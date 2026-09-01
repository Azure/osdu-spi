# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical service image, owned by the engineering system and synced to every fork (ADR-037).
# Mirrors the OSDU community service-base-image: the JAR that java-build compiled is copied in
# via JAR_FILE, and no Maven runs here.
#
# Multi-arch base so release images pull natively on Apple Silicon. Dependabot bumps the digest
# in the template only; template-sync carries it to the forks.
FROM mcr.microsoft.com/openjdk/jdk:17-azurelinux@sha256:b5184552440ea3a3f2100ca08b538066d61d8d1800da2b3a18818c4b6fcbe7f5

ARG JAR_FILE
ARG APPLICATIONINSIGHTS_CONNECTION_STRING="dummy"
ARG AZURE_MSI_ENABLED="true"
ARG JAVA_OPTS=""
# The MCR base does not bundle the App Insights agent that OSDU's base image did, so it is
# fetched to the same /opt/agents/ path. Bumping the version means updating the checksum.
# ADD rather than RUN keeps the arm64 leg free of emulation.
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
