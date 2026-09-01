#!/bin/sh
# Entrypoint for build/acceptance.Dockerfile. Arguments are Maven argv tokens appended
# verbatim; the environment arrives via --env-file from the acceptance resolver.
set -e
cd /suite
if [ -f /suite/.mvn/community-maven.settings.xml ]; then
  exec mvn -B --no-transfer-progress --settings /suite/.mvn/community-maven.settings.xml "$@"
fi
exec mvn -B --no-transfer-progress "$@"
