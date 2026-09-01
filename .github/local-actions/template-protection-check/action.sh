#!/bin/bash
# Keeps the initialization workflows from running in the template repository
# itself, using either the IS_TEMPLATE variable or GitHub's is_template flag.
#
# Inputs (via environment):
#   IS_TEMPLATE - repository variable
#   GITHUB_IS_TEMPLATE - GitHub's template flag
#
# Outputs (to GITHUB_OUTPUT):
#   is_template - true/false

set -euo pipefail

IS_TEMPLATE_VAR="${IS_TEMPLATE:-false}"
GITHUB_TEMPLATE_FLAG="${GITHUB_IS_TEMPLATE:-false}"

if [[ "$IS_TEMPLATE_VAR" == "true" ]]; then
    echo "🛡️ IS_TEMPLATE variable is true - blocking init workflow execution"
    echo "This prevents accidental initialization in the template development repository"
    echo "is_template=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    exit 0
fi

if [[ "$GITHUB_TEMPLATE_FLAG" == "true" ]]; then
    echo "🛡️ GitHub template flag is true - blocking init workflow execution"
    echo "is_template=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    exit 0
fi

echo "✅ Safety check passed - not a template repository"
echo "is_template=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
exit 0