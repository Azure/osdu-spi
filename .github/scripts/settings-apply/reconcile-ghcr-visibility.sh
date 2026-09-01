#!/usr/bin/env bash
#
# Verifies a GHCR package is public so the shared spi-stack cluster can pull it
# without an imagePullSecret (ADR-033). Same check docker-build runs after a
# push, repeated here on the settings-apply cadence.
#
# GHCR has no API to change visibility, so this only reports the fix and never
# fails the run.
#
# Arguments:
#   $1            org/owner
#   $2            package name (same as the image name)
#
# Environment:
#   GH_TOKEN | GITHUB_TOKEN - token with package read scope

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <org> <package_name>"; exit 1
fi

ORG="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
PACKAGE_NAME="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "⚠️  No token set; skipping visibility check."; exit 0
fi

# Org packages live under /orgs/<org>/...; a user's own packages under /user/... (read-write).
OWNER_TYPE="$(gh api "/users/${ORG}" --jq '.type' 2>/dev/null || echo "")"
if [[ "$OWNER_TYPE" == "Organization" ]]; then
  BASE="orgs/${ORG}"; SETTINGS_URL="https://github.com/orgs/${ORG}/packages/container/${PACKAGE_NAME}/settings"
else
  BASE="user"; SETTINGS_URL="https://github.com/users/${ORG}/packages/container/${PACKAGE_NAME}/settings"
fi

CURRENT="$(gh api "${BASE}/packages/container/${PACKAGE_NAME}" --jq '.visibility' 2>/dev/null || echo "")"
if [[ -z "$CURRENT" ]]; then
  echo "ℹ Package ${ORG}/${PACKAGE_NAME} not found or not readable; nothing to verify."; exit 0
fi
if [[ "$CURRENT" == "public" ]]; then
  echo "✓ Package ${ORG}/${PACKAGE_NAME} is public."; exit 0
fi

# Report the one-time fix; visibility is sticky once set.
echo "⚠️  Package ${ORG}/${PACKAGE_NAME} is '${CURRENT}', not public — cluster pulls will fail with ErrImagePull."
echo "    GHCR has no API to change visibility. Make it public once (sticky) at:"
echo "    ${SETTINGS_URL}"
echo "    Set the owner's default package visibility to Public so future packages are born public."
exit 0
