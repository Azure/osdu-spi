#!/bin/sh
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
