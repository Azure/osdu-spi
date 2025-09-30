#!/usr/bin/env bash
#
# Make Sync Decision Script
#
# Implements the decision matrix for sync operations based on upstream state
# and existing PRs/issues.
#
# Decision Matrix:
#   1. No PR + Upstream Changed    -> Create new PR and issue
#   2. Existing PR + No Change     -> Add reminder comment
#   3. Existing PR + Upstream Changed -> Update existing branch/PR
#   4. No PR + No Change           -> No action
#
# Arguments:
#   $1 - Current upstream SHA
#   $2 - Last upstream SHA (from stored state)
#   $3 - Has existing PR (true/false)
#   $4 - Has existing issue (true/false)
#   $5 - Existing PR number (can be empty)
#   $6 - Existing issue number (can be empty)
#   $7 - Existing PR branch (can be empty)
#
# Outputs:
#   should_create_pr - true/false
#   should_create_issue - true/false
#   should_update_branch - true/false
#   existing_pr_number - PR number if exists
#   existing_issue_number - Issue number if exists
#   existing_branch_name - Branch name if exists
#   sync_decision - Decision reason (create_new, add_reminder, update_existing, no_action)
#
# Usage:
#   ./make-sync-decision.sh \
#     "abc123" \           # current_upstream_sha
#     "def456" \           # last_upstream_sha
#     "false" \            # has_existing_pr
#     "false" \            # has_existing_issue
#     "" \                 # existing_pr_number
#     "" \                 # existing_issue_number
#     ""                   # existing_pr_branch

set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <current_sha> <last_sha> <has_pr> <has_issue> <pr_number> <issue_number> <pr_branch>"
  exit 1
fi

UPSTREAM_SHA="$1"
LAST_UPSTREAM_SHA="$2"
HAS_EXISTING_PR="$3"
HAS_EXISTING_ISSUE="$4"
EXISTING_PR_NUMBER="$5"
EXISTING_ISSUE_NUMBER="$6"
EXISTING_PR_BRANCH="$7"

# Decision matrix logic
UPSTREAM_CHANGED="false"
if [[ "$UPSTREAM_SHA" != "$LAST_UPSTREAM_SHA" ]]; then
  UPSTREAM_CHANGED="true"
fi

echo "Decision inputs:"
echo "  Upstream changed: $UPSTREAM_CHANGED ($UPSTREAM_SHA vs $LAST_UPSTREAM_SHA)"
echo "  Has existing PR: $HAS_EXISTING_PR"
echo "  Has existing issue: $HAS_EXISTING_ISSUE"

# Apply decision matrix
if [[ "$HAS_EXISTING_PR" = "false" ]] && [[ "$UPSTREAM_CHANGED" = "true" ]]; then
  # Scenario 1: No existing PR, upstream changed -> Create new PR and issue
  SHOULD_CREATE_PR="true"
  SHOULD_CREATE_ISSUE="true"
  SHOULD_UPDATE_BRANCH="false"
  OUT_PR_NUMBER=""
  OUT_ISSUE_NUMBER=""
  OUT_BRANCH_NAME=""
  SYNC_DECISION="create_new"
  echo "🆕 Decision: Create new PR and issue (upstream changed, no existing PR)"

elif [[ "$HAS_EXISTING_PR" = "true" ]] && [[ "$UPSTREAM_CHANGED" = "false" ]]; then
  # Scenario 2: Existing PR, upstream unchanged -> Add reminder comment
  SHOULD_CREATE_PR="false"
  SHOULD_CREATE_ISSUE="false"
  SHOULD_UPDATE_BRANCH="false"
  OUT_PR_NUMBER="$EXISTING_PR_NUMBER"
  OUT_ISSUE_NUMBER="$EXISTING_ISSUE_NUMBER"
  OUT_BRANCH_NAME="$EXISTING_PR_BRANCH"
  SYNC_DECISION="add_reminder"
  echo "📝 Decision: Add reminder comment (upstream unchanged, existing PR)"

elif [[ "$HAS_EXISTING_PR" = "true" ]] && [[ "$UPSTREAM_CHANGED" = "true" ]]; then
  # Scenario 3: Existing PR, upstream changed -> Update existing branch and PR
  SHOULD_CREATE_PR="false"
  SHOULD_CREATE_ISSUE="false"
  SHOULD_UPDATE_BRANCH="true"
  OUT_PR_NUMBER="$EXISTING_PR_NUMBER"
  OUT_ISSUE_NUMBER="$EXISTING_ISSUE_NUMBER"
  OUT_BRANCH_NAME="$EXISTING_PR_BRANCH"
  SYNC_DECISION="update_existing"
  echo "🔄 Decision: Update existing branch and PR (upstream changed, existing PR)"

else
  # Scenario 4: No existing PR, upstream unchanged -> No action
  SHOULD_CREATE_PR="false"
  SHOULD_CREATE_ISSUE="false"
  SHOULD_UPDATE_BRANCH="false"
  OUT_PR_NUMBER=""
  OUT_ISSUE_NUMBER=""
  OUT_BRANCH_NAME=""
  SYNC_DECISION="no_action"
  echo "✅ Decision: No action needed (upstream unchanged, no existing PR)"
fi

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "should_create_pr=$SHOULD_CREATE_PR" >> "$GITHUB_OUTPUT"
  echo "should_create_issue=$SHOULD_CREATE_ISSUE" >> "$GITHUB_OUTPUT"
  echo "should_update_branch=$SHOULD_UPDATE_BRANCH" >> "$GITHUB_OUTPUT"
  echo "existing_pr_number=$OUT_PR_NUMBER" >> "$GITHUB_OUTPUT"
  echo "existing_issue_number=$OUT_ISSUE_NUMBER" >> "$GITHUB_OUTPUT"
  echo "existing_branch_name=$OUT_BRANCH_NAME" >> "$GITHUB_OUTPUT"
  echo "sync_decision=$SYNC_DECISION" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "should_create_pr=$SHOULD_CREATE_PR"
echo "should_create_issue=$SHOULD_CREATE_ISSUE"
echo "should_update_branch=$SHOULD_UPDATE_BRANCH"
echo "existing_pr_number=$OUT_PR_NUMBER"
echo "existing_issue_number=$OUT_ISSUE_NUMBER"
echo "existing_branch_name=$OUT_BRANCH_NAME"
echo "sync_decision=$SYNC_DECISION"