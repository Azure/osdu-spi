#!/usr/bin/env bash
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Verifies a freshly pushed GHCR package is public so the shared spi-stack AKS
# cluster can pull it without an imagePullSecret (ADR-033). Never fails the build.
#
# GHCR has no REST API to change package visibility (GET and DELETE only). It is
# governed by the owner's default and is sticky once set, so this reports the
# one-time fix instead of calling a nonexistent endpoint.
#
# Env: GITHUB_TOKEN (package read scope)
# Local: GITHUB_TOKEN=*** ./set-package-visibility.sh my-org partition

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <org> <package_name>"
  exit 1
fi

# GHCR names are lowercase.
ORG="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
PACKAGE_NAME="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "⚠️  GITHUB_TOKEN not set; skipping visibility check."
  exit 0
fi

# Org packages live under /orgs/<org>/; a user's own packages under /user/
# (not /users/<user>/, which is read-only).
OWNER_TYPE="$(gh api "/users/${ORG}" --jq '.type' 2>/dev/null || echo "")"
if [[ "$OWNER_TYPE" == "Organization" ]]; then
  BASE="orgs/${ORG}"
  SETTINGS_URL="https://github.com/orgs/${ORG}/packages/container/${PACKAGE_NAME}/settings"
else
  BASE="user"
  SETTINGS_URL="https://github.com/users/${ORG}/packages/container/${PACKAGE_NAME}/settings"
fi

CURRENT="$(gh api "${BASE}/packages/container/${PACKAGE_NAME}" --jq '.visibility' 2>/dev/null || echo "")"
if [[ -z "$CURRENT" ]]; then
  echo "ℹ Package ${ORG}/${PACKAGE_NAME} not found or not readable; skipping visibility check."
  exit 0
fi

if [[ "$CURRENT" == "public" ]]; then
  echo "✓ Package ${ORG}/${PACKAGE_NAME} is public."
  exit 0
fi

# GHCR has no API to flip visibility, so report the one-time fix.
echo "⚠️  Package ${ORG}/${PACKAGE_NAME} is '${CURRENT}', not public — cluster pulls will fail with ErrImagePull."
echo "    GHCR has no API to change visibility. Make it public once (sticky) at:"
echo "    ${SETTINGS_URL}"
echo "    Set the owner's default package visibility to Public so future packages are born public."

exit 0
