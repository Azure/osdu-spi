#!/usr/bin/env bash
#
# Persists the last upstream SHA that produced no fork-visible change into a
# repository variable so the next run can skip regenerating an identical tree.
# This is the only sync state that outlives the tracking issue (ADR-024).
#
# The stored value is "<sha>:<generation-rev>". The revision half scopes the
# result to the filter inputs that produced it, so a config or engine change
# invalidates the cache instead of pinning a stale tree until upstream moves.
#
# Env: GITHUB_TOKEN, SYNC_MODE (passed through to generation-rev.sh)
# Local: ./record-evaluated-sha.sh <full_upstream_sha>

set -euo pipefail

STATE_VARIABLE="SYNC_LAST_EVALUATED_SHA"

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument" >&2
  echo "Usage: $0 <upstream_sha>" >&2
  exit 1
fi

UPSTREAM_SHA="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A malformed value would compare unequal forever and silently disable the
# optimization, so reject it here rather than storing it.
if [[ ! "$UPSTREAM_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Error: Upstream SHA must be a 40-character lowercase hexadecimal value" >&2
  exit 1
fi

GENERATION_REV="$("$HERE/generation-rev.sh")"
STATE_VALUE="$UPSTREAM_SHA:$GENERATION_REV"

# A failed write costs one repeated evaluation next run, which is exactly the
# pre-existing behavior; failing the sync over a missed optimization is worse.
if gh variable set "$STATE_VARIABLE" --body "$STATE_VALUE"; then
  echo "✅ Recorded evaluated upstream state: $STATE_VALUE"
else
  echo "⚠️ Warning: could not record $STATE_VARIABLE - the next run will re-evaluate this SHA"
fi
