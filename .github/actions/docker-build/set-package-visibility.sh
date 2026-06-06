#!/usr/bin/env bash
#
# Verify Package Visibility Script
#
# Verifies a freshly-pushed GHCR container package is public so the shared
# spi-stack AKS cluster can pull it without an imagePullSecret (ADR-033).
#
# GHCR exposes NO REST API to change package visibility (GET/DELETE only).
# Visibility is governed by the owner's default package visibility and is
# sticky once set, so this verifies and reports an actionable remediation rather
# than calling a nonexistent endpoint. SOFT-FAIL: never fails the build.
#
# Arguments:
#   $1 - org/owner (e.g. my-org)
#   $2 - package name == image name (e.g. partition)
#
# Environment:
#   GITHUB_TOKEN - token with package read scope (passed by the action's push path)
#
# Local usage:
#   GITHUB_TOKEN=*** ./set-package-visibility.sh my-org partition

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <org> <package_name>"
  exit 1
fi

# GHCR owner/package names are lowercase; normalize before hitting the API
ORG="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
PACKAGE_NAME="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "⚠️  GITHUB_TOKEN not set; skipping visibility check."
  exit 0
fi

# Discriminate org-owned vs user-owned to choose the correct packages namespace.
# Org packages live under /orgs/<org>/...; a user's own packages are written via the
# authenticated-user namespace /user/... (NOT /users/<user>/..., which is read-only).
OWNER_TYPE="$(gh api "/users/${ORG}" --jq '.type' 2>/dev/null || echo "")"
if [[ "$OWNER_TYPE" == "Organization" ]]; then
  BASE="orgs/${ORG}"
  SETTINGS_URL="https://github.com/orgs/${ORG}/packages/container/${PACKAGE_NAME}/settings"
else
  BASE="user"
  SETTINGS_URL="https://github.com/users/${ORG}/packages/container/${PACKAGE_NAME}/settings"
fi

# Read current visibility; an empty result means the package is missing or unreadable (skip silently)
CURRENT="$(gh api "${BASE}/packages/container/${PACKAGE_NAME}" --jq '.visibility' 2>/dev/null || echo "")"
if [[ -z "$CURRENT" ]]; then
  echo "ℹ Package ${ORG}/${PACKAGE_NAME} not found or not readable; skipping visibility check."
  exit 0
fi

if [[ "$CURRENT" == "public" ]]; then
  echo "✓ Package ${ORG}/${PACKAGE_NAME} is public."
  exit 0
fi

# Not public, and GHCR has no API to flip visibility — report the one-time fix.
echo "⚠️  Package ${ORG}/${PACKAGE_NAME} is '${CURRENT}', not public — cluster pulls will fail with ErrImagePull."
echo "    GHCR has no API to change visibility. Make it public once (sticky) at:"
echo "    ${SETTINGS_URL}"
echo "    Set the owner's default package visibility to Public so future packages are born public."

exit 0
