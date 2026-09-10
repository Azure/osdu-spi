# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical test-suite image, owned by the engineering system and synced to every fork
# (ADR-037 posture). Bakes every suite the descriptor declares from the same commit as the
# service image, with each suite's dependencies prewarmed, so the tests that shipped with a
# release stay one command later:
#
#   docker run --env-file .env -e SUITE_DIR=<path> ghcr.io/<org>/<svc>-acceptance:sha-<sha> [maven argv...]
#
# SUITE_DIR is a tests.<name>.path from .spi/service.yaml and defaults to the acceptance suite.
# The select stage carves only the declared suites, the Maven settings, and the descriptor out
# of the checkout, so the service source never ships and scanners see only what the suites use.
#
# Only the suite source and a warmed local repository are pinned. The run is online, and where
# the upstream graph carries version ranges (os-core-test pulls io.cucumber ranges) a later run
# can resolve a different set; go-offline caches artifacts, not range metadata. A fork that
# wants a frozen set pins the ranges in its own suite pom.
#
# amd64 only: this build runs Maven, and under QEMU arm64 emulation that costs minutes per push
# with no consumer. CI runners are amd64 and Apple Silicon runs the amd64 image emulated.
FROM docker.io/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS select
# Space-separated suite paths; the first is the run-time default.
ARG SUITE_DIRS
COPY . /src/
RUN set -eu; mkdir -p /suite; \
    for dir in ${SUITE_DIRS:?SUITE_DIRS build-arg is required}; do \
      mkdir -p "/suite/$dir"; cp -R "/src/$dir/." "/suite/$dir/"; \
    done; \
    if [ -d /src/.mvn ]; then cp -R /src/.mvn /suite/.mvn; fi; \
    if [ -d /src/.spi ]; then cp -R /src/.spi /suite/.spi; fi; \
    printf '%s' "${SUITE_DIRS%% *}" > /suite/.default-suite-dir

FROM docker.io/library/maven:3-eclipse-temurin-26@sha256:2bc6924d954a6efefde0a9629228914acf72e4abcdb927b68f19edd1135a0cb1

ARG SUITE_DIRS
WORKDIR /suite
COPY --from=select /suite/ /suite/
COPY --chmod=0755 build/acceptance-entrypoint.sh /usr/local/bin/acceptance-entrypoint.sh

# Each suite resolves its own graph; a multi-module suite (a testing/ reactor whose provider
# module depends on a sibling core module) also needs that sibling installed, which
# go-offline does not do, so the reactor is installed without running its tests first.
RUN set -eu; \
    SETTINGS=""; \
    if [ -f /suite/.mvn/community-maven.settings.xml ]; then SETTINGS="--settings /suite/.mvn/community-maven.settings.xml"; fi; \
    for dir in ${SUITE_DIRS:?SUITE_DIRS build-arg is required}; do \
      echo "==> prewarming $dir"; \
      if grep -q "<modules>" "/suite/$dir/pom.xml"; then \
        mvn -B -q --no-transfer-progress $SETTINGS -f "/suite/$dir/pom.xml" install -DskipTests; \
      fi; \
      mvn -B --no-transfer-progress $SETTINGS -f "/suite/$dir/pom.xml" dependency:go-offline; \
    done

# Arguments are Maven argv tokens, never a shell string.
ENTRYPOINT ["/usr/local/bin/acceptance-entrypoint.sh"]
CMD ["verify"]
