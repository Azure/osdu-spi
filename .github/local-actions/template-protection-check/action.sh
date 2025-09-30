#!/bin/bash
# Template Repository Protection Check
#
# Prevents initialization workflows from running in the template development repository.
# Checks both the IS_TEMPLATE repository variable and GitHub's is_template flag.
#
# Inputs (via environment):
#   IS_TEMPLATE - Repository variable indicating template development repository
#   GITHUB_IS_TEMPLATE - GitHub's template repository flag
#
# Outputs (to GITHUB_OUTPUT and stdout):
#   is_template=true/false - Whether this is a template repository
#
# Exit codes:
#   0 - Check completed (output indicates template status)
#   1 - Error in execution

set -euo pipefail

IS_TEMPLATE_VAR="${IS_TEMPLATE:-false}"
GITHUB_TEMPLATE_FLAG="${GITHUB_IS_TEMPLATE:-false}"

# Check IS_TEMPLATE variable first (primary protection)
if [[ "$IS_TEMPLATE_VAR" == "true" ]]; then
    echo "🛡️ IS_TEMPLATE variable is true - blocking init workflow execution"
    echo "This prevents accidental initialization in the template development repository"
    echo "is_template=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    exit 0
fi

# Check GitHub's template flag (secondary protection)
if [[ "$GITHUB_TEMPLATE_FLAG" == "true" ]]; then
    echo "🛡️ GitHub template flag is true - blocking init workflow execution"
    echo "is_template=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    exit 0
fi

# Not a template - safe to proceed
echo "✅ Safety check passed - not a template repository"
echo "is_template=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
exit 0