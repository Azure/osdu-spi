#!/usr/bin/env bash
#
# Checks that the five values the deploy lane needs are present (names only,
# never values) and keeps one human-required tracking issue in step with what
# is missing. `spi onboard` writes all five; a fork without them skips the
# lane with a visible reason rather than failing.
#
# SERVICE_NAME, MAVEN_PROFILE, and SERVICE_TARGET_JAR are not listed: they
# default at runtime (ADR-035, ADR-037), so only overrides use them.
#
# Arguments:
#   $1            Repository full name (owner/repo)
#   --dry-run     Print the assessment without touching the issue
#
# Environment:
#   GH_TOKEN      issues:write, plus repo admin for the name-listing fallback
#   HAVE_<NAME>   "true"/"false" from workflow context, authoritative when set. The name
#                 listing below is only for local runs: the App installation may not
#                 carry Secrets: read, and org-level values never appear in it.

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

REQUIRED_SECRETS=(AZURE_CLIENT_ID)
REQUIRED_VARS=(AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID SPI_STACK_RESOURCE_GROUP SPI_STACK_CLUSTER)

flagged() { local flag="HAVE_$1"; [[ -n "${!flag:-}" ]]; }

# Only a run without flags (local, or an older workflow) needs the name listings.
secret_names=""; variable_names=""
for n in "${REQUIRED_SECRETS[@]}" "${REQUIRED_VARS[@]}"; do
  if ! flagged "$n"; then
    secret_names="$(gh api --paginate "repos/${REPO}/actions/secrets" --jq '.secrets[].name' 2>/dev/null \
      || { echo "secret listing unavailable; relying on HAVE_* flags" >&2; echo ""; })"
    variable_names="$(gh api --paginate "repos/${REPO}/actions/variables" --jq '.variables[].name' 2>/dev/null || echo "")"
    break
  fi
done

missing=()
have() {
  local flag="HAVE_$1"
  if flagged "$1"; then [[ "${!flag}" == "true" ]]; else grep -qx "$1" <<< "$2"; fi
}

for s in "${REQUIRED_SECRETS[@]}"; do
  have "$s" "$secret_names" || missing+=("secret \`$s\`, set by \`spi onboard\`")
done
for v in "${REQUIRED_VARS[@]}"; do
  have "$v" "$variable_names" || missing+=("variable \`$v\`, set by \`spi onboard\`")
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

body="$(printf 'The Deploy and Test lane skips until the following are set on this repository:\n\n'; printf -- '- [ ] %s\n' "${missing[@]}"; printf '\nBuild-side identity (`SERVICE_NAME`, `MAVEN_PROFILE`, `SERVICE_TARGET_JAR`) defaults at runtime and is not required.\n\n_Maintained automatically by `settings-apply.yml`._\n')"

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
