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
# Finds the open upstream-sync PR targeting fork_upstream, if any.
#
# Env: GITHUB_TOKEN

set -euo pipefail

echo "Detecting existing sync PRs..."

OPEN_SYNC_PRS=$(gh pr list \
  --state open \
  --label "upstream-sync" \
  --json number,title,headRefName,baseRefName \
  --jq '.[] | select(.baseRefName == "fork_upstream")')

echo "Open sync PRs found:"
echo "$OPEN_SYNC_PRS" | jq -r '. | "PR #\(.number): \(.title) (\(.headRefName))"' || echo "None"

if [[ -n "$OPEN_SYNC_PRS" ]] && [[ "$OPEN_SYNC_PRS" != "null" ]]; then
  PR_NUMBER=$(echo "$OPEN_SYNC_PRS" | jq -r '.number' | head -1)
  PR_BRANCH=$(echo "$OPEN_SYNC_PRS" | jq -r '.headRefName' | head -1)
  HAS_EXISTING_PR="true"
else
  PR_NUMBER=""
  PR_BRANCH=""
  HAS_EXISTING_PR="false"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "existing_pr_number=$PR_NUMBER" >> "$GITHUB_OUTPUT"
  echo "existing_pr_branch=$PR_BRANCH" >> "$GITHUB_OUTPUT"
  echo "has_existing_pr=$HAS_EXISTING_PR" >> "$GITHUB_OUTPUT"
fi

echo "existing_pr_number=$PR_NUMBER"
echo "existing_pr_branch=$PR_BRANCH"
echo "has_existing_pr=$HAS_EXISTING_PR"