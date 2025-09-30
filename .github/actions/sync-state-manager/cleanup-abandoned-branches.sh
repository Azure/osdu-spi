#!/usr/bin/env bash
#
# Cleanup Abandoned Sync Branches Script
#
# Cleans up sync branches older than 24 hours that don't have associated PRs.
# Branch format: sync/upstream-YYYYMMDD-HHMMSS
#
# Arguments:
#   None
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI
#
# Usage:
#   export GITHUB_TOKEN="ghp_token"
#   ./cleanup-abandoned-branches.sh

set -euo pipefail

echo "Cleaning up abandoned sync branches..."

# List all sync branches (both local and remote)
SYNC_BRANCHES=$(git branch -r | grep -E "origin/sync/upstream-[0-9]+" | sed 's/origin\///' | sed 's/^[[:space:]]*//' || echo "")

if [[ -n "$SYNC_BRANCHES" ]]; then
  echo "Found sync branches:"
  echo "$SYNC_BRANCHES"

  # Get current time in seconds since epoch
  CURRENT_TIME=$(date +%s)
  CLEANUP_THRESHOLD=$((CURRENT_TIME - 86400)) # 24 hours ago

  # Check each branch for age and associated PR
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue

    # Extract timestamp from branch name (format: sync/upstream-YYYYMMDD-HHMMSS)
    TIMESTAMP_STR=$(echo "$branch" | sed -n 's/.*sync\/upstream-\([0-9]\{8\}-[0-9]\{6\}\).*/\1/p')

    if [[ -n "$TIMESTAMP_STR" ]]; then
      # Convert to epoch time (handle both GNU and BSD date)
      if date --version >/dev/null 2>&1; then
        # GNU date
        BRANCH_TIME=$(date -d "${TIMESTAMP_STR:0:4}-${TIMESTAMP_STR:4:2}-${TIMESTAMP_STR:6:2} ${TIMESTAMP_STR:9:2}:${TIMESTAMP_STR:11:2}:${TIMESTAMP_STR:13:2}" +%s 2>/dev/null || echo "0")
      else
        # BSD date (macOS)
        BRANCH_TIME=$(date -j -f "%Y%m%d-%H%M%S" "$TIMESTAMP_STR" +%s 2>/dev/null || echo "0")
      fi

      # Check if branch is older than threshold
      if [[ "$BRANCH_TIME" -lt "$CLEANUP_THRESHOLD" ]] && [[ "$BRANCH_TIME" -gt "0" ]]; then
        # Check if there's an associated open PR with proper error handling
        echo "   Checking for associated PR for branch: $branch"
        ASSOCIATED_PR=$(gh pr list --head "$branch" --state open --json number 2>/dev/null | jq -r '.[0].number // empty' 2>/dev/null || echo "")
        GH_EXIT_CODE=$?

        if [[ $GH_EXIT_CODE -ne 0 ]]; then
          echo "   ⚠️ Warning: gh command failed for branch $branch (exit code: $GH_EXIT_CODE)"
          echo "   Skipping cleanup for safety - manual intervention may be required"
        elif [[ -z "$ASSOCIATED_PR" ]]; then
          AGE_SECONDS=$((CURRENT_TIME - BRANCH_TIME))
          echo "   ⚠️ Found abandoned branch: $branch (age: $AGE_SECONDS seconds)"
          echo "   Deleting abandoned branch..."
          if git push origin --delete "$branch" 2>/dev/null; then
            echo "   ✅ Deleted branch: $branch"
          else
            echo "   ⚠️ Failed to delete branch (may not exist or permissions issue)"
          fi
        else
          echo "   ✅ Branch $branch has associated PR #$ASSOCIATED_PR - keeping"
        fi
      fi
    fi
  done <<< "$SYNC_BRANCHES"
else
  echo "No sync branches found to clean up"
fi

echo "Cleanup complete"