#!/usr/bin/env bash
#
# Check Stored State Script
#
# Reads sync state from existing issue description using awk parsing.
# Extracts the last upstream SHA and timestamp from issue body.
#
# Arguments:
#   $1 - Existing issue number (can be empty if no issue exists)
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI
#
# Outputs:
#   last_upstream_sha - Last synced upstream SHA
#   current_issue_number - Issue number (same as input)
#   last_sync_timestamp - Timestamp of last sync
#
# Usage:
#   export GITHUB_TOKEN="ghp_token"
#   ./check-stored-state.sh "123"

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <existing_issue_number>"
  exit 1
fi

EXISTING_ISSUE_NUMBER="$1"

echo "Reading sync state from existing issue description..."

if [[ -n "$EXISTING_ISSUE_NUMBER" ]]; then
  echo "Found existing issue #$EXISTING_ISSUE_NUMBER, parsing state from description..."

  # Get issue body and extract upstream version SHA
  ISSUE_BODY=$(gh issue view "$EXISTING_ISSUE_NUMBER" --json body --jq '.body')

  # Extract SHA from "Upstream Version" field using awk for robust parsing
  LAST_UPSTREAM_SHA=$(echo "$ISSUE_BODY" | awk '/Upstream Version/ {match($0, /`[^`]+`/); if (RSTART > 0) print substr($0, RSTART+1, RLENGTH-2)}' | head -1)

  # Extract timestamp from issue creation/update
  LAST_SYNC_TIMESTAMP=$(gh issue view "$EXISTING_ISSUE_NUMBER" --json updatedAt --jq '.updatedAt')

  echo "Parsed from issue:"
  echo "  Last upstream SHA: $LAST_UPSTREAM_SHA"
  echo "  Issue number: $EXISTING_ISSUE_NUMBER"
  echo "  Last sync: $LAST_SYNC_TIMESTAMP"
else
  echo "No existing sync issue found, treating as first sync"
  LAST_UPSTREAM_SHA=""
  LAST_SYNC_TIMESTAMP=""
fi

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "last_upstream_sha=$LAST_UPSTREAM_SHA" >> "$GITHUB_OUTPUT"
  echo "current_issue_number=$EXISTING_ISSUE_NUMBER" >> "$GITHUB_OUTPUT"
  echo "last_sync_timestamp=$LAST_SYNC_TIMESTAMP" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "last_upstream_sha=$LAST_UPSTREAM_SHA"
echo "current_issue_number=$EXISTING_ISSUE_NUMBER"
echo "last_sync_timestamp=$LAST_SYNC_TIMESTAMP"