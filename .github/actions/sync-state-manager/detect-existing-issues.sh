#!/usr/bin/env bash
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