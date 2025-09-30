#!/usr/bin/env bash
#
# Get Upstream SHA Script
#
# Retrieves the current SHA from the upstream remote's default branch.
#
# Arguments:
#   $1 - Default branch name (e.g., "main" or "master")
#
# Outputs:
#   upstream_sha - SHA of upstream's default branch (via GITHUB_OUTPUT)
#
# Usage:
#   ./get-upstream-sha.sh "main"

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <default_branch>"
  exit 1
fi

DEFAULT_BRANCH="$1"

# Get the current upstream SHA
UPSTREAM_SHA=$(git rev-parse "upstream/$DEFAULT_BRANCH")
echo "Current upstream SHA: $UPSTREAM_SHA"

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "upstream_sha=$UPSTREAM_SHA" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "upstream_sha=$UPSTREAM_SHA"