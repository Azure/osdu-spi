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
# Prints the SHA of the upstream remote's default branch.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <default_branch>"
  exit 1
fi

DEFAULT_BRANCH="$1"

UPSTREAM_SHA=$(git rev-parse "upstream/$DEFAULT_BRANCH")
echo "Current upstream SHA: $UPSTREAM_SHA"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "upstream_sha=$UPSTREAM_SHA" >> "$GITHUB_OUTPUT"
fi

echo "upstream_sha=$UPSTREAM_SHA"