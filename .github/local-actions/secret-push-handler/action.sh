#!/bin/bash
# Push Protection Error Detection and Reporting
#
# Analyzes git push output for push protection violations and creates
# detailed GitHub issues with resolution guidance including secret allowlist URLs.
#
# Inputs (via environment):
#   PUSH_OUTPUT_FILE - Path to file containing git push output
#   ISSUE_NUMBER - GitHub issue number for commenting
#   UPSTREAM_REPO - Upstream repository being synced
#   GITHUB_TOKEN - GitHub token for API access
#
# Outputs (to GITHUB_OUTPUT and stdout):
#   push_protected=true/false - Whether push protection was detected
#   escalation_issue_url=<url> - URL of created escalation issue (if applicable)

set -euo pipefail

# Validate required inputs
if [ -z "${PUSH_OUTPUT_FILE:-}" ]; then
    echo "::error::PUSH_OUTPUT_FILE environment variable is required"
    exit 1
fi

if [ ! -f "$PUSH_OUTPUT_FILE" ]; then
    echo "::error::Push output file not found: $PUSH_OUTPUT_FILE"
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

# Check for push protection violation
if ! grep -q "GH013: Repository rule violations found" "$PUSH_OUTPUT_FILE"; then
    echo "push_protected=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "No push protection violation detected"
    exit 0
fi

echo "::error::Push blocked by push protection due to secrets"
echo "push_protected=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"

# Extract secret allowlist URLs (handles ANSI escape codes)
SECRETS_INFO=$(grep -Eo 'https://github\.com/.+/secret-scanning/unblock-secret/[A-Za-z0-9]+' \
               "$PUSH_OUTPUT_FILE" | head -20 || true)

# Extract blob IDs (GitHub format: "blob id: <hash>")
BLOB_IDS=$(grep -Eo 'blob id: *[a-f0-9]+' "$PUSH_OUTPUT_FILE" \
           | sed -E 's/^blob id: *//' | head -20 || true)

# Build escalation issue body
ISSUE_BODY="## 🔒 Push Protection Blocking Initialization\n\n"
ISSUE_BODY="${ISSUE_BODY}The initialization workflow was blocked by push protection. This is likely due to secrets detected in the upstream repository's git history.\n\n"
ISSUE_BODY="${ISSUE_BODY}### Detected Issues\n\n"

if [ -n "$BLOB_IDS" ]; then
    ISSUE_BODY="${ISSUE_BODY}### Detected Secret Blob IDs\n\`\`\`\n${BLOB_IDS}\n\`\`\`\n\n"
fi

ISSUE_BODY="${ISSUE_BODY}### Resolution Options\n\n"
ISSUE_BODY="${ISSUE_BODY}1. **✅ Recommended: Use Secret Allowlist URLs** (Manual Process)\n"
ISSUE_BODY="${ISSUE_BODY}   - **Important**: This requires manual action - GitHub requires human approval for security\n"
ISSUE_BODY="${ISSUE_BODY}   - Click each URL below in your browser while logged into GitHub\n"
ISSUE_BODY="${ISSUE_BODY}   - Review each secret and click \"Allow secret\" if it's safe to include\n"
ISSUE_BODY="${ISSUE_BODY}   - After allowing all secrets, comment the upstream repo URL on the original issue to re-run initialization\n\n"

if [ -n "$SECRETS_INFO" ]; then
    ISSUE_BODY="${ISSUE_BODY}   **Secret Allowlist URLs** (click each one):\n"
    while IFS= read -r url; do
        [ -n "$url" ] && ISSUE_BODY="${ISSUE_BODY}   - [Allow Secret](${url})\n"
    done <<< "$SECRETS_INFO"
else
    ISSUE_BODY="${ISSUE_BODY}   ⚠️ No allowlist URLs detected in output - check workflow logs\n"
fi

ISSUE_BODY="${ISSUE_BODY}\n2. **Alternative: Organization Admin Action**\n"
ISSUE_BODY="${ISSUE_BODY}   - Ask your organization admin to temporarily disable push protection\n"
ISSUE_BODY="${ISSUE_BODY}   - Re-run the initialization after it's disabled\n"
ISSUE_BODY="${ISSUE_BODY}   - Re-enable push protection after initialization completes\n\n"

ISSUE_BODY="${ISSUE_BODY}3. **Manual Initialization**\n"
ISSUE_BODY="${ISSUE_BODY}   - Clone the repository locally\n"
ISSUE_BODY="${ISSUE_BODY}   - Run the initialization steps manually\n"
ISSUE_BODY="${ISSUE_BODY}   - Use \`git push --no-verify\` if you have appropriate permissions\n\n"

ISSUE_BODY="${ISSUE_BODY}### Workflow Run\n"
ISSUE_BODY="${ISSUE_BODY}[View workflow logs](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-})\n\n"

ISSUE_BODY="${ISSUE_BODY}### Next Steps\n"
ISSUE_BODY="${ISSUE_BODY}After resolving the push protection issue using one of the methods above, please:\n"
ISSUE_BODY="${ISSUE_BODY}1. Close this issue\n"
ISSUE_BODY="${ISSUE_BODY}2. Re-run the initialization by commenting the upstream repository URL on the original initialization issue"

# Create escalation issue
ESCALATION_ISSUE_URL=$(printf "%b" "$ISSUE_BODY" | gh issue create \
    --title "🔒 Push Protection Blocking Initialization - Action Required" \
    --body-file - \
    --label "initialization,escalation" || true)

if [ -n "$ESCALATION_ISSUE_URL" ]; then
    echo "escalation_issue_url=$ESCALATION_ISSUE_URL" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    COMMENT_MSG="❌ **Initialization blocked by push protection**\n\nThe upstream repository contains secrets that are being blocked by GitHub's push protection.\n\n**Next Steps:**\n1. 📋 I've created a detailed issue with allowlist URLs: $ESCALATION_ISSUE_URL\n2. 🔓 Visit each allowlist URL and click 'Allow secret'\n3. 🔄 Re-run initialization by commenting \`${UPSTREAM_REPO:-the upstream repository}\` again\n\nThe second run will succeed once secrets are allowlisted!"
else
    echo "escalation_issue_url=" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    COMMENT_MSG="❌ **Initialization blocked by push protection**\n\nThe upstream repository contains secrets that are being blocked by GitHub's push protection.\n\n**Next Steps:**\n1. 📋 I've created a detailed issue with allowlist URLs - check issues labeled 'escalation'\n2. 🔓 Visit each allowlist URL and click 'Allow secret'\n3. 🔄 Re-run initialization by commenting \`${UPSTREAM_REPO:-the upstream repository}\` again\n\nThe second run will succeed once secrets are allowlisted!"
fi

# Comment on original initialization issue
printf "%b" "$COMMENT_MSG" | gh issue comment "$ISSUE_NUMBER" --body-file -

echo "✅ Created escalation issue and commented on initialization issue"