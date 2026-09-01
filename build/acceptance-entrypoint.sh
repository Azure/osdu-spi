#!/bin/sh
# Entrypoint for the canonical acceptance image (build/acceptance.Dockerfile).
# Arguments are Maven argv tokens — the descriptor's mavenArguments, appended
# verbatim (default CMD: verify). Environment arrives via --env-file from the
# acceptance resolver.
set -e
cd /suite
if [ -f /suite/.mvn/community-maven.settings.xml ]; then
  exec mvn -B --no-transfer-progress --settings /suite/.mvn/community-maven.settings.xml "$@"
fi
exec mvn -B --no-transfer-progress "$@"
