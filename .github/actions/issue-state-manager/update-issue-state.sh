#!/usr/bin/env bash
#
# Updates the Sync Summary fields in a tracking issue body.
#
# Env: GITHUB_TOKEN
# Local: ./update-issue-state.sh <issue_number> <upstream_version> <sync_branch> <commit_count>

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <issue_number> <upstream_version> <sync_branch> <commit_count>"
  exit 1
fi

ISSUE_NUMBER="$1"
UPSTREAM_VERSION="$2"
SYNC_BRANCH="$3"
COMMIT_COUNT="$4"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is required"
  exit 1
fi

echo "Updating issue #$ISSUE_NUMBER with current sync state..."
echo "  - Upstream Version: $UPSTREAM_VERSION"
echo "  - Sync Branch: $SYNC_BRANCH"
echo "  - Commit Count: $COMMIT_COUNT"

CURRENT_BODY=$(gh issue view "$ISSUE_NUMBER" --json body --jq '.body')

TMP_FILE=$(mktemp)
echo "$CURRENT_BODY" > "$TMP_FILE"

# awk, not sed: the fields contain backticks and an arrow.
awk -v upstream="$UPSTREAM_VERSION" -v count="$COMMIT_COUNT" -v branch="$SYNC_BRANCH" '
{
  gsub(/\*\*Upstream Version\*\*: `[^`]*`/, "**Upstream Version**: `" upstream "`")

  gsub(/\*\*Changes\*\*: [0-9]+ new commits from upstream/, "**Changes**: " count " new commits from upstream")

  gsub(/\*\*Branch\*\*: `[^`]*` → `fork_upstream`/, "**Branch**: `" branch "` → `fork_upstream`")

  print
}' "$TMP_FILE" > "${TMP_FILE}.updated"

gh issue edit "$ISSUE_NUMBER" --body-file "${TMP_FILE}.updated"

rm -f "$TMP_FILE" "${TMP_FILE}.updated"

echo "✅ Successfully updated issue #$ISSUE_NUMBER description"