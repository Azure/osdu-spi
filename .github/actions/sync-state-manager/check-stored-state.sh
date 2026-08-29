#!/usr/bin/env bash
#
# Check Stored State Script
#
# Reads sync state for the current sync cycle. When a tracking issue exists its
# hidden marker is authoritative, so an open cycle keeps driving branch updates.
# With no tracking issue the durable repository variable is consulted instead,
# which is what stops a filtered no-op SHA from being re-generated (ADR-024).
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

STATE_VARIABLE="SYNC_LAST_EVALUATED_SHA"

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <existing_issue_number>"
  exit 1
fi

EXISTING_ISSUE_NUMBER="$1"

echo "Reading sync state from existing issue description..."

if [[ -n "$EXISTING_ISSUE_NUMBER" ]]; then
  echo "Found existing issue #$EXISTING_ISSUE_NUMBER, parsing state from description..."

  # Get issue body and extract the machine-readable upstream SHA
  ISSUE_BODY=$(gh issue view "$EXISTING_ISSUE_NUMBER" --json body --jq '.body')

  LAST_UPSTREAM_SHA=$(awk '
    /<!-- upstream-sha: [0-9a-f]+ -->/ {
      sha = $0
      sub(/^.*<!-- upstream-sha: /, "", sha)
      sub(/ -->.*$/, "", sha)
      if (length(sha) == 40 && sha ~ /^[0-9a-f]+$/) {
        print sha
        exit
      }
    }
  ' <<< "$ISSUE_BODY")

  # Extract timestamp from issue creation/update
  LAST_SYNC_TIMESTAMP=$(gh issue view "$EXISTING_ISSUE_NUMBER" --json updatedAt --jq '.updatedAt')

  echo "Parsed from issue:"
  echo "  Last upstream SHA: $LAST_UPSTREAM_SHA"
  echo "  Issue number: $EXISTING_ISSUE_NUMBER"
  echo "  Last sync: $LAST_SYNC_TIMESTAMP"
else
  echo "No existing sync issue found, reading durable evaluated-SHA state..."

  STORED_SHA=$(gh variable get "$STATE_VARIABLE" 2>/dev/null || echo "")

  if [[ "$STORED_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    LAST_UPSTREAM_SHA="$STORED_SHA"
    echo "  Last evaluated upstream SHA: $LAST_UPSTREAM_SHA"
  else
    LAST_UPSTREAM_SHA=""
    echo "  No durable state recorded, treating as first sync"
  fi

  LAST_SYNC_TIMESTAMP=""
fi

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "last_upstream_sha=$LAST_UPSTREAM_SHA"
    echo "current_issue_number=$EXISTING_ISSUE_NUMBER"
    echo "last_sync_timestamp=$LAST_SYNC_TIMESTAMP"
  } >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "last_upstream_sha=$LAST_UPSTREAM_SHA"
echo "current_issue_number=$EXISTING_ISSUE_NUMBER"
echo "last_sync_timestamp=$LAST_SYNC_TIMESTAMP"