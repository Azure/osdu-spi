#!/bin/bash
# Validates the upstream repository a user typed into the initialization issue.
# The comment is untrusted: it arrives through the environment, never interpolated.
#
# Inputs (via environment):
#   COMMENT_BODY - untrusted comment text
#   ISSUE_NUMBER - issue for error comments
#   GITHUB_TOKEN - gh CLI token
#
# Outputs (to GITHUB_OUTPUT):
#   upstream_repo - validated identifier, empty on failure
#   should_proceed - true/false

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

REPO=$(echo "$COMMENT_BODY" | head -1 | xargs)

echo "Processing repository input: $REPO"

if [[ "$REPO" == http* ]]; then
    if ! [[ "$REPO" =~ ^https?://[^/]+/[^/]+/[^/]+(/.*)?$ ]]; then
        echo "❌ Invalid GitLab URL format: $REPO" | gh issue comment "$ISSUE_NUMBER" --body-file -
        echo "should_proceed=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        echo "upstream_repo=" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        exit 0
    fi
else
    if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        echo "❌ Invalid repository format. Expected 'owner/repo' but got '$REPO'" | gh issue comment "$ISSUE_NUMBER" --body-file -
        echo "should_proceed=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        echo "upstream_repo=" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        exit 0
    fi
fi

echo "upstream_repo=$REPO" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "should_proceed=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"

cat << EOF | gh issue comment "$ISSUE_NUMBER" --body-file -
✅ **Repository validated:** \`$REPO\`

🔄 **Starting initialization process...**

This will take a few minutes. I'll update you with progress!
EOF

echo "✅ Repository validated: $REPO"