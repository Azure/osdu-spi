#!/usr/bin/env bash
#
# Detect Existing Sync PRs Script
#
# Queries GitHub API for open PRs with upstream-sync label targeting fork_upstream.
#
# Arguments:
#   None
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI
#
# Outputs:
#   existing_pr_number - PR number if found
#   existing_pr_branch - PR head branch if found
#   has_existing_pr - true/false
#
# Usage:
#   export GITHUB_TOKEN="ghp_token"
#   ./detect-existing-prs.sh

set -euo pipefail

echo "Detecting existing sync PRs..."

# Query GitHub API for open PRs with upstream-sync label
OPEN_SYNC_PRS=$(gh pr list \
  --state open \
  --label "upstream-sync" \
  --json number,title,headRefName,baseRefName \
  --jq '.[] | select(.baseRefName == "fork_upstream")')

echo "Open sync PRs found:"
echo "$OPEN_SYNC_PRS" | jq -r '. | "PR #\(.number): \(.title) (\(.headRefName))"' || echo "None"

# Extract first PR details if any exist
if [[ -n "$OPEN_SYNC_PRS" ]] && [[ "$OPEN_SYNC_PRS" != "null" ]]; then
  PR_NUMBER=$(echo "$OPEN_SYNC_PRS" | jq -r '.number' | head -1)
  PR_BRANCH=$(echo "$OPEN_SYNC_PRS" | jq -r '.headRefName' | head -1)
  HAS_EXISTING_PR="true"
else
  PR_NUMBER=""
  PR_BRANCH=""
  HAS_EXISTING_PR="false"
fi

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "existing_pr_number=$PR_NUMBER" >> "$GITHUB_OUTPUT"
  echo "existing_pr_branch=$PR_BRANCH" >> "$GITHUB_OUTPUT"
  echo "has_existing_pr=$HAS_EXISTING_PR" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "existing_pr_number=$PR_NUMBER"
echo "existing_pr_branch=$PR_BRANCH"
echo "has_existing_pr=$HAS_EXISTING_PR"