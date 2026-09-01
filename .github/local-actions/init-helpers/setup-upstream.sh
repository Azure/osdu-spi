#!/usr/bin/env bash
#
# Adds the upstream remote and detects its default branch.
#
# Arguments:
#   $1 - Upstream repository (URL or owner/repo)
#   $2 - Issue number for status comments (optional)
#
# Environment:
#   GITHUB_TOKEN - issue comments when an issue number is given
#   DEFAULT_BRANCH - output: written to GITHUB_ENV
#   REPO_URL - output: written to GITHUB_ENV as the full clone URL

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Error: Missing required argument"
  echo "Usage: $0 <upstream_repo> [issue_number]"
  exit 1
fi

UPSTREAM_REPO="$1"
ISSUE_NUMBER="${2:-}"

echo "Setting up upstream repository: $UPSTREAM_REPO"

if [[ "$UPSTREAM_REPO" == http* ]]; then
  REPO_URL="$UPSTREAM_REPO"
  if [[ ! "$REPO_URL" == *.git ]]; then
    REPO_URL="${REPO_URL}.git"
  fi
else
  REPO_URL="https://github.com/$UPSTREAM_REPO.git"
fi

echo "Repository URL: $REPO_URL"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "REPO_URL=$REPO_URL" >> "$GITHUB_ENV"
fi

git remote add upstream "$REPO_URL"
git fetch upstream --prune --tags

BRANCHES=$(git branch -r | grep upstream | sed 's/upstream\///' | grep -v HEAD | tr '\n' ' ' || echo "")
echo "Available branches: $BRANCHES"

if git rev-parse --verify upstream/main >/dev/null 2>&1; then
  DEFAULT_BRANCH="main"
elif git rev-parse --verify upstream/master >/dev/null 2>&1; then
  DEFAULT_BRANCH="master"
else
  # @ delimiter: the ref contains slashes.
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

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "DEFAULT_BRANCH=$DEFAULT_BRANCH" >> "$GITHUB_ENV"
fi

if [[ -n "$ISSUE_NUMBER" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "✅ Using default branch: $DEFAULT_BRANCH" | gh issue comment "$ISSUE_NUMBER" --body-file -
fi

echo "Upstream repository setup complete"