#!/bin/bash
# Configure Git Identity
#
# Configures git user identity for GitHub Actions bot commits.
#
# Inputs (via environment):
#   PULL_REBASE - Set pull.rebase configuration (true/false/empty)

set -euo pipefail

# Always configure bot identity
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Configure pull behavior if requested
if [[ "${PULL_REBASE:-}" == "true" ]]; then
    git config pull.rebase true
elif [[ "${PULL_REBASE:-}" == "false" ]]; then
    git config pull.rebase false
fi

echo "✅ Git configured for github-actions[bot]"