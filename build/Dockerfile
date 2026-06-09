# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical service container image for OSDU SPI Java services (ADR-037).
# Owned by the engineering system and synced to every fork; services do not supply their own.
# Mirrors the OSDU community service-base-image (java/Dockerfile): the prebuilt Spring Boot JAR
# produced by the java-build job is copied in via JAR_FILE — no Maven runs in this image build.
#
# Base: Microsoft Build of OpenJDK 17 on Azure Linux (MCR) — multi-arch (amd64+arm64) so release
# images pull natively on Apple Silicon and amd64. Digest-pinned for reproducibility; the docker
# Dependabot ecosystem (template only) bumps this digest as a PR and template-sync propagates it
# to every fork — forks never author their own base bump (ADR-037).
FROM mcr.microsoft.com/openjdk/jdk:17-azurelinux@sha256:b5184552440ea3a3f2100ca08b538066d61d8d1800da2b3a18818c4b6fcbe7f5

ARG JAR_FILE
ARG APPLICATIONINSIGHTS_CONNECTION_STRING="dummy"
ARG AZURE_MSI_ENABLED="true"
ARG JAVA_OPTS=""
# App Insights Java agent (Azure Monitor). The MCR base does not bundle it like OSDU's alpine-zulu17
# did, so we bake the same /opt/agents/ path here. Pinned by version + sha256; bumping the version
# requires updating the checksum (ADR-037). The agent is the arch-independent jar — no RUN, so the
# arm64 leg stays cheap. The entrypoint attaches it only when a real connection string is set.
ARG APPLICATIONINSIGHTS_AGENT_VERSION="3.7.8"
ADD --checksum=sha256:e8c494f3f9a36f6b99790a4741b03f51988dc5c4244c14cc24be51874ef72e6b \
    https://repo1.maven.org/maven2/com/microsoft/azure/applicationinsights-agent/${APPLICATIONINSIGHTS_AGENT_VERSION}/applicationinsights-agent-${APPLICATIONINSIGHTS_AGENT_VERSION}.jar \
    /opt/agents/applicationinsights-agent.jar

COPY ${JAR_FILE} /app.jar
COPY --chmod=0755 build/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENV APPLICATIONINSIGHTS_CONNECTION_STRING=${APPLICATIONINSIGHTS_CONNECTION_STRING}
ENV DEFAULT_JVM_OPTS="-XX:+UseG1GC -XX:InitialRAMPercentage=25.0 -XX:MaxRAMPercentage=50.0 -XX:+HeapDumpOnOutOfMemoryError -Dlog4j2.formatMsgNoLookups=true"
ENV JAVA_OPTS="${DEFAULT_JVM_OPTS} ${JAVA_OPTS}"
ENV AZURE_MSI_ISENABLED="${AZURE_MSI_ENABLED}"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
