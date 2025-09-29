#!/usr/bin/env bash
#
# Detect Existing Sync Issues Script
#
# Queries GitHub API for open issues with upstream-sync label.
#
# Arguments:
#   None
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI
#
# Outputs:
#   existing_issue_number - Issue number if found
#   has_existing_issue - true/false
#
# Usage:
#   export GITHUB_TOKEN="ghp_token"
#   ./detect-existing-issues.sh

set -euo pipefail

echo "Detecting existing sync issues..."

# Query GitHub API for open issues with upstream-sync label
OPEN_SYNC_ISSUES=$(gh issue list \
  --state open \
  --label "upstream-sync" \
  --json number,title)

echo "Open sync issues found:"
echo "$OPEN_SYNC_ISSUES" | jq -r '.[] | "Issue #\(.number): \(.title)"' || echo "None"

# Extract first issue details if any exist
if [[ -n "$OPEN_SYNC_ISSUES" ]] && [[ "$OPEN_SYNC_ISSUES" != "[]" ]]; then
  ISSUE_NUMBER=$(echo "$OPEN_SYNC_ISSUES" | jq -r '.[0].number')
  HAS_EXISTING_ISSUE="true"
else
  ISSUE_NUMBER=""
  HAS_EXISTING_ISSUE="false"
fi

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "existing_issue_number=$ISSUE_NUMBER" >> "$GITHUB_OUTPUT"
  echo "has_existing_issue=$HAS_EXISTING_ISSUE" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "existing_issue_number=$ISSUE_NUMBER"
echo "has_existing_issue=$HAS_EXISTING_ISSUE"