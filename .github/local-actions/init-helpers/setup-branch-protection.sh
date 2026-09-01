#!/usr/bin/env bash
#
# Configures branch protection for the fork management branches.
#
# Branches protected:
#   - main: requires PR review
#   - fork_upstream: basic protection, automation pushes allowed
#   - fork_integration: not protected, the cascade pushes to it directly
#
# Arguments:
#   $1 - Repository full name (owner/repo)
#   $2 - Issue number for status comments (optional)
#
# Environment:
#   GH_TOKEN - admin token for the protection API
#   GITHUB_TOKEN - issue comments when an issue number is given
#   BRANCH_PROTECTION_SUCCESS - output: written to GITHUB_ENV as "true" or "false"

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <repo_full_name> [issue_number]"
  exit 1
fi

REPO_FULL_NAME="$1"
ISSUE_NUMBER="${2:-}"

BRANCH_PROTECTION_SUCCESS=true

echo "Setting up branch protection for $REPO_FULL_NAME..."

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "⚠️ GH_TOKEN not available, skipping branch protection setup"

  if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    cat <<EOF | gh issue comment "$ISSUE_NUMBER" --body-file -
⚠️ **Warning:** Unable to set branch protection rules. Please configure manually or provide a GH_TOKEN secret with appropriate permissions.

To set up branch protection manually, go to Settings → Branches and protect: main (PR required), fork_upstream (basic protection). Leave fork_integration unprotected.
EOF
  fi

  BRANCH_PROTECTION_SUCCESS=false
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "BRANCH_PROTECTION_SUCCESS=$BRANCH_PROTECTION_SUCCESS" >> "$GITHUB_ENV"
  fi
  exit 0
fi

echo "Protecting main branch..."
if ! GH_TOKEN=$GH_TOKEN gh api \
  --method PUT \
  -H "Accept: application/vnd.github.v3+json" \
  "/repos/$REPO_FULL_NAME/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
then
  echo "⚠️ Failed to protect main branch"
  BRANCH_PROTECTION_SUCCESS=false
else
  echo "✅ Protected main branch with PR requirements"
fi

echo "Protecting fork_upstream branch..."
if ! GH_TOKEN=$GH_TOKEN gh api \
  --method PUT \
  -H "Accept: application/vnd.github.v3+json" \
  "/repos/$REPO_FULL_NAME/branches/fork_upstream/protection" \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
then
  echo "⚠️ Failed to protect fork_upstream branch"
  BRANCH_PROTECTION_SUCCESS=false
else
  echo "✅ Protected fork_upstream branch (automation pushes allowed)"
fi

echo "✅ fork_integration branch left unprotected (allows direct pushes for cascade workflow)"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "BRANCH_PROTECTION_SUCCESS=$BRANCH_PROTECTION_SUCCESS" >> "$GITHUB_ENV"
fi

echo "Branch protection setup complete: $BRANCH_PROTECTION_SUCCESS"