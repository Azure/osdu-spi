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

# Export GH_TOKEN for gh CLI to avoid token exposure in process listings
export GH_TOKEN

# Function to create a ruleset from a config file
create_ruleset() {
  local config_file="$1"
  local ruleset_name="$2"
  local RULESET_FAILED=false

  echo "Creating '$ruleset_name' ruleset..."
  if [[ -f "$config_file" ]]; then
    # Capture both stdout and stderr
    RULESET_RESPONSE=$(gh api --method POST \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/$REPO_FULL_NAME/rulesets" \
      --input "$config_file" 2>&1) || RULESET_FAILED=true

    if [[ "$RULESET_FAILED" == "true" ]]; then
      echo "⚠️ Failed to create '$ruleset_name' ruleset"
      echo "Error: $RULESET_RESPONSE"
      RULESET_SUCCESS=false
    else
      RULESET_ID=$(echo "$RULESET_RESPONSE" | jq -r '.id // "null"')
      if [[ "$RULESET_ID" != "null" ]] && [[ -n "$RULESET_ID" ]]; then
        echo "✅ Created '$ruleset_name' ruleset (ID: $RULESET_ID)"
      else
        echo "⚠️ Failed to create '$ruleset_name' ruleset - API returned null ID"
        echo "Response: $RULESET_RESPONSE"
        RULESET_SUCCESS=false
      fi
    fi
  else
    echo "⚠️ Configuration file $config_file not found"
    RULESET_SUCCESS=false
  fi
}

# Create Default Branch Protection ruleset
create_ruleset ".github/rulesets/default-branch.json" "Default Branch Protection"

# Create Integration Branch Protection ruleset
create_ruleset ".github/rulesets/integration-branch.json" "Integration Branch Protection"

# Store result
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "RULESET_SUCCESS=$RULESET_SUCCESS" >> "$GITHUB_ENV"
fi

echo "Ruleset setup complete: $RULESET_SUCCESS"
