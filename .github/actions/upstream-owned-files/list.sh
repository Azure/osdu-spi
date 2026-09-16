#!/usr/bin/env bash
#
# Lists the files a pull request changes that also exist on origin/fork_upstream.
# That branch is exactly what the upstream filter emits, so it is the ownership
# split of ADR-038 by construction; nothing here names a path.
#
# Environment: BASE_REF HEAD_REF BASE_SHA HEAD_SHA SAME_REPO SYNC_MODE GITHUB_OUTPUT
# Outputs: checked (true|false), reason (exemption text), files (newline list)
# Exit 1 only when the repository state cannot be read; an exemption exits 0.

set -euo pipefail

skip() {
  echo "Skipping ownership check: $1"
  { echo "checked=false"; echo "reason=$1"; echo "files="; } >> "$GITHUB_OUTPUT"
  exit 0
}

# Only pull requests to main carry the split. Branches that move upstream code by
# design are exempt, but only from this repository: a fork can name a branch anything.
[ "$BASE_REF" = "main" ] || skip "base branch is $BASE_REF, not main"
case "$HEAD_REF" in
  fork_integration|release/upstream-*)
    if [ "$SAME_REPO" = "true" ]; then skip "$HEAD_REF moves upstream code by design"; fi
    ;;
esac
[ "${SYNC_MODE:-}" != "mirror" ] || skip "mirror mode has no ownership split (ADR-039)"

# Tested on the base tree: a pull request that deletes the filter config must not switch the check off.
git cat-file -e "$BASE_SHA:.github/upstream-filter.yml" 2>/dev/null \
  || skip "no .github/upstream-filter.yml on $BASE_REF"

if ! git fetch --quiet origin fork_upstream; then
  echo "::error::Unable to fetch origin/fork_upstream to enforce the ownership split"
  exit 1
fi
if ! CHANGED_FILES=$(git diff --name-only "$BASE_SHA...$HEAD_SHA"); then
  echo "::error::Unable to diff $BASE_SHA...$HEAD_SHA to enforce the ownership split"
  exit 1
fi
if ! UPSTREAM_OWNED=$(git ls-tree -r --name-only origin/fork_upstream) || [ -z "$UPSTREAM_OWNED" ]; then
  echo "::error::Unable to list the origin/fork_upstream tree to enforce the ownership split"
  exit 1
fi

TOUCHED=$(comm -12 <(printf '%s\n' "$CHANGED_FILES" | sort) <(printf '%s\n' "$UPSTREAM_OWNED" | sort))
if [ -z "$TOUCHED" ]; then
  echo "No upstream-owned files touched"
else
  printf 'Upstream-owned files changed:\n%s\n' "$TOUCHED"
fi
{
  echo "checked=true"
  echo "reason="
  if [ -z "$TOUCHED" ]; then
    echo "files="
  else
    echo "files<<UPSTREAM_OWNED_EOF"
    printf '%s\n' "$TOUCHED"
    echo "UPSTREAM_OWNED_EOF"
  fi
} >> "$GITHUB_OUTPUT"
