#!/bin/bash
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Merges the source branch into the target branch, resolving every conflict in
# favor of the source side.
#
# Inputs (via environment):
#   SOURCE_BRANCH - branch to merge from
#   TARGET_BRANCH - branch to merge into
#   COMMIT_MESSAGE - merge commit message
#   ISSUE_NUMBER - issue for status comments (optional)
#   GITHUB_TOKEN - needed only for comments
#
# Outputs (to GITHUB_OUTPUT):
#   merge_successful - true/false
#   conflicts_resolved - count

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

git checkout "$TARGET_BRANCH"

if ! git merge "$SOURCE_BRANCH" --allow-unrelated-histories --no-ff -X theirs -m "$COMMIT_MESSAGE"; then
    echo "⚠️  Merge conflicts detected, resolving automatically..."

    if [ -n "$ISSUE_NUMBER" ] && [ -n "$GITHUB_TOKEN" ]; then
        echo "⚠️ **Merge conflicts detected, resolving automatically...**" | gh issue comment "$ISSUE_NUMBER" --body-file - || true
    fi

    CONFLICTS_RESOLVED=0

    # -X theirs does not resolve modify/delete; take the source side for anything still unmerged.
    git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU)' | cut -c4- | while read -r file; do
        echo "Resolving conflict in $file - using $SOURCE_BRANCH version"
        git checkout --theirs "$file"
        git add "$file"
        CONFLICTS_RESOLVED=$((CONFLICTS_RESOLVED + 1))
    done

    # The while loop ran in a subshell, so recount here.
    CONFLICTS_RESOLVED=$(git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU)' | wc -l)

    git commit -m "$COMMIT_MESSAGE (conflicts resolved using $SOURCE_BRANCH versions)"

    echo "conflicts_resolved=$CONFLICTS_RESOLVED" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "merge_successful=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "✅ Resolved $CONFLICTS_RESOLVED conflicts using $SOURCE_BRANCH versions"
else
    echo "conflicts_resolved=0" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "merge_successful=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "✅ Merge completed without conflicts"
fi