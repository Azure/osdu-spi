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
# Checks that .github/CODEOWNERS exists on the default branch and that GitHub
# can resolve every owner in it, and keeps one human-required tracking issue in
# step with what is wrong. A line naming a handle without write access is
# ignored by GitHub, which makes the code-owner review rule vacuous, so an
# unresolvable owner is reported the same as a missing file.
#
# Arguments:
#   $1            Repository full name (owner/repo)
#   --dry-run     Print the assessment without touching the issue
#
# Environment:
#   GH_TOKEN      contents:read plus issues:write
#   SYNC_MODE     "mirror" on a customer-tier fork, which has no template sync to plant the file

set -euo pipefail

DRY_RUN=false
ARGS=()
for a in "$@"; do
  if [[ "$a" == "--dry-run" ]]; then DRY_RUN=true; else ARGS+=("$a"); fi
done
if [[ ${#ARGS[@]} -lt 1 ]]; then
  echo "Usage: $0 <repo_full_name> [--dry-run]"; exit 1
fi
REPO="${ARGS[0]}"
export GH_TOKEN="${GH_TOKEN:-}"

ISSUE_TITLE="⚙️ CODEOWNERS: missing or unresolvable owners"

problems=()
if contents="$(gh api "repos/${REPO}/contents/.github/CODEOWNERS" --jq .content 2>&1)"; then
  present=true
elif grep -q 'HTTP 404' <<< "$contents"; then
  present=false
else
  echo "::error::Could not read .github/CODEOWNERS: $contents"
  exit 1
fi

if [[ "$present" == "false" ]]; then
  if [[ "${SYNC_MODE:-}" == "mirror" ]]; then
    problems+=("\`.github/CODEOWNERS\` is not on the default branch. A mirror fork has no template sync to plant it: commit the file naming your reviewers (a team with write access, for example \`@org/team\`), or wait for the next mirror sync if the parent has since added one.")
  else
    problems+=("\`.github/CODEOWNERS\` is not on the default branch. Set the \`CODEOWNERS\` repository variable to a team with write access (for example \`@org/team\`); the next template sync plants the file.")
  fi
else
  # A file with no rule passes GitHub's validation yet protects no path.
  decoded="$(base64 -d <<< "$contents")"
  if ! grep -qE '^[[:space:]]*[^#[:space:]]' <<< "$decoded"; then
    problems+=("\`.github/CODEOWNERS\` has no ownership rule, only blank or comment lines, so the code-owner review rule applies to no path. Add a rule such as \`* @org/team\`.")
  fi
  # GitHub validates the default branch's file; each error names the line and the unknown owner.
  if ! validation="$(gh api "repos/${REPO}/codeowners/errors" 2>&1)"; then
    echo "::error::Could not validate CODEOWNERS: $validation"
    exit 1
  fi
  errors="$(jq -r '.errors[] | "line \(.line): \(.message | split("\n")[0])"' <<< "$validation")"
  if [[ -n "$errors" ]]; then
    while IFS= read -r e; do problems+=("$e"); done <<< "$errors"
    problems+=("An owner GitHub cannot resolve, or one without write access, is ignored and the code-owner review rule does not apply to that path.")
  fi
fi

if ! existing_issue="$(gh issue list --repo "$REPO" --state open --search "in:title \"$ISSUE_TITLE\"" --json number --jq '.[0].number // empty' 2>&1)"; then
  echo "::error::Could not look up the tracking issue: $existing_issue"
  exit 1
fi

if [[ ${#problems[@]} -eq 0 ]]; then
  echo "✅ CODEOWNERS present and every owner resolves."
  if [[ -n "$existing_issue" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "DRY-RUN would close issue #$existing_issue"
    else
      gh issue close "$existing_issue" --repo "$REPO" --comment "CODEOWNERS is present and every owner resolves. Closing."
    fi
  fi
  exit 0
fi

echo "⚠️ CODEOWNERS problems:"
printf '   - %s\n' "${problems[@]}"

body="$(printf 'The Default Branch Protection ruleset requires a code-owner review, which only applies when `.github/CODEOWNERS` exists and its owners resolve:\n\n'; printf -- '- [ ] %s\n' "${problems[@]}"; printf '\n_Maintained automatically by `settings-apply.yml`._\n')"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY-RUN would $( [[ -n "$existing_issue" ]] && echo "update issue #$existing_issue" || echo "open a human-required issue" )"
  exit 0
fi

if [[ -n "$existing_issue" ]]; then
  gh issue edit "$existing_issue" --repo "$REPO" --body "$body" >/dev/null
  echo "Updated tracking issue #$existing_issue"
else
  gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$body" \
    --label "human-required" >/dev/null 2>&1 \
    || gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$body" >/dev/null
  echo "Opened human-required tracking issue."
fi
