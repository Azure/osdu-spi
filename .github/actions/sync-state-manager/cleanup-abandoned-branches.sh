#!/usr/bin/env bash
#
# Deletes sync/upstream-YYYYMMDD-HHMMSS branches older than 24 hours that have
# no open PR.
#
# Env: GITHUB_TOKEN

set -euo pipefail

echo "Cleaning up abandoned sync branches..."

SYNC_BRANCHES=$(git branch -r | grep -E "origin/sync/upstream-[0-9]+" | sed 's/origin\///' | sed 's/^[[:space:]]*//' || echo "")

if [[ -n "$SYNC_BRANCHES" ]]; then
  echo "Found sync branches:"
  echo "$SYNC_BRANCHES"

  CURRENT_TIME=$(date +%s)
  CLEANUP_THRESHOLD=$((CURRENT_TIME - 86400)) # 24 hours ago

  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue

    TIMESTAMP_STR=$(echo "$branch" | sed -n 's/.*sync\/upstream-\([0-9]\{8\}-[0-9]\{6\}\).*/\1/p')

    if [[ -n "$TIMESTAMP_STR" ]]; then
      # GNU and BSD date parse differently.
      if date --version >/dev/null 2>&1; then
        BRANCH_TIME=$(date -d "${TIMESTAMP_STR:0:4}-${TIMESTAMP_STR:4:2}-${TIMESTAMP_STR:6:2} ${TIMESTAMP_STR:9:2}:${TIMESTAMP_STR:11:2}:${TIMESTAMP_STR:13:2}" +%s 2>/dev/null || echo "0")
      else
        BRANCH_TIME=$(date -j -f "%Y%m%d-%H%M%S" "$TIMESTAMP_STR" +%s 2>/dev/null || echo "0")
      fi

      if [[ "$BRANCH_TIME" -lt "$CLEANUP_THRESHOLD" ]] && [[ "$BRANCH_TIME" -gt "0" ]]; then
        echo "   Checking for associated PR for branch: $branch"
        GH_EXIT_CODE=0
        PR_LIST=$(gh pr list --head "$branch" --state open --json number 2>/dev/null) || GH_EXIT_CODE=$?

        if [[ $GH_EXIT_CODE -ne 0 ]]; then
          echo "   ⚠️ Warning: gh command failed for branch $branch (exit code: $GH_EXIT_CODE)"
          echo "   Skipping cleanup for safety - manual intervention may be required"
          continue
        fi

        if ! ASSOCIATED_PR=$(jq -r '.[0].number // empty' <<< "$PR_LIST" 2>/dev/null); then
          echo "   ⚠️ Warning: failed to parse PR lookup response for branch $branch"
          echo "   Skipping cleanup for safety - manual intervention may be required"
          continue
        fi

        if [[ -z "$ASSOCIATED_PR" ]]; then
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