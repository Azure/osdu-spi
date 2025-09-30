#!/bin/bash
# Merge with Automatic Theirs Resolution
#
# Merges source branch into target branch, automatically resolving conflicts
# by preferring the source branch version (theirs strategy).
#
# Inputs (via environment):
#   SOURCE_BRANCH - Branch to merge from (e.g., fork_integration)
#   TARGET_BRANCH - Branch to merge into (e.g., main)
#   COMMIT_MESSAGE - Commit message for the merge
#   ISSUE_NUMBER - GitHub issue number for status comments (optional)
#   GITHUB_TOKEN - GitHub token for API access (optional, for comments)
#
# Outputs (to GITHUB_OUTPUT and stdout):
#   merge_successful=true/false - Whether merge completed
#   conflicts_resolved=<count> - Number of conflicts auto-resolved

set -euo pipefail

SOURCE_BRANCH="${SOURCE_BRANCH}"
TARGET_BRANCH="${TARGET_BRANCH}"
COMMIT_MESSAGE="${COMMIT_MESSAGE}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$SOURCE_BRANCH" ] || [ -z "$TARGET_BRANCH" ] || [ -z "$COMMIT_MESSAGE" ]; then
    echo "::error::SOURCE_BRANCH, TARGET_BRANCH, and COMMIT_MESSAGE are required"
    exit 1
fi

echo "Merging $SOURCE_BRANCH into $TARGET_BRANCH..."

# Checkout target branch
git checkout "$TARGET_BRANCH"

# Try merge with unrelated histories, preferring source branch changes
if ! git merge "$SOURCE_BRANCH" --allow-unrelated-histories --no-ff -X theirs -m "$COMMIT_MESSAGE"; then
    echo "⚠️  Merge conflicts detected, resolving automatically..."

    # Post comment if issue tracking enabled
    if [ -n "$ISSUE_NUMBER" ] && [ -n "$GITHUB_TOKEN" ]; then
        echo "⚠️ **Merge conflicts detected, resolving automatically...**" | gh issue comment "$ISSUE_NUMBER" --body-file - || true
    fi

    # Count conflicts resolved
    CONFLICTS_RESOLVED=0

    # If there are still conflicts even with -X theirs, explicitly take source version
    # Git status codes: DD=deleted, AU=added by us, UD=deleted by them, etc.
    git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU)' | cut -c4- | while read -r file; do
        echo "Resolving conflict in $file - using $SOURCE_BRANCH version"
        # Use the version from source branch (which comes from upstream)
        git checkout --theirs "$file"
        git add "$file"
        CONFLICTS_RESOLVED=$((CONFLICTS_RESOLVED + 1))
    done

    # Get actual count (subshell issue workaround)
    CONFLICTS_RESOLVED=$(git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU)' | wc -l)

    # Complete the merge
    git commit -m "$COMMIT_MESSAGE (conflicts resolved using $SOURCE_BRANCH versions)"

    echo "conflicts_resolved=$CONFLICTS_RESOLVED" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "merge_successful=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "✅ Resolved $CONFLICTS_RESOLVED conflicts using $SOURCE_BRANCH versions"
else
    echo "conflicts_resolved=0" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "merge_successful=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "✅ Merge completed without conflicts"
fi