#!/usr/bin/env bash
#
# Prints the SHA of the upstream remote's default branch.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <default_branch>"
  exit 1
fi

DEFAULT_BRANCH="$1"

UPSTREAM_SHA=$(git rev-parse "upstream/$DEFAULT_BRANCH")
echo "Current upstream SHA: $UPSTREAM_SHA"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "upstream_sha=$UPSTREAM_SHA" >> "$GITHUB_OUTPUT"
fi

echo "upstream_sha=$UPSTREAM_SHA"