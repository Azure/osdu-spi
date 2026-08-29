#!/usr/bin/env bash
#
# Record Evaluated Upstream SHA Script
#
# Persists the last upstream SHA that produced no fork-visible change into a
# repository variable, so the next run can skip regenerating an identical tree.
# This is the only sync state that outlives the tracking issue (ADR-024).
#
# Arguments:
#   $1 - Full upstream SHA that was evaluated
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI
#
# Usage:
#   export GITHUB_TOKEN="ghp_token"
#   ./record-evaluated-sha.sh "0b8fd115ac1aeb283926830f6f6152b42783b220"

set -euo pipefail

STATE_VARIABLE="SYNC_LAST_EVALUATED_SHA"

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <upstream_sha>"
  exit 1
fi

UPSTREAM_SHA="$1"

# A malformed value would compare unequal forever and silently disable the
# optimization, so reject it here rather than storing it.
if [[ ! "$UPSTREAM_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Error: Upstream SHA must be a 40-character lowercase hexadecimal value"
  exit 1
fi

# A failed write costs one repeated evaluation next run, which is exactly the
# pre-existing behavior; failing the sync over a missed optimization is worse.
if gh variable set "$STATE_VARIABLE" --body "$UPSTREAM_SHA"; then
  echo "✅ Recorded evaluated upstream SHA: $UPSTREAM_SHA"
else
  echo "⚠️ Warning: could not record $STATE_VARIABLE - the next run will re-evaluate this SHA"
fi
