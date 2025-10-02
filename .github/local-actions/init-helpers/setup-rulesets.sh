#!/usr/bin/env bash
#
# Setup Repository Rulesets Script
#
# Creates repository rulesets from JSON configuration files.
#
# Rulesets created:
#   - Default Branch Protection: Comprehensive protection with PR requirements, status checks, code scanning, Copilot review
#   - Integration Branch Protection: Deletion protection only (allows direct pushes for cascade)
#
# Arguments:
#   $1 - Repository full name (owner/repo)
#   $2 - Issue number for status comments (optional)
#
# Environment Variables:
#   GH_TOKEN - Required (PAT with admin permissions)
#   GITHUB_TOKEN - Used for issue comments if issue_number provided
#   RULESET_SUCCESS - Output: Sets to "true" or "false"
#
# Usage:
#   export GH_TOKEN="ghp_your_pat_token"
#   ./setup-rulesets.sh "owner/repo" "123"

set -euo pipefail

# Validate arguments
if [[ $# -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <repo_full_name> [issue_number]"
  exit 1
fi

REPO_FULL_NAME="$1"
ISSUE_NUMBER="${2:-}"

RULESET_SUCCESS=true

echo "Setting up repository rulesets for $REPO_FULL_NAME..."

# Check if GH_TOKEN is available
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "⚠️ GH_TOKEN not available, skipping ruleset setup"

  if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    cat <<EOF | gh issue comment "$ISSUE_NUMBER" --body-file -
⚠️ **Warning:** Unable to create repository rulesets. Please configure manually or provide a GH_TOKEN secret with appropriate permissions.

To set up rulesets manually, go to Settings → Rules → Rulesets and create rulesets based on the configurations in \`.github/rulesets/\`.
EOF
  fi

  RULESET_SUCCESS=false
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "RULESET_SUCCESS=$RULESET_SUCCESS" >> "$GITHUB_ENV"
  fi
  exit 0
fi

# Create Default Branch Protection ruleset
echo "Creating 'Default Branch Protection' ruleset..."
if [[ -f ".github/rulesets/default-branch.json" ]]; then
  RULESET_JSON=$(cat .github/rulesets/default-branch.json | GH_TOKEN=$GH_TOKEN gh api --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO_FULL_NAME/rulesets" --input - 2>/dev/null || echo "")

  if [[ -n "$RULESET_JSON" ]] && [[ "$RULESET_JSON" != "null" ]]; then
    RULESET_ID=$(echo "$RULESET_JSON" | jq -r '.id')
    echo "✅ Created 'Default Branch Protection' ruleset (ID: $RULESET_ID)"
  else
    echo "⚠️ Failed to create 'Default Branch Protection' ruleset"
    RULESET_SUCCESS=false
  fi
else
  echo "⚠️ Configuration file .github/rulesets/default-branch.json not found"
  RULESET_SUCCESS=false
fi

# Create Integration Branch Protection ruleset
echo "Creating 'Integration Branch Protection' ruleset..."
if [[ -f ".github/rulesets/integration-branch.json" ]]; then
  RULESET_JSON=$(cat .github/rulesets/integration-branch.json | GH_TOKEN=$GH_TOKEN gh api --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO_FULL_NAME/rulesets" --input - 2>/dev/null || echo "")

  if [[ -n "$RULESET_JSON" ]] && [[ "$RULESET_JSON" != "null" ]]; then
    RULESET_ID=$(echo "$RULESET_JSON" | jq -r '.id')
    echo "✅ Created 'Integration Branch Protection' ruleset (ID: $RULESET_ID)"
  else
    echo "⚠️ Failed to create 'Integration Branch Protection' ruleset"
    RULESET_SUCCESS=false
  fi
else
  echo "⚠️ Configuration file .github/rulesets/integration-branch.json not found"
  RULESET_SUCCESS=false
fi

# Store result
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "RULESET_SUCCESS=$RULESET_SUCCESS" >> "$GITHUB_ENV"
fi

echo "Ruleset setup complete: $RULESET_SUCCESS"
