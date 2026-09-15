#!/usr/bin/env bash
#
# Applies security-on.json.
#
# Arguments:
#   $1 - Repository full name (owner/repo)
#   $2 - Issue number for status comments (optional)
#
# Environment:
#   GH_TOKEN - admin token for repository settings
#   GITHUB_TOKEN - issue comments when an issue number is given
#   SECURITY_SUCCESS - output: written to GITHUB_ENV as "true" or "false"

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <repo_full_name> [issue_number]"
  exit 1
fi

REPO_FULL_NAME="$1"
ISSUE_NUMBER="${2:-}"

SECURITY_SUCCESS=true

echo "Setting up security features for $REPO_FULL_NAME..."

if [[ -f ".github/security-on.json" ]]; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "Enabling security features from security-on.json..."
    if ! GH_TOKEN=$GH_TOKEN gh api \
      --method PATCH \
      -H "Accept: application/vnd.github.v3+json" \
      "/repos/$REPO_FULL_NAME" \
      --input .github/security-on.json; then
      echo "⚠️ Some security features may require manual configuration"
      SECURITY_SUCCESS=false
    else
      echo "✅ Security features enabled"
    fi
  else
    echo "⚠️ GH_TOKEN not available, skipping security features configuration"

    if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
      echo "⚠️ **Note:** Security features require manual configuration. Go to Settings → Security & analysis" | gh issue comment "$ISSUE_NUMBER" --body-file -
    fi

    SECURITY_SUCCESS=false
  fi
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SECURITY_SUCCESS=$SECURITY_SUCCESS" >> "$GITHUB_ENV"
fi

echo "Security setup complete: $SECURITY_SUCCESS"