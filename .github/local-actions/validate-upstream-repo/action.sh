#!/bin/bash
# Validate Upstream Repository
#
# Safely validates untrusted user input for upstream repository format.
# Prevents code injection by reading from environment variables, not interpolation.
#
# Inputs (via environment):
#   COMMENT_BODY - Untrusted user comment text
#   ISSUE_NUMBER - GitHub issue number for error comments
#   GITHUB_TOKEN - GitHub token for API access
#
# Outputs (to GITHUB_OUTPUT and stdout):
#   upstream_repo=<repo> - Validated repository identifier
#   should_proceed=true/false - Whether validation passed

set -euo pipefail

if [ -z "${COMMENT_BODY:-}" ]; then
    echo "::error::COMMENT_BODY environment variable is required"
    exit 1
fi

if [ -z "${ISSUE_NUMBER:-}" ]; then
    echo "::error::ISSUE_NUMBER environment variable is required"
    exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "::error::GITHUB_TOKEN environment variable is required"
    exit 1
fi

# Extract first line and trim whitespace - safe since reading from env var
REPO=$(echo "$COMMENT_BODY" | head -1 | xargs)

echo "Processing repository input: $REPO"

# Validate repository format
if [[ "$REPO" == http* ]]; then
    # GitLab URL format validation
    if ! [[ "$REPO" =~ ^https?://[^/]+/[^/]+/[^/]+(/.*)?$ ]]; then
        echo "❌ Invalid GitLab URL format: $REPO" | gh issue comment "$ISSUE_NUMBER" --body-file -
        echo "should_proceed=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        echo "upstream_repo=" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        exit 0
    fi
else
    # GitHub owner/repo format validation
    if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        echo "❌ Invalid repository format. Expected 'owner/repo' but got '$REPO'" | gh issue comment "$ISSUE_NUMBER" --body-file -
        echo "should_proceed=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        echo "upstream_repo=" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        exit 0
    fi
fi

# Validation passed - safe to output
echo "upstream_repo=$REPO" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "should_proceed=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"

# Post confirmation
cat << EOF | gh issue comment "$ISSUE_NUMBER" --body-file -
✅ **Repository validated:** \`$REPO\`

🔄 **Starting initialization process...**

This will take a few minutes. I'll update you with progress!
EOF

echo "✅ Repository validated: $REPO"