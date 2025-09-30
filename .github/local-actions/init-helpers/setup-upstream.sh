#!/usr/bin/env bash
#
# Setup Upstream Repository Script
#
# Adds upstream remote and detects the default branch (main, master, or other).
#
# Arguments:
#   $1 - Upstream repository (URL or owner/repo format)
#   $2 - Issue number for status comments (optional)
#
# Environment Variables:
#   GITHUB_TOKEN - Required for gh CLI if issue_number provided
#   DEFAULT_BRANCH - Output: Sets this environment variable to detected branch
#   REPO_URL - Output: Sets this environment variable to full URL
#
# Usage:
#   ./setup-upstream.sh "https://github.com/azure/osdu-infrastructure.git" "123"
#   ./setup-upstream.sh "azure/osdu-infrastructure"

set -euo pipefail

# Validate arguments
if [[ $# -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <upstream_repo> [issue_number]"
  exit 1
fi

UPSTREAM_REPO="$1"
ISSUE_NUMBER="${2:-}"

echo "Setting up upstream repository: $UPSTREAM_REPO"

# Convert to URL format
if [[ "$UPSTREAM_REPO" == http* ]]; then
  REPO_URL="$UPSTREAM_REPO"
  if [[ ! "$REPO_URL" == *.git ]]; then
    REPO_URL="${REPO_URL}.git"
  fi
else
  REPO_URL="https://github.com/$UPSTREAM_REPO.git"
fi

echo "Repository URL: $REPO_URL"

# Store repo URL for use in subsequent steps
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "REPO_URL=$REPO_URL" >> "$GITHUB_ENV"
fi

# Add upstream remote
git remote add upstream "$REPO_URL"
git fetch upstream --prune --tags

# Get all branches from upstream
BRANCHES=$(git branch -r | grep upstream | sed 's/upstream\///' | grep -v HEAD | tr '\n' ' ' || echo "")
echo "Available branches: $BRANCHES"

# Determine default branch
if git rev-parse --verify upstream/main >/dev/null 2>&1; then
  DEFAULT_BRANCH="main"
elif git rev-parse --verify upstream/master >/dev/null 2>&1; then
  DEFAULT_BRANCH="master"
else
  # Try to detect default branch from HEAD
  # Using @ as sed delimiter to avoid escaping slashes in path
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/upstream/HEAD 2>/dev/null | sed 's@^refs/remotes/upstream/@@' || echo "")

  if [[ -z "$DEFAULT_BRANCH" ]]; then
    # Last resort: check common branch names
    for branch in develop development prod production release stable; do
      if git rev-parse --verify "upstream/$branch" >/dev/null 2>&1; then
        DEFAULT_BRANCH="$branch"
        break
      fi
    done
  fi

  if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo "❌ Error: Could not determine default branch in upstream repository"
    echo "Available branches found: $BRANCHES"

    if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
      cat <<EOF | gh issue comment "$ISSUE_NUMBER" --body-file -
❌ **Error:** Could not determine default branch in upstream repository

Available branches found: $BRANCHES

Please ensure the upstream repository has at least one branch.
EOF
    fi

    exit 1
  fi
fi

echo "✅ Detected default branch: $DEFAULT_BRANCH"

# Store default branch for use in subsequent steps
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "DEFAULT_BRANCH=$DEFAULT_BRANCH" >> "$GITHUB_ENV"
fi

# Post success comment if issue number provided
if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "✅ Using default branch: $DEFAULT_BRANCH" | gh issue comment "$ISSUE_NUMBER" --body-file -
fi

echo "Upstream repository setup complete"