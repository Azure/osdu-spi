#!/usr/bin/env bash
#
# Decides what the sync run should do from the upstream SHA and the existing
# PR and issue state (ADR-024).
#
#   No PR + upstream changed        -> create_new       (new PR and issue)
#   Existing PR + no change         -> add_reminder     (leave everything as is)
#   Existing PR + upstream changed  -> update_existing  (update the branch and PR)
#   No PR + no change               -> no_action
#
# Arguments:
#   $1 current upstream SHA
#   $2 last upstream SHA from stored state
#   $3 has existing PR (true/false)
#   $4 has existing issue (true/false)
#   $5 existing PR number (may be empty)
#   $6 existing issue number (may be empty)
#   $7 existing PR branch (may be empty)

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

UPSTREAM_CHANGED="false"
if [[ "$UPSTREAM_SHA" != "$LAST_UPSTREAM_SHA" ]]; then
  UPSTREAM_CHANGED="true"
fi

echo "Decision inputs:"
echo "  Upstream changed: $UPSTREAM_CHANGED ($UPSTREAM_SHA vs $LAST_UPSTREAM_SHA)"
echo "  Has existing PR: $HAS_EXISTING_PR"
echo "  Has existing issue: $HAS_EXISTING_ISSUE"

if [[ "$HAS_EXISTING_PR" = "false" ]] && [[ "$UPSTREAM_CHANGED" = "true" ]]; then
  SHOULD_CREATE_PR="true"
  SHOULD_CREATE_ISSUE="true"
  SHOULD_UPDATE_BRANCH="false"
  OUT_PR_NUMBER=""
  OUT_ISSUE_NUMBER=""
  OUT_BRANCH_NAME=""
  SYNC_DECISION="create_new"
  echo "🆕 Decision: Create new PR and issue (upstream changed, no existing PR)"

elif [[ "$HAS_EXISTING_PR" = "true" ]] && [[ "$UPSTREAM_CHANGED" = "false" ]]; then
  SHOULD_CREATE_PR="false"
  SHOULD_CREATE_ISSUE="false"
  SHOULD_UPDATE_BRANCH="false"
  OUT_PR_NUMBER="$EXISTING_PR_NUMBER"
  OUT_ISSUE_NUMBER="$EXISTING_ISSUE_NUMBER"
  OUT_BRANCH_NAME="$EXISTING_PR_BRANCH"
  # add_reminder is kept for deployed workflows that still match on it.
  SYNC_DECISION="add_reminder"
  echo "✅ Decision: Existing PR remains current (upstream unchanged)"

elif [[ "$HAS_EXISTING_PR" = "true" ]] && [[ "$UPSTREAM_CHANGED" = "true" ]]; then
  SHOULD_CREATE_PR="false"
  SHOULD_CREATE_ISSUE="false"
  SHOULD_UPDATE_BRANCH="true"
  OUT_PR_NUMBER="$EXISTING_PR_NUMBER"
  OUT_ISSUE_NUMBER="$EXISTING_ISSUE_NUMBER"
  OUT_BRANCH_NAME="$EXISTING_PR_BRANCH"
  SYNC_DECISION="update_existing"
  echo "🔄 Decision: Update existing branch and PR (upstream changed, existing PR)"

else
  SHOULD_CREATE_PR="false"
  SHOULD_CREATE_ISSUE="false"
  SHOULD_UPDATE_BRANCH="false"
  OUT_PR_NUMBER=""
  OUT_ISSUE_NUMBER=""
  OUT_BRANCH_NAME=""
  SYNC_DECISION="no_action"
  echo "✅ Decision: No action needed (upstream unchanged, no existing PR)"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "should_create_pr=$SHOULD_CREATE_PR" >> "$GITHUB_OUTPUT"
  echo "should_create_issue=$SHOULD_CREATE_ISSUE" >> "$GITHUB_OUTPUT"
  echo "should_update_branch=$SHOULD_UPDATE_BRANCH" >> "$GITHUB_OUTPUT"
  echo "existing_pr_number=$OUT_PR_NUMBER" >> "$GITHUB_OUTPUT"
  echo "existing_issue_number=$OUT_ISSUE_NUMBER" >> "$GITHUB_OUTPUT"
  echo "existing_branch_name=$OUT_BRANCH_NAME" >> "$GITHUB_OUTPUT"
  echo "sync_decision=$SYNC_DECISION" >> "$GITHUB_OUTPUT"
fi

echo "should_create_pr=$SHOULD_CREATE_PR"
echo "should_create_issue=$SHOULD_CREATE_ISSUE"
echo "should_update_branch=$SHOULD_UPDATE_BRANCH"
echo "existing_pr_number=$OUT_PR_NUMBER"
echo "existing_issue_number=$OUT_ISSUE_NUMBER"
echo "existing_branch_name=$OUT_BRANCH_NAME"
echo "sync_decision=$SYNC_DECISION"