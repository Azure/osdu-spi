#!/usr/bin/env bash
set -euo pipefail

#
# rotate-app-key.sh
#
# Distributes a GitHub App private key from Azure Key Vault to GitHub secrets.
#
# Prerequisites:
#   - az CLI (authenticated)
#   - gh CLI (authenticated with admin access to repo and org)
#
# Usage:
#   .github/scripts/rotate-app-key.sh \
#     --vault-name <vault> \
#     --secret-name <secret> \
#     --repo <owner/repo> \
#     --org <org> \
#     [--github-secret <name>] \
#     [--dry-run]
#
# Example:
#   .github/scripts/rotate-app-key.sh \
#     --vault-name contoso-app-kv \
#     --secret-name app-private-key \
#     --repo contoso/my-service \
#     --org contoso-forks
#

VAULT_NAME=""
SECRET_NAME=""
REPO=""
ORG=""
GITHUB_SECRET="RELEASE_APP_PRIVATE_KEY"
DRY_RUN=false

usage() {
  local exit_code="${1:-1}"
  echo "Usage: $0 --vault-name <vault> --secret-name <secret> --repo <owner/repo> --org <org> [--github-secret <name>] [--dry-run]"
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
    --vault-name)
      require_arg "$1" "$2"
      VAULT_NAME="$2"
      shift 2
      ;;
    --secret-name)
      require_arg "$1" "$2"
      SECRET_NAME="$2"
      shift 2
      ;;
    --repo)
      require_arg "$1" "$2"
      REPO="$2"
      shift 2
      ;;
    --org)
      require_arg "$1" "$2"
      ORG="$2"
      shift 2
      ;;
    --github-secret)
      require_arg "$1" "$2"
      GITHUB_SECRET="$2"
      shift 2
      ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)      usage 0 ;;
    *)              echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$VAULT_NAME" || -z "$SECRET_NAME" || -z "$REPO" || -z "$ORG" ]]; then
  echo "ERROR: Missing required arguments."
  usage
fi

if $DRY_RUN; then
  echo "[DRY RUN] No changes will be made."
fi

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

echo "==> Fetching private key from Key Vault ($VAULT_NAME)..."

KEY_VALUE=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query value -o tsv)

if [[ -z "$KEY_VALUE" ]]; then
  echo "ERROR: Failed to retrieve secret '$SECRET_NAME' from vault '$VAULT_NAME'."
  exit 1
fi

echo "    Key retrieved from Key Vault."

if $DRY_RUN; then
  echo "[DRY RUN] Would update $GITHUB_SECRET on repo $REPO"
  echo "[DRY RUN] Would update $GITHUB_SECRET on org $ORG"
else
  echo "==> Updating repo secret on $REPO..."
  printf '%s' "$KEY_VALUE" | gh secret set "$GITHUB_SECRET" --repo "$REPO"
  echo "    Done."

  echo "==> Updating org secret on $ORG..."
  printf '%s' "$KEY_VALUE" | gh secret set "$GITHUB_SECRET" --org "$ORG" --visibility all
  echo "    Done."
fi

echo ""
echo "==> Key rotation complete."
echo ""
echo "Next steps:"
echo "  1. Trigger a workflow to verify the new key works"
echo "  2. Revoke the old key from the GitHub App settings page"
echo "  3. Update the Key Vault secret expiry (90 days):"
echo "     az keyvault secret set-attributes \\"
echo "       --vault-name $VAULT_NAME \\"
echo "       --name $SECRET_NAME \\"
echo "       --expires \$(date -u -d '+90 days' '+%Y-%m-%dT00:00:00Z')  # GNU/Linux"
echo "       # macOS: date -u -v+90d '+%Y-%m-%dT00:00:00Z'"
