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
# Exports a fork's BUILD_ENV repository variable into the job environment so the
# Maven steps that follow see it. BUILD_ENV holds KEY=VALUE lines; blank lines and
# lines starting with # are skipped. In a value, $GITHUB_WORKSPACE and
# ${GITHUB_WORKSPACE} become the checkout root and nothing else expands.
#
# Environment:
#   BUILD_ENV        - the variable's value; empty or unset exports nothing
#   GITHUB_WORKSPACE - the checkout root
#   GITHUB_ENV       - the runner's environment file, appended to

set -euo pipefail

if [[ -z "${BUILD_ENV:-}" ]]; then
  exit 0
fi

# Names the runner, the toolchain setup or the build steps own.
RESERVED='^(GITHUB_|RUNNER_|ACTIONS_)|^(PATH|HOME|SHELL|ENV|BASH_ENV|CI|JAVA_HOME|M2_HOME|MAVEN_HOME|MAVEN_OPTS|MAVEN_PROFILE|GENERATE_COVERAGE|NODE_OPTIONS|LD_PRELOAD|LD_LIBRARY_PATH)$'

# Unbraced $GITHUB_WORKSPACE not followed by a name character, so $GITHUB_WORKSPACE_X stays literal.
# shellcheck disable=SC2016
WORKSPACE_TOKEN='^(.*)\$GITHUB_WORKSPACE([^A-Za-z0-9_].*)?$'

exported=()
lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  line="${line%$'\r'}"
  if [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]]; then
    continue
  fi
  key="${line%%=*}"
  if [[ "$line" != *=* || ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "::error::BUILD_ENV line $lineno is not KEY=VALUE with KEY made of letters, digits and _"
    exit 1
  fi
  if [[ "$key" =~ $RESERVED ]]; then
    echo "::error::BUILD_ENV line $lineno sets $key, which the runner or the build owns"
    exit 1
  fi
  value="${line#*=}"
  value="${value//\$\{GITHUB_WORKSPACE\}/$GITHUB_WORKSPACE}"
  expanded=""
  while [[ "$value" =~ $WORKSPACE_TOKEN ]]; do
    expanded="$GITHUB_WORKSPACE${BASH_REMATCH[2]}$expanded"
    value="${BASH_REMATCH[1]}"
  done
  value="$value$expanded"
  printf '%s=%s\n' "$key" "$value" >> "$GITHUB_ENV"
  exported+=("$key")
done <<< "$BUILD_ENV"

if [[ ${#exported[@]} -gt 0 ]]; then
  echo "Build environment from BUILD_ENV: ${exported[*]}"
fi
