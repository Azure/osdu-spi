# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical acceptance test image, owned by the engineering system and synced to every fork
# (ADR-037 posture). Bakes the suite source from the same commit as the service image with
# dependencies prewarmed, so the tests that shipped with a release stay one command later:
#
#   docker run --env-file .env ghcr.io/<org>/<svc>-acceptance:sha-<sha> [maven argv...]
#
# Only the suite source and a warmed local repository are pinned. The run is online, and where
# the upstream graph carries version ranges (os-core-test pulls io.cucumber ranges) a later run
# can resolve a different set; go-offline caches artifacts, not range metadata. A fork that
# wants a frozen set pins the ranges in its own suite pom.
#
# SUITE_DIR defaults to <svc>-acceptance-test; the acceptance-image action honors the
# descriptor override (ADR-040). The module must build standalone, as upstream's do.
#
# amd64 only: this build runs Maven, and under QEMU arm64 emulation that costs minutes per push
# with no consumer. CI runners are amd64 and Apple Silicon runs the amd64 image emulated.
FROM docker.io/library/maven:3.9-eclipse-temurin-17@sha256:a8746f15d5bb26b5b8bacb056cc76211553850f4c71d16aff845cfa004cbc197

ARG SUITE_DIR
WORKDIR /suite
# Settings before source: the community-repo profile rarely changes, the suite does. The glob
# makes .mvn/ optional; the sidecar acceptance.Dockerfile.dockerignore keeps upstream's root
# .dockerignore (`.*`) from filtering it out where it does exist.
COPY .mvn*/ /suite/.mvn/
COPY ${SUITE_DIR}/ /suite/
COPY --chmod=0755 build/acceptance-entrypoint.sh /usr/local/bin/acceptance-entrypoint.sh

RUN if [ -f /suite/.mvn/community-maven.settings.xml ]; then \
      mvn -B --no-transfer-progress --settings /suite/.mvn/community-maven.settings.xml dependency:go-offline; \
    else \
      mvn -B --no-transfer-progress dependency:go-offline; \
    fi

# Arguments are Maven argv tokens, never a shell string.
ENTRYPOINT ["/usr/local/bin/acceptance-entrypoint.sh"]
CMD ["verify"]
