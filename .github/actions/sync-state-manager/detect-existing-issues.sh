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
# Finds the open upstream-sync tracking issue, if any.
#
# Env: GITHUB_TOKEN

set -euo pipefail

echo "Detecting existing sync issues..."

OPEN_SYNC_ISSUES=$(gh issue list \
  --state open \
  --label "upstream-sync" \
  --json number,title)

echo "Open sync issues found:"
echo "$OPEN_SYNC_ISSUES" | jq -r '.[] | "Issue #\(.number): \(.title)"' || echo "None"

if [[ -n "$OPEN_SYNC_ISSUES" ]] && [[ "$OPEN_SYNC_ISSUES" != "[]" ]]; then
  ISSUE_NUMBER=$(echo "$OPEN_SYNC_ISSUES" | jq -r '.[0].number')
  HAS_EXISTING_ISSUE="true"
else
  ISSUE_NUMBER=""
  HAS_EXISTING_ISSUE="false"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "existing_issue_number=$ISSUE_NUMBER" >> "$GITHUB_OUTPUT"
  echo "has_existing_issue=$HAS_EXISTING_ISSUE" >> "$GITHUB_OUTPUT"
fi

echo "existing_issue_number=$ISSUE_NUMBER"
echo "has_existing_issue=$HAS_EXISTING_ISSUE"