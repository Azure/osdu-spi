#!/bin/sh
# Canonical container entrypoint for OSDU SPI Java services (ADR-037), synced to every fork.
# Attaches the Application Insights Java agent only when a real connection string is configured.
# The image default is the sentinel "dummy", so local / unconfigured runs start clean instead of
# emitting agent errors; production passes a real APPLICATIONINSIGHTS_CONNECTION_STRING and gets
# codeless instrumentation, matching the agent OSDU's base image used to bake in.
set -eu

AGENT_OPT=""
if [ -n "${APPLICATIONINSIGHTS_CONNECTION_STRING:-}" ] && \
   [ "${APPLICATIONINSIGHTS_CONNECTION_STRING}" != "dummy" ] && \
   [ -f /opt/agents/applicationinsights-agent.jar ]; then
  AGENT_OPT="-javaagent:/opt/agents/applicationinsights-agent.jar"
fi

# JAVA_OPTS / AGENT_OPT are intentionally unquoted so each flag word-splits into a separate arg.
# shellcheck disable=SC2086
exec java ${AGENT_OPT} ${JAVA_OPTS} -jar /app.jar
