#!/usr/bin/env bash
#
# Creates or updates the rulesets in .github/rulesets/*.json by name, so it is
# safe to run at init and again on the settings-apply cadence.
#
# default-branch.json lists the fully onboarded check set. On a fork that is
# not yet deploy-ready the deploy and integration-test checks are stripped from
# the payload so PRs are not blocked on checks that cannot pass yet.
#
# Arguments:
#   $1            Repository full name (owner/repo)
#   $2            Issue number for status comments (optional)
#   --dry-run     Print planned actions and the filter decision; no mutations
#
# Environment:
#   GH_TOKEN      admin token for ruleset mutations
#   GITHUB_TOKEN  issue comments when an issue number is given
#   RULESET_SUCCESS  output: written to GITHUB_ENV as "true" or "false"

set -euo pipefail

DRY_RUN=false
ARGS=()
for a in "$@"; do
  if [[ "$a" == "--dry-run" ]]; then DRY_RUN=true; else ARGS+=("$a"); fi
done

if [[ ${#ARGS[@]} -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <repo_full_name> [issue_number] [--dry-run]"
  exit 1
fi

REPO_FULL_NAME="${ARGS[0]}"
ISSUE_NUMBER="${ARGS[1]:-}"
RULESET_SUCCESS=true

# Stripped from the required checks on forks that are not deploy-ready.
DEPLOY_CHECKS=("🚀 Deploy to spi-stack" "🧪 Integration Tests")

echo "Reconciling repository rulesets for $REPO_FULL_NAME (dry_run: $DRY_RUN)..."

if [[ -z "${GH_TOKEN:-}" ]] && [[ "$DRY_RUN" != "true" ]]; then
  echo "⚠️ GH_TOKEN not available, skipping ruleset setup"
  if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$REPO_FULL_NAME" --body \
      "⚠️ **Warning:** Unable to reconcile repository rulesets (no admin token). Configure manually under Settings → Rules → Rulesets from \`.github/rulesets/\`." || true
  fi
  RULESET_SUCCESS=false
  [[ -n "${GITHUB_ENV:-}" ]] && echo "RULESET_SUCCESS=$RULESET_SUCCESS" >> "$GITHUB_ENV"
  exit 0
fi
export GH_TOKEN

# SERVICE_NAME and MAVEN_PROFILE default at runtime (ADR-035, ADR-037), so they
# do not gate deploy; only the inputs with no default do.
deploy_ready() {
  local ready=true name
  local secret_names variable_names
  secret_names="$(gh api --paginate "repos/${REPO_FULL_NAME}/actions/secrets" --jq '.secrets[].name' 2>/dev/null || echo "")"
  variable_names="$(gh api --paginate "repos/${REPO_FULL_NAME}/actions/variables" --jq '.variables[].name' 2>/dev/null || echo "")"
  grep -qx "AZURE_CLIENT_ID" <<< "$secret_names" || ready=false
  for name in ACCEPTANCE_TEST_DIR ACCEPTANCE_TEST_SECRET_MAP ACCEPTANCE_TEST_DEPENDENCIES K8S_DEPLOYMENT_NAME K8S_CONTAINER_NAME; do
    grep -qx "$name" <<< "$variable_names" || ready=false
  done
  [[ "$ready" == "true" ]]
}

if deploy_ready; then DEPLOY_READY=true; else DEPLOY_READY=false; fi
echo "Deploy-ready: $DEPLOY_READY (controls whether deploy/integration-test checks are required)"

# Strips the deploy and test checks from the payload when the fork is not deploy-ready.
build_payload() {
  local config_file="$1"
  if [[ "$DEPLOY_READY" == "true" ]]; then
    cat "$config_file"
    return
  fi
  local filter='(.. | objects | select(has("required_status_checks")).required_status_checks)
    |= map(select(.context as $c | $strip | index($c) | not))'
  jq --argjson strip "$(printf '%s\n' "${DEPLOY_CHECKS[@]}" | jq -R . | jq -s .)" "$filter" "$config_file"
}

apply_ruleset() {
  local config_file="$1"
  if [[ ! -f "$config_file" ]]; then
    echo "⚠️ Configuration file $config_file not found"
    RULESET_SUCCESS=false
    return
  fi
  local name payload existing_id resp
  name="$(jq -r '.name' "$config_file")"
  payload="$(build_payload "$config_file")"
  existing_id="$(gh api "repos/${REPO_FULL_NAME}/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null | head -n1 || echo "")"

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$existing_id" ]]; then echo "DRY-RUN would UPDATE '$name' (id $existing_id)"; else echo "DRY-RUN would CREATE '$name'"; fi
    echo "$payload" | jq -r '"  required checks: " + ((.. | objects | select(has("required_status_checks")).required_status_checks // [] | map(.context) | join(", ")))' 2>/dev/null || true
    return
  fi

  if [[ -n "$existing_id" ]]; then
    if resp="$(echo "$payload" | gh api --method PUT -H "Accept: application/vnd.github+json" \
        "repos/${REPO_FULL_NAME}/rulesets/${existing_id}" --input - 2>&1)"; then
      echo "✅ Updated '$name' ruleset (id $existing_id)"
    else
      echo "⚠️ Failed to update '$name' ruleset: $resp"; RULESET_SUCCESS=false
    fi
  else
    if resp="$(echo "$payload" | gh api --method POST -H "Accept: application/vnd.github+json" \
        "repos/${REPO_FULL_NAME}/rulesets" --input - 2>&1)"; then
      echo "✅ Created '$name' ruleset"
    else
      echo "⚠️ Failed to create '$name' ruleset: $resp"; RULESET_SUCCESS=false
    fi
  fi
}

apply_ruleset ".github/rulesets/default-branch.json"
apply_ruleset ".github/rulesets/integration-branch.json"

[[ -n "${GITHUB_ENV:-}" ]] && echo "RULESET_SUCCESS=$RULESET_SUCCESS" >> "$GITHUB_ENV"
echo "Ruleset reconciliation complete: $RULESET_SUCCESS"
