#!/usr/bin/env bash
#
# Applies security-on.json and creates the GitHub Copilot code review ruleset.
#
# Arguments:
#   $1 - Repository full name (owner/repo)
#   $2 - Issue number for status comments (optional)
#
# Environment:
#   GH_TOKEN - admin token for repository settings and rulesets
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

if [[ -n "${GH_TOKEN:-}" ]]; then
  echo "🤖 Creating GitHub Copilot automatic code review ruleset..."

  RULESET_JSON=$(echo '{
    "name": "GitHub Copilot Code Review",
    "target": "branch",
    "enforcement": "active"
  }' | GH_TOKEN=$GH_TOKEN gh api --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO_FULL_NAME/rulesets" --input - 2>/dev/null || echo "")

  if [[ -n "$RULESET_JSON" ]] && [[ "$RULESET_JSON" != "null" ]]; then
    RULESET_ID=$(echo "$RULESET_JSON" | jq -r '.id')
    echo "Created basic ruleset with ID: $RULESET_ID"

    # "~DEFAULT_BRANCH" is Rulesets API syntax for the repository's default branch.
    if echo '{
      "name": "GitHub Copilot Code Review",
      "target": "branch",
      "enforcement": "active",
      "conditions": {
        "ref_name": {
          "include": ["~DEFAULT_BRANCH"],
          "exclude": []
        }
      },
      "bypass_actors": [],
      "rules": [
        {
          "type": "pull_request",
          "parameters": {
            "allowed_merge_methods": ["merge", "squash", "rebase"],
            "automatic_copilot_code_review_enabled": true,
            "dismiss_stale_reviews_on_push": false,
            "require_code_owner_review": false,
            "require_last_push_approval": false,
            "required_approving_review_count": 0,
            "required_review_thread_resolution": false
          }
        }
      ]
    }' | GH_TOKEN=$GH_TOKEN gh api --method PUT \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/$REPO_FULL_NAME/rulesets/$RULESET_ID" --input - >/dev/null 2>&1; then
      echo "✅ GitHub Copilot automatic code review enabled via repository ruleset"
    else
      echo "⚠️ Failed to configure Copilot code review in ruleset"
      SECURITY_SUCCESS=false
    fi
  else
    echo "⚠️ Could not create GitHub Copilot code review ruleset - may require manual configuration"

    if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
      echo "📝 To enable manually: Go to Settings → Rules → Rulesets → New branch ruleset → Add Copilot code review rule" | gh issue comment "$ISSUE_NUMBER" --body-file -
    fi
  fi
else
  echo "⚠️ GH_TOKEN not available, skipping GitHub Copilot configuration"

  if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "⚠️ **Note:** GitHub Copilot automatic code review requires manual configuration. Go to Settings → Rules → Rulesets → New branch ruleset → Add Copilot code review rule" | gh issue comment "$ISSUE_NUMBER" --body-file -
  fi
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SECURITY_SUCCESS=$SECURITY_SUCCESS" >> "$GITHUB_ENV"
fi

echo "Security setup complete: $SECURITY_SUCCESS"