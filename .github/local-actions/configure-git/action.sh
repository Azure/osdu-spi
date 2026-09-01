#!/bin/bash
# Sets the github-actions[bot] commit identity.
#
# Inputs (via environment):
#   PULL_REBASE - sets pull.rebase when "true" or "false"

set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

if [[ "${PULL_REBASE:-}" == "true" ]]; then
    git config pull.rebase true
elif [[ "${PULL_REBASE:-}" == "false" ]]; then
    git config pull.rebase false
fi

echo "✅ Git configured for github-actions[bot]"