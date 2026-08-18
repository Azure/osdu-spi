#!/usr/bin/env bash
#
# Check the deploy-onboarding readiness manifest and surface what's missing.
#
# Verifies presence (never values) of the secrets/variables a fork needs before
# the deploy + integration-test required checks can be enabled, and validates the
# fork-owned service descriptor (ADR-039). Opens/updates a single `human-required`
# tracking issue listing what's missing and who owns it; closes that issue when
# everything is present.
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
# Descriptor findings are reported as field paths + stable error codes only, so no
# descriptor or secret value ever reaches the issue body.

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
variables_json="$(gh api --paginate --slurp "repos/${REPO}/actions/variables?per_page=100" 2>/dev/null || echo '[{"variables":[]}]')"
variable_names="$(jq -r '.[].variables[].name' <<< "$variables_json")"
no_data_token_env="$(jq -r '[.[].variables[] | select(.name == "NO_DATA_ACCESS_TOKEN_ENV") | .value][0] // ""' <<< "$variables_json")"

missing=()
have_secret() { grep -qx "$1" <<< "$secret_names"; }
have_var()    { grep -qx "$1" <<< "$variable_names"; }

have_secret "AZURE_CLIENT_ID" || missing+=("secret \`AZURE_CLIENT_ID\` — set by \`spi onboard\`")
for v in K8S_DEPLOYMENT_NAME K8S_CONTAINER_NAME; do
  have_var "$v" || missing+=("variable \`$v\` — set by \`spi onboard\`")
done
if [[ -n "$no_data_token_env" ]]; then
  have_var "NO_DATA_ACCESS_TESTER_CLIENT_ID" \
    || missing+=("variable \`NO_DATA_ACCESS_TESTER_CLIENT_ID\` — set by \`spi onboard\` for negative-authorization tests")
fi
for v in ACCEPTANCE_TEST_DIR ACCEPTANCE_TEST_SECRET_MAP ACCEPTANCE_TEST_DEPENDENCIES; do
  have_var "$v" || missing+=("variable \`$v\` — set by the operator")
done

# --- Service descriptor + descriptor ownership (ADR-039) ---------------------
# Reported through this same deduplicated issue rather than a competing tracker.
READ_SERVICE_CONFIG=".github/scripts/service-config/read_service_config.py"
if [[ -f "$READ_SERVICE_CONFIG" ]]; then
  config_json="$(python3 "$READ_SERVICE_CONFIG" --root . --format json --redact 2>/dev/null || true)"
  if [[ -z "$config_json" ]] || ! jq empty <<< "$config_json" 2>/dev/null; then
    missing+=("service descriptor could not be evaluated — run \`python3 $READ_SERVICE_CONFIG --root . --format json\` locally")
  else
    descriptor_present="$(jq -r '.descriptor_present' <<< "$config_json")"
    descriptor_valid="$(jq -r '.valid' <<< "$config_json")"
    lane_implemented="$(jq -r '.lane_implemented' <<< "$config_json")"
    archetype="$(jq -r '.archetype' <<< "$config_json")"
    if [[ "$descriptor_present" != "true" ]]; then
      missing+=("service descriptor \`.spi/service.yaml\` — generate with \`python3 .github/scripts/service-config/generate_descriptor.py --root .\` (legacy Java inference is in use)")
    elif [[ "$descriptor_valid" != "true" ]]; then
      codes="$(jq -r '[.errors[]] | join("; ")' <<< "$config_json")"
      missing+=("service descriptor \`.spi/service.yaml\` is invalid — $codes")
    elif [[ "$lane_implemented" != "true" ]]; then
      missing+=("archetype \`$archetype\` has no build lane in this template version — apply the latest template-sync PR before enabling required checks")
    fi
  fi
fi

GENERATE_CODEOWNERS=".github/scripts/service-config/generate_codeowners.py"
if [[ -f "$GENERATE_CODEOWNERS" ]]; then
  if ! python3 "$GENERATE_CODEOWNERS" --path CODEOWNERS --check >/dev/null 2>&1; then
    missing+=("CODEOWNERS rule for \`/.spi/\` — set variable \`SPI_ENGINEERING_OWNERS\`, then run \`python3 .github/scripts/service-config/generate_codeowners.py --path CODEOWNERS --owners \"@org/team\"\` and commit the result")
  fi
fi

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

body="$(printf 'The deploy and integration-test required checks stay disabled until the following are set on this repository:\n\n'; printf -- '- [ ] %s\n' "${missing[@]}"; printf '\nBuild-side identity (`SERVICE_NAME`, `MAVEN_PROFILE`, `SERVICE_TARGET_JAR`) defaults at runtime and is not required.\nService-descriptor findings list field paths and error codes only; no descriptor, secret or variable value is reproduced here.\n\n_Maintained automatically by `settings-apply.yml`._\n')"

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
