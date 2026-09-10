#!/bin/sh
# Entrypoint for build/acceptance.Dockerfile. Arguments are Maven argv tokens appended
# verbatim; the environment arrives via --env-file from the acceptance resolver.
# SUITE_DIR selects the suite (a tests.<name>.path from .spi/service.yaml); the build's
# first suite is the default.
set -e
SUITE_DIR="${SUITE_DIR:-$(cat /suite/.default-suite-dir)}"
if [ ! -f "/suite/$SUITE_DIR/pom.xml" ]; then
  echo "SUITE_DIR '$SUITE_DIR' is not a suite baked into this image" >&2
  exit 2
fi
cd "/suite/$SUITE_DIR"
echo "Running suite $SUITE_DIR: mvn $*" >&2
if [ -f /suite/.mvn/community-maven.settings.xml ]; then
  exec mvn -B --no-transfer-progress --settings /suite/.mvn/community-maven.settings.xml "$@"
fi
exec mvn -B --no-transfer-progress "$@"
