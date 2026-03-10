#!/usr/bin/env bash
set -euo pipefail

#
# setup-fork-repo.sh
#
# Configures a fork repository with required variables and secrets.
# Pulls all sensitive values from Azure Key Vault and sets the necessary
# GitHub Actions variables and secrets for the osdu-spi engineering system.
#
# Prerequisites:
#   - az CLI (authenticated to the tenant/subscription containing the vault)
#   - gh CLI (authenticated with write access to the target repo)
#
# Key Vault secrets used:
#   - github-app-id:          GitHub App ID for the automation app
#   - github-app-private-key: GitHub App private key (PEM format)
#   - azure-api-key:          Azure AI Foundry API key (for AI-generated PR descriptions)
#   - azure-api-base:         Azure AI Foundry endpoint URL
#   - azure-api-version:      Azure AI Foundry API version
#
# Usage:
#   .github/scripts/setup-fork-repo.sh \
#     --repo <owner/repo> \
#     --upstream <upstream-url> \
#     --vault-name <vault> \
#     [--template-repo <url>] \
#     [--dry-run]
#
# Examples:
#   # Setup partition service
#   .github/scripts/setup-fork-repo.sh \
#     --repo Azure/osdu-spi-partition \
#     --upstream https://community.opengroup.org/osdu/platform/system/partition.git \
#     --vault-name my-vault
#
#   # Dry run to verify
#   .github/scripts/setup-fork-repo.sh \
#     --repo Azure/osdu-spi-partition \
#     --upstream https://community.opengroup.org/osdu/platform/system/partition.git \
#     --vault-name my-vault \
#     --dry-run
#

# Defaults
REPO=""
UPSTREAM=""
VAULT_NAME="${AZURE_VAULT_NAME:-}"
TEMPLATE_REPO="https://github.com/Azure/osdu-spi.git"
FIREWALL_DOMAINS="community.opengroup.org,repo1.maven.org,central.maven.org,repo.maven.apache.org,plugins.gradle.org"
DRY_RUN=false

usage() {
  local exit_code="${1:-1}"
  cat <<EOF
Usage: $0 --repo <owner/repo> --upstream <upstream-url> --vault-name <vault> [options]

Required:
  --repo <owner/repo>         Target GitHub repository (e.g., Azure/osdu-spi-partition)
  --upstream <url>            Upstream repository URL
  --vault-name <name>         Azure Key Vault name (or set AZURE_VAULT_NAME env var)

Options:
  --template-repo <url>       Template repository URL (default: https://github.com/Azure/osdu-spi.git)
  --dry-run                   Show what would be done without making changes
  -h, --help                  Show this help message

Environment Variables:
  AZURE_VAULT_NAME            Default value for --vault-name
EOF
  exit "$exit_code"
}

require_arg() {
  local opt="$1"
  local val="${2-}"
  if [[ -z "$val" || "$val" == -* ]]; then
    echo "ERROR: Option '$opt' requires a non-empty value."
    usage
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)           require_arg "$1" "$2"; REPO="$2"; shift 2 ;;
    --upstream)       require_arg "$1" "$2"; UPSTREAM="$2"; shift 2 ;;
    --vault-name)     require_arg "$1" "$2"; VAULT_NAME="$2"; shift 2 ;;
    --template-repo)  require_arg "$1" "$2"; TEMPLATE_REPO="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)        usage 0 ;;
    *)                echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$REPO" || -z "$UPSTREAM" ]]; then
  echo "ERROR: --repo and --upstream are required."
  usage
fi

if [[ -z "$VAULT_NAME" ]]; then
  echo "ERROR: --vault-name is required (or set AZURE_VAULT_NAME environment variable)."
  usage
fi

if $DRY_RUN; then
  echo "[DRY RUN] No changes will be made."
  echo ""
fi

# ── Prerequisites ──────────────────────────────────────────────────

echo "==> Checking prerequisites..."

if ! command -v az &> /dev/null; then
  echo "ERROR: az CLI not found. Install: https://aka.ms/install-azure-cli"
  exit 1
fi

if ! command -v gh &> /dev/null; then
  echo "ERROR: gh CLI not found. Install: https://cli.github.com"
  exit 1
fi

az account show &> /dev/null || { echo "ERROR: Not logged in to Azure. Run: az login"; exit 1; }
gh auth status &> /dev/null || { echo "ERROR: Not logged in to GitHub. Run: gh auth login"; exit 1; }

# Verify repo exists and we have access
if ! gh api "repos/$REPO" --jq '.full_name' &> /dev/null; then
  echo "ERROR: Cannot access repository $REPO. Check permissions."
  exit 1
fi

echo "    Target repo: $REPO"
echo "    Upstream:    $UPSTREAM"
echo ""

# ── Fetch secrets from Key Vault ──────────────────────────────────

echo "==> Fetching secrets from Key Vault ($VAULT_NAME)..."

fetch_secret() {
  local name="$1"
  local value
  value=$(az keyvault secret show \
    --vault-name "$VAULT_NAME" \
    --name "$name" \
    --query value -o tsv 2>/dev/null) || true

  if [[ -z "$value" ]]; then
    echo "ERROR: Failed to retrieve '$name' from vault '$VAULT_NAME'." >&2
    echo "       Ensure the secret exists and you have access." >&2
    echo "       Check: az account show" >&2
    exit 1
  fi

  echo "    Retrieved $name" >&2
  printf '%s' "$value"
}

# GitHub App secrets
APP_ID=$(fetch_secret "github-app-id")
APP_KEY=$(fetch_secret "github-app-private-key")

# Azure AI Foundry secrets
AZURE_API_KEY=$(fetch_secret "azure-api-key")
AZURE_API_BASE=$(fetch_secret "azure-api-base")
AZURE_API_VERSION=$(fetch_secret "azure-api-version")

echo ""

# ── Variables ──────────────────────────────────────────────────────

echo "==> Setting repository variables..."

set_variable() {
  local name="$1"
  local value="$2"
  if $DRY_RUN; then
    echo "    [DRY RUN] Would set $name = $value"
  else
    gh variable set "$name" --body "$value" --repo "$REPO"
    echo "    Set $name"
  fi
}

set_variable "COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS" "$FIREWALL_DOMAINS"
set_variable "INITIALIZATION_COMPLETE" "true"
set_variable "TEMPLATE_REPO_URL" "$TEMPLATE_REPO"
set_variable "UPSTREAM_REPO_URL" "$UPSTREAM"

echo ""

# ── Secrets ────────────────────────────────────────────────────────

echo "==> Setting repository secrets..."

set_secret() {
  local name="$1"
  local value="$2"
  if $DRY_RUN; then
    echo "    [DRY RUN] Would set $name (${#value} bytes)"
  else
    printf '%s' "$value" | gh secret set "$name" --repo "$REPO"
    echo "    Set $name"
  fi
}

set_secret "RELEASE_APP_ID" "$APP_ID"
set_secret "RELEASE_APP_PRIVATE_KEY" "$APP_KEY"
set_secret "AZURE_API_KEY" "$AZURE_API_KEY"
set_secret "AZURE_API_BASE" "$AZURE_API_BASE"
set_secret "AZURE_API_VERSION" "$AZURE_API_VERSION"

echo ""

# ── Summary ────────────────────────────────────────────────────────

echo "==> Setup complete for $REPO"
echo ""
echo "Variables configured:"
echo "  - COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS"
echo "  - INITIALIZATION_COMPLETE"
echo "  - TEMPLATE_REPO_URL"
echo "  - UPSTREAM_REPO_URL"
echo ""
echo "Secrets configured:"
echo "  - RELEASE_APP_ID"
echo "  - RELEASE_APP_PRIVATE_KEY"
echo "  - AZURE_API_KEY"
echo "  - AZURE_API_BASE"
echo "  - AZURE_API_VERSION"
echo ""
echo "Next steps:"
echo "  1. Push template content to the repo (if not already done)"
echo "  2. The init workflow will trigger automatically on push to main"
echo "  3. Or, if already initialized, trigger a sync workflow to verify"
