# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical acceptance test image for OSDU SPI Java services (extends the ADR-037 posture:
# owned by the engineering system, synced to every fork; services do not supply their own).
#
# Bakes the acceptance suite SOURCE from the same commit as the service image, with Maven
# dependencies prewarmed at build time (dependency:go-offline) — so "run the tests that shipped
# with release X" stays one command months later.
#
# What the image pins is the suite source and a warmed local repository; dependency RESOLUTION
# is not pinned. The run is online by design, and where the upstream graph carries version
# ranges (os-core-test pulls io.cucumber ranges today) a later run can resolve a different set:
# go-offline caches artifacts, not the range metadata a resolve consults. Registry availability
# is still required — `--offline` fails on those ranges. A fork wanting a frozen dependency set
# must pin the ranges in its own suite pom.
#
# The suite executes at container run time against a live gateway:
#
#   docker run --env-file .env ghcr.io/<org>/<svc>-acceptance:sha-<sha> [maven argv...]
#
# SUITE_DIR is the repository-relative suite module: default <svc>-acceptance-test (the
# upstream module kept by the filter), descriptor override honored by the acceptance-image
# action (ADR-040). The module must build standalone — the upstream acceptance modules are
# parentless by design.
#
# amd64-only, deliberately (unlike the multi-arch service image): this build RUNs Maven, and
# under QEMU arm64 emulation that costs many minutes per push for no consumer — CI runners
# are amd64 and Apple Silicon runs the amd64 image under emulation. A need for native arm64
# local runs is the signal to revisit, not to silently flip.
FROM docker.io/library/maven:3.9-eclipse-temurin-17@sha256:a8746f15d5bb26b5b8bacb056cc76211553850f4c71d16aff845cfa004cbc197

ARG SUITE_DIR
WORKDIR /suite
# Settings before source: the community-repo profile rarely changes, the suite does.
# The glob makes root .mvn/ optional, matching every other consumer in the fork (java-build,
# validate, cascade) and keeping the settings-less branch of the RUN below reachable; the
# sidecar acceptance.Dockerfile.dockerignore is what stops the upstream root .dockerignore
# (`.*`) from filtering it out where it does exist.
COPY .mvn*/ /suite/.mvn/
COPY ${SUITE_DIR}/ /suite/
COPY --chmod=0755 build/acceptance-entrypoint.sh /usr/local/bin/acceptance-entrypoint.sh

RUN if [ -f /suite/.mvn/community-maven.settings.xml ]; then \
      mvn -B --no-transfer-progress --settings /suite/.mvn/community-maven.settings.xml dependency:go-offline; \
    else \
      mvn -B --no-transfer-progress dependency:go-offline; \
    fi

# Arguments are Maven argv tokens (the descriptor's mavenArguments, never a shell string).
ENTRYPOINT ["/usr/local/bin/acceptance-entrypoint.sh"]
CMD ["verify"]
