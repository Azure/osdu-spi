#!/usr/bin/env bash
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

#
# Builds an unreviewed tree with Maven in a throwaway container that sees only the workspace,
# the JDK and Maven. The runner's Actions cache token, credentials and ~/.m2 stay outside, so
# build code cannot plant a cache entry that a trusted build later restores. .git is read-only so
# nothing it writes there runs in a later host git command (checkout's post-job cleanup).
#
# Env:
#   JAVA_HOME      - JDK mounted read-only (actions/setup-java)
#   M2_HOME        - Maven mounted read-only (setup-maven)
#   SANDBOX_IMAGE  - digest-pinned base image; supplies only libc and coreutils
#   MAVEN_PROFILE  - profile list for -P; empty passes none
#   BUILD_ENV      - the fork's BUILD_ENV variable, exported into the container (build-env.sh)
#
# Local: GITHUB_WORKSPACE=$PWD GITHUB_REF_NAME=main RUNNER_TEMP=$(mktemp -d) plus the Env above.

set -euo pipefail

env_file="$RUNNER_TEMP/sandbox-build.env"
: > "$env_file"
GITHUB_ENV="$env_file" bash "$(dirname "$0")/build-env.sh"

safe_ref=$(printf '%s' "$GITHUB_REF_NAME" | tr -c 'A-Za-z0-9._' '-' | tr -s '-')
args=(--batch-mode --show-version "-Drevision=${safe_ref}-SNAPSHOT" -Dmaven.repo.local=/tmp/m2)
if [ -f .mvn/community-maven.settings.xml ]; then
  args+=(--settings=.mvn/community-maven.settings.xml)
fi
if [ -n "${MAVEN_PROFILE:-}" ]; then
  args+=(-P "$MAVEN_PROFILE")
fi

# exec: this script sits in the writable mount, and bash would read anything the build appends.
exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  --cap-drop ALL --security-opt no-new-privileges \
  --env-file "$env_file" \
  -e HOME=/tmp \
  -e MAVEN_OPTS=-Duser.home=/tmp \
  -e "JAVA_HOME=$JAVA_HOME" \
  -e "PATH=$JAVA_HOME/bin:$M2_HOME/bin:/usr/bin:/bin" \
  -v "$JAVA_HOME:$JAVA_HOME:ro" \
  -v "$M2_HOME:$M2_HOME:ro" \
  -v "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE" \
  -v "$GITHUB_WORKSPACE/.git:$GITHUB_WORKSPACE/.git:ro" \
  -w "$GITHUB_WORKSPACE" \
  "$SANDBOX_IMAGE" \
  mvn "${args[@]}" clean install
