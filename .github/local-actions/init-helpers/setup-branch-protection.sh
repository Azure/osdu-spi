#!/usr/bin/env bash
#
# Setup Branch Protection Script
#
# Configures branch protection rules for fork management branches.
#
# Branches protected:
#   - main: Requires PR reviews (production branch)
#   - fork_upstream: Basic protection (automation pushes allowed)
#   - fork_integration: NOT protected (allows direct pushes for cascade)
#
# Arguments:
#   $1 - Repository full name (owner/repo)
#   $2 - Issue number for status comments (optional)
#
# Environment Variables:
#   GH_TOKEN - Required (PAT with workflows permission)
#   GITHUB_TOKEN - Used for issue comments if issue_number provided
#   BRANCH_PROTECTION_SUCCESS - Output: Sets to "true" or "false"
#
# Usage:
#   export GH_TOKEN="ghp_your_pat_token"
#   ./setup-branch-protection.sh "owner/repo" "123"

set -euo pipefail

# Validate arguments
if [[ $# -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <repo_full_name> [issue_number]"
  exit 1
fi

REPO_FULL_NAME="$1"
ISSUE_NUMBER="${2:-}"

BRANCH_PROTECTION_SUCCESS=true

echo "Setting up branch protection for $REPO_FULL_NAME..."

# Check if GH_TOKEN is available
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

# Protect main branch (production) - requires PR reviews
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

# Protect fork_upstream branch - allow automation pushes only
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

# Do NOT protect fork_integration - it needs direct pushes for cascade workflow
echo "✅ fork_integration branch left unprotected (allows direct pushes for cascade workflow)"

# Store result
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "BRANCH_PROTECTION_SUCCESS=$BRANCH_PROTECTION_SUCCESS" >> "$GITHUB_ENV"
fi

echo "Branch protection setup complete: $BRANCH_PROTECTION_SUCCESS"