#!/usr/bin/env bash
#
# Issue State Manager Script
#
# Updates GitHub issue description with current sync state using awk for reliable
# field replacement (handles backticks and special characters).
#
# Arguments:
#   $1 - Issue number
#   $2 - Upstream version (commit SHA)
#   $3 - Sync branch name
#   $4 - Commit count
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI authentication
#
# Usage:
#   export GITHUB_TOKEN="ghp_your_token"
#   ./update-issue-state.sh 123 "abc1234" "sync/upstream-20250129" 5

set -euo pipefail

# Validate arguments
if [[ $# -ne 4 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <issue_number> <upstream_version> <sync_branch> <commit_count>"
  exit 1
fi

ISSUE_NUMBER="$1"
UPSTREAM_VERSION="$2"
SYNC_BRANCH="$3"
COMMIT_COUNT="$4"

# Validate GITHUB_TOKEN
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is required"
  exit 1
fi

echo "Updating issue #$ISSUE_NUMBER with current sync state..."
echo "  - Upstream Version: $UPSTREAM_VERSION"
echo "  - Sync Branch: $SYNC_BRANCH"
echo "  - Commit Count: $COMMIT_COUNT"

# Get current issue body
CURRENT_BODY=$(gh issue view "$ISSUE_NUMBER" --json body --jq '.body')

# Write to temporary file for awk processing
TMP_FILE=$(mktemp)
echo "$CURRENT_BODY" > "$TMP_FILE"

# Use awk to update the three key fields in the Sync Summary section
# This is more reliable than sed for handling backticks and special characters
awk -v upstream="$UPSTREAM_VERSION" -v count="$COMMIT_COUNT" -v branch="$SYNC_BRANCH" '
{
  # Update Upstream Version (handles backticks)
  gsub(/\*\*Upstream Version\*\*: `[^`]*`/, "**Upstream Version**: `" upstream "`")

  # Update Changes count
  gsub(/\*\*Changes\*\*: [0-9]+ new commits from upstream/, "**Changes**: " count " new commits from upstream")

  # Update Branch (handles backticks and arrow)
  gsub(/\*\*Branch\*\*: `[^`]*` → `fork_upstream`/, "**Branch**: `" branch "` → `fork_upstream`")

  print
}' "$TMP_FILE" > "${TMP_FILE}.updated"

# Update the issue description using the updated file
gh issue edit "$ISSUE_NUMBER" --body-file "${TMP_FILE}.updated"

# Clean up temporary files
rm -f "$TMP_FILE" "${TMP_FILE}.updated"

echo "✅ Successfully updated issue #$ISSUE_NUMBER description"