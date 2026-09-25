#!/bin/bash
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

# Sets the github-actions[bot] commit identity.
#
# Inputs (via environment):
#   PULL_REBASE - sets pull.rebase when "true" or "false"

set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

if [[ "${PULL_REBASE:-}" == "true" ]]; then
    git config pull.rebase true
elif [[ "${PULL_REBASE:-}" == "false" ]]; then
    git config pull.rebase false
fi

echo "✅ Git configured for github-actions[bot]"