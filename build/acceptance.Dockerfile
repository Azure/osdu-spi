# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical test-suite image, owned by the engineering system and synced to every fork
# (ADR-037 posture). Bakes every suite the descriptor declares from the same commit as the
# service image, with each suite's dependencies prewarmed, so the tests that shipped with a
# release stay one command later:
#
#   docker run --env-file .env -e SUITE_DIR=<path> ghcr.io/<org>/<svc>-acceptance:sha-<sha> [argv...]
#
# SUITE_DIR is a tests.<name>.path from .spi/service.yaml and defaults to the acceptance suite.
# The argv goes to Maven, or to pytest for a suite of type pytest.
# The select stage carves only the declared suites, the Maven settings, and the descriptor out
# of the checkout, so the service source never ships and scanners see only what the suites use.
#
# Only the suite source and a warmed local repository are pinned. The run is online, and where
# the upstream graph carries version ranges (os-core-test pulls io.cucumber ranges) a later run
# can resolve a different set; the prewarm caches artifacts, not range metadata. A fork that
# wants a frozen set pins the ranges in its own suite pom.
#
# amd64 only: this build runs Maven, and under QEMU arm64 emulation that costs minutes per push
# with no consumer. CI runners are amd64 and Apple Silicon runs the amd64 image emulated.
ARG JAVA_VERSION=17
FROM docker.io/library/alpine:3.22@sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f AS select
# Space-separated suite paths; the first is the run-time default.
ARG SUITE_DIRS
# Space-separated dir=requirements[,requirements...] for each suite of type pytest.
ARG PYTEST_SUITES=""
COPY . /src/
RUN set -eu; mkdir -p /suite; \
    for dir in ${SUITE_DIRS:?SUITE_DIRS build-arg is required}; do \
      mkdir -p "/suite/$dir"; cp -R "/src/$dir/." "/suite/$dir/"; \
    done; \
    if [ -d /src/.mvn ]; then cp -R /src/.mvn /suite/.mvn; fi; \
    if [ -d /src/.spi ]; then cp -R /src/.spi /suite/.spi; fi; \
    printf '%s' "${SUITE_DIRS%% *}" > /suite/.default-suite-dir; \
    : > /suite/.pytest-suites; \
    for spec in ${PYTEST_SUITES}; do echo "${spec%%=*}" >> /suite/.pytest-suites; done

# JAVA_VERSION is the release the fork's root pom declares, one stage per release as in build/Dockerfile.
FROM docker.io/library/maven:3.9-eclipse-temurin-17@sha256:1a352420f7aba21f5ad08df31bab55f74c013fb491f1ae8ab1dd7ff9ed698584 AS maven-17
FROM docker.io/library/maven:3.9-eclipse-temurin-25@sha256:93b8a14ea2f412782e4e842651273b4d903e35cc496284f178fbbe2d67d00976 AS maven-25
FROM maven-${JAVA_VERSION}

ARG SUITE_DIRS
ARG PYTEST_SUITES=""
# Python packages come through the Microsoft package feed proxy, never the public index directly.
ARG PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple/
WORKDIR /suite
COPY --from=select /suite/ /suite/
COPY LICENSE NOTICE NOTICE-OSDU-SPI /licenses/
COPY --chmod=0755 build/acceptance-entrypoint.sh /usr/local/bin/acceptance-entrypoint.sh

# Each suite resolves its own graph; a multi-module suite (a testing/ reactor whose provider
# module depends on a sibling core module) also needs that sibling installed, so the reactor is
# installed first. -DskipITs as well as -DskipTests, because a failsafe execution that sets its
# own <skipTests> ignores the user property. resolve, not go-offline: go-offline also fetches
# conflict losers and unevaluated classifiers the mediated build never uses.
# Surefire and failsafe fetch their test provider only when a run selects test classes, so
# verify runs once with a method filter no test method matches. A suite runner (a JUnit Platform
# @Suite, Cucumber) does not apply that filter to its scenarios, so Cucumber's dry run is set too:
# the forked JVM gets it as a system property, which Cucumber 5+ reads through both its JUnit 4
# runner and its JUnit Platform engine, and no hook or step body runs. Anything that still errors
# without the suite's environment is ignored, and its reports are removed so a suite verdict reads
# only a real run. The filter goes through -Dtest/-Dit.test: plugins older than 3.0.0-M6 reject
# one in an excludes file.
RUN set -eu; \
    SETTINGS=""; \
    if [ -f /suite/.mvn/community-maven.settings.xml ]; then SETTINGS="--settings /suite/.mvn/community-maven.settings.xml"; fi; \
    for dir in ${SUITE_DIRS:?SUITE_DIRS build-arg is required}; do \
      if grep -qxF "$dir" /suite/.pytest-suites; then continue; fi; \
      echo "==> prewarming $dir"; \
      if grep -q "<modules>" "/suite/$dir/pom.xml"; then \
        mvn -B -q --no-transfer-progress $SETTINGS -f "/suite/$dir/pom.xml" install -DskipTests -DskipITs; \
      fi; \
      mvn -B --no-transfer-progress $SETTINGS -f "/suite/$dir/pom.xml" dependency:resolve dependency:resolve-plugins; \
      mvn -B -q --no-transfer-progress $SETTINGS -f "/suite/$dir/pom.xml" verify \
        '-Dtest=**/*#spiPrewarmNoTestMethod' '-Dit.test=**/*#spiPrewarmNoTestMethod' \
        -Dsurefire.failIfNoSpecifiedTests=false -Dit.failIfNoSpecifiedTests=false \
        -Dcucumber.execution.dry-run=true -Dmaven.test.failure.ignore=true; \
    done; \
    find /suite -type d \( -name surefire-reports -o -name failsafe-reports \) -prune -exec rm -rf {} +

# Each pytest suite gets its own virtual environment under /opt/spi-venv, named for its path
# with / as + (a character suite paths cannot hold). pip runs from the suite directory so
# local requirements such as -e . resolve there.
# The proxy is a pull-through cache whose first fetch of an uncached file can fail, and pip
# does not retry an HTTP error status, so the install is retried as a whole.
RUN set -eu; \
    if [ -n "${PYTEST_SUITES}" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends python3 python3-venv; \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    for spec in ${PYTEST_SUITES}; do \
      dir="${spec%%=*}"; venv="/opt/spi-venv/$(printf '%s' "$dir" | tr / +)"; \
      echo "==> installing $dir into $venv"; \
      python3 -m venv "$venv"; \
      set --; \
      IFS=,; for file in ${spec#*=}; do set -- "$@" -r "/suite/$dir/$file"; done; unset IFS; \
      ( cd "/suite/$dir"; attempt=1; \
        until "$venv/bin/pip" install --disable-pip-version-check --no-cache-dir \
            --index-url "$PIP_INDEX_URL" "$@" pytest; do \
          [ "$attempt" -lt 3 ] || exit 1; attempt=$((attempt + 1)); sleep 15; \
        done ); \
    done

# Arguments are argv tokens for the suite's runner, never a shell string.
ENTRYPOINT ["/usr/local/bin/acceptance-entrypoint.sh"]
