# Canonical service container image for OSDU SPI Java services (ADR-037).
# Owned by the engineering system and synced to every fork; services do not supply their own.
# Mirrors the OSDU community service-base-image (java/Dockerfile): the prebuilt Spring Boot JAR
# produced by the java-build job is copied in via JAR_FILE — no Maven runs in this image build.
ARG BASE_IMAGE="community.opengroup.org:5555/osdu/platform/deployment-and-operations/base-containers-azure/alpine-zulu17:0.0.6"
FROM ${BASE_IMAGE}

ARG JAR_FILE
ARG APPLICATIONINSIGHTS_CONNECTION_STRING="dummy"
ARG AZURE_MSI_ENABLED="true"
ARG JAVA_OPTS=""

COPY ${JAR_FILE} /app.jar

ENV APPLICATIONINSIGHTS_CONNECTION_STRING=${APPLICATIONINSIGHTS_CONNECTION_STRING}
ENV DEFAULT_JVM_OPTS="-XX:+UseG1GC -XX:InitialRAMPercentage=25.0 -XX:MaxRAMPercentage=50.0 -XX:+HeapDumpOnOutOfMemoryError -Dlog4j2.formatMsgNoLookups=true"
ENV JAVA_OPTS="${DEFAULT_JVM_OPTS} ${JAVA_OPTS}"
ENV AZURE_MSI_ISENABLED="${AZURE_MSI_ENABLED}"

ENTRYPOINT ["/bin/sh", "-c", "exec java $JAVA_OPTS -jar /app.jar"]
