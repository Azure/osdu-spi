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
