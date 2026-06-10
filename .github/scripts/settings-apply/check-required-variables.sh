#!/usr/bin/env bash
#
# Check the deploy-onboarding readiness manifest and surface what's missing.
#
# Verifies presence (never values) of the secrets/variables a fork needs before
# the deploy + integration-test required checks can be enabled. Opens/updates a
# single `human-required` tracking issue listing what's missing and who owns it;
# closes that issue when everything is present.
#
# SERVICE_NAME / MAVEN_PROFILE / SERVICE_TARGET_JAR are NOT listed: they default
# at runtime (ADR-035/037), so they never block onboarding — only overrides.
#
# Arguments:
#   $1            Repository full name (owner/repo)
#   --dry-run     Print the assessment without opening/closing the issue
#
# Environment:
#   GH_TOKEN      Token with repo admin (read secret/variable names) + issues:write
#
# AZURE_CLIENT_ID is checked present-only; its value is never read or logged.

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

ISSUE_TITLE="⚙️ Deploy onboarding: required CI configuration missing"

secret_names="$(gh api --paginate "repos/${REPO}/actions/secrets" --jq '.secrets[].name' 2>/dev/null || echo "")"
variable_names="$(gh api --paginate "repos/${REPO}/actions/variables" --jq '.variables[].name' 2>/dev/null || echo "")"

missing=()
have_secret() { grep -qx "$1" <<< "$secret_names"; }
have_var()    { grep -qx "$1" <<< "$variable_names"; }

have_secret "AZURE_CLIENT_ID" || missing+=("secret \`AZURE_CLIENT_ID\` — set by \`spi onboard\`")
for v in K8S_DEPLOYMENT_NAME K8S_CONTAINER_NAME; do
  have_var "$v" || missing+=("variable \`$v\` — set by \`spi onboard\`")
done
for v in ACCEPTANCE_TEST_DIR ACCEPTANCE_TEST_SECRET_MAP ACCEPTANCE_TEST_DEPENDENCIES; do
  have_var "$v" || missing+=("variable \`$v\` — set by the operator")
done

existing_issue="$(gh issue list --repo "$REPO" --state open --search "in:title \"$ISSUE_TITLE\"" --json number --jq '.[0].number // empty' 2>/dev/null || echo "")"

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "✅ Deploy-onboarding manifest complete."
  if [[ -n "$existing_issue" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "DRY-RUN would close issue #$existing_issue (manifest now complete)"
    else
      gh issue close "$existing_issue" --repo "$REPO" --comment "All required deploy-onboarding configuration is now present. Closing." || true
    fi
  fi
  exit 0
fi

echo "⚠️ Missing ${#missing[@]} required item(s) for deploy onboarding:"
printf '   - %s\n' "${missing[@]}"

body="$(printf 'The deploy and integration-test required checks stay disabled until the following are set on this repository:\n\n'; printf -- '- [ ] %s\n' "${missing[@]}"; printf '\nBuild-side identity (`SERVICE_NAME`, `MAVEN_PROFILE`, `SERVICE_TARGET_JAR`) defaults at runtime and is not required.\n\n_Maintained automatically by `settings-apply.yml`._\n')"

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
