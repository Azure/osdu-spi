#!/usr/bin/env bash
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

#
# Keeps allow_auto_merge and allow_merge_commit on, so the cascade can arm a
# merge-commit auto-merge on each release PR (ADR-009). Init sets both, but forks
# created before init did keep them off, and their release PRs wait for a manual
# merge after approval.
#
# Arguments:
#   $1            Repository full name (owner/repo)
#   --dry-run     Print the planned change; no mutation
#
# Environment:
#   GH_TOKEN      administration:write to read and change repository settings

set -euo pipefail

DRY_RUN=false
ARGS=()
for a in "$@"; do
  if [[ "$a" == "--dry-run" ]]; then DRY_RUN=true; else ARGS+=("$a"); fi
done

if [[ ${#ARGS[@]} -lt 1 ]]; then
  echo "Usage: $0 <repo_full_name> [--dry-run]"
  exit 1
fi
REPO="${ARGS[0]}"

if ! CURRENT=$(gh api "repos/$REPO" --jq '"\(.allow_auto_merge) \(.allow_merge_commit)"' 2>&1); then
  echo "::warning::Could not read merge settings for $REPO: $CURRENT"
  exit 0
fi
read -r AUTO_MERGE MERGE_COMMIT <<<"$CURRENT"
echo "allow_auto_merge=$AUTO_MERGE allow_merge_commit=$MERGE_COMMIT"

if [[ "$AUTO_MERGE" == "true" && "$MERGE_COMMIT" == "true" ]]; then
  echo "✅ Merge settings already allow merge-commit auto-merge"
  exit 0
fi

if $DRY_RUN; then
  echo "DRY-RUN would set allow_auto_merge=true allow_merge_commit=true"
  exit 0
fi

# An org policy can forbid merge commits; that leaves release PRs to a manual merge, so warn rather than fail the run.
if OUT=$(gh api --method PATCH "repos/$REPO" -F allow_auto_merge=true -F allow_merge_commit=true \
    --jq '"\(.allow_auto_merge) \(.allow_merge_commit)"' 2>&1) && [[ "$OUT" == "true true" ]]; then
  echo "✅ Enabled allow_auto_merge and allow_merge_commit"
else
  echo "::warning::Could not enable merge-commit auto-merge on $REPO ($OUT). Release PRs need a manual merge with 'Create a merge commit'."
fi
