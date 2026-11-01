# syntax=docker/dockerfile:1.24.0@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Canonical service image, owned by the engineering system and synced to every fork (ADR-037).
# Mirrors the OSDU community service-base-image: the JAR that java-build compiled is copied in
# via JAR_FILE, and no Maven runs here.
#
# Multi-arch base so release images pull natively on Apple Silicon. JAVA_VERSION is the release
# the fork's root pom declares (java-release action); one stage per release keeps each digest on
# a FROM line where Dependabot bumps it in the template, and template-sync carries it to the forks.
ARG JAVA_VERSION=17
FROM mcr.microsoft.com/openjdk/jdk:17-azurelinux@sha256:17863b3888bce74d34cca07cacdc45ea2fe0f49dd2b0c22956e4ddc51b1886f7 AS runtime-17
FROM mcr.microsoft.com/openjdk/jdk:25-azurelinux@sha256:d3215d9ab2fc5f2ee7e3a77e83c9750f18b70a735a4514f5b2d3c5861bce4905 AS runtime-25

# The MCR base does not bundle the App Insights agent that OSDU's base image did, so it is
# fetched here, on the builder's platform so the arm64 leg needs no emulation, and its bundled
# license and notice files are read out of the same verified bytes. Bumping the version means
# updating the checksum.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/openjdk/jdk:17-azurelinux@sha256:17863b3888bce74d34cca07cacdc45ea2fe0f49dd2b0c22956e4ddc51b1886f7 AS agent
ARG APPLICATIONINSIGHTS_AGENT_VERSION="3.7.8"
ADD --checksum=sha256:e8c494f3f9a36f6b99790a4741b03f51988dc5c4244c14cc24be51874ef72e6b \
    https://repo1.maven.org/maven2/com/microsoft/azure/applicationinsights-agent/${APPLICATIONINSIGHTS_AGENT_VERSION}/applicationinsights-agent-${APPLICATIONINSIGHTS_AGENT_VERSION}.jar \
    /agent/applicationinsights-agent.jar
WORKDIR /agent/notices
RUN jar tf ../applicationinsights-agent.jar | grep -iE 'license|notice' | grep -v '/$' \
      | xargs jar xf ../applicationinsights-agent.jar \
    && test -f META-INF/LICENSE

FROM runtime-${JAVA_VERSION}

ARG JAR_FILE
ARG APPLICATIONINSIGHTS_CONNECTION_STRING="dummy"
ARG AZURE_MSI_ENABLED="true"
ARG JAVA_OPTS=""

# Named one by one so a missing file fails the build instead of shipping without it.
COPY LICENSE NOTICE NOTICE-OSDU-SPI /licenses/
COPY --from=agent /agent/notices/ /licenses/applicationinsights-agent/
COPY --from=agent /agent/applicationinsights-agent.jar /opt/agents/applicationinsights-agent.jar

COPY ${JAR_FILE} /app.jar
COPY --chmod=0755 build/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENV APPLICATIONINSIGHTS_CONNECTION_STRING=${APPLICATIONINSIGHTS_CONNECTION_STRING}
ENV DEFAULT_JVM_OPTS="-XX:+UseG1GC -XX:InitialRAMPercentage=25.0 -XX:MaxRAMPercentage=50.0 -XX:+HeapDumpOnOutOfMemoryError -Dlog4j2.formatMsgNoLookups=true"
ENV JAVA_OPTS="${DEFAULT_JVM_OPTS} ${JAVA_OPTS}"
ENV AZURE_MSI_ISENABLED="${AZURE_MSI_ENABLED}"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
