#!/bin/sh
# Canonical service entrypoint, synced to every fork (ADR-037). The App Insights agent is
# attached only when a real connection string is set; the image default "dummy" keeps local
# runs free of agent errors.
set -eu

AGENT_OPT=""
if [ -n "${APPLICATIONINSIGHTS_CONNECTION_STRING:-}" ] && \
   [ "${APPLICATIONINSIGHTS_CONNECTION_STRING}" != "dummy" ] && \
   [ -f /opt/agents/applicationinsights-agent.jar ]; then
  AGENT_OPT="-javaagent:/opt/agents/applicationinsights-agent.jar"
fi

# Unquoted on purpose so each flag word-splits into its own argument.
# shellcheck disable=SC2086
exec java ${AGENT_OPT} ${JAVA_OPTS} -jar /app.jar
