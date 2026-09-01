#!/usr/bin/env bash
#
# Materializes the seed source for the fork-owned Azure trees.
#
# For each of provider/<service>-azure and testing/<service>-test-azure, resolves
# the newest upstream commit that still contains the tree and extracts it into
# one scratch directory for the engine's --seed-source input. The two trees are
# resolved independently: upstream can delete them in different commits.
#
# A path deleted through a merge is invisible to simplified history: rev-list
# without --full-history returns nothing, and with it the newest result is the
# deletion commit itself, whose first parent is not necessarily the side that
# carried the tree. The walk checks the commit, then each parent, and takes the
# first that resolves the path.
#
# Usage: seed-source.sh <upstream_ref> <service> <out_file>
#
# Writes key=value lines to <out_file>:
#   seed_dir=<directory holding both extracted trees>
#   provider_sha=<commit the provider tree was taken from>
#   testing_sha=<commit the testing tree was taken from>
#
# The calling checkout's working tree and index are never touched.

set -euo pipefail

REF="$1"
SERVICE="$2"
OUT="$3"

if [ -n "${RUNNER_TEMP:-}" ]; then
  WORKDIR="$RUNNER_TEMP"
else
  WORKDIR="$(mktemp -d)"
fi
SEED_DIR="$WORKDIR/seed-source"
SCRATCH="$WORKDIR/seed-source.index"
rm -rf "$SEED_DIR" "$SCRATCH"
mkdir -p "$SEED_DIR"

resolve_path_sha() {
  local path="$1"
  local sha
  sha=$(git rev-parse -q --verify "$REF^{commit}")
  if git rev-parse -q --verify "$sha:$path" >/dev/null; then
    echo "$sha"
    return 0
  fi
  local touching
  touching=$(git rev-list -1 --full-history "$sha" -- "$path")
  if [ -z "$touching" ]; then
    echo "seed-source: $path never existed in the history of $REF" >&2
    return 1
  fi
  local candidate
  for candidate in "$touching" $(git rev-parse "$touching^@"); do
    if git rev-parse -q --verify "$candidate:$path" >/dev/null; then
      echo "$candidate"
      return 0
    fi
  done
  echo "seed-source: $path resolves in neither $touching nor its parents" >&2
  return 1
}

PROVIDER_PATH="provider/${SERVICE}-azure"
TESTING_PATH="testing/${SERVICE}-test-azure"

PROVIDER_SHA=$(resolve_path_sha "$PROVIDER_PATH")
TESTING_SHA=$(resolve_path_sha "$TESTING_PATH")

# git archive would honor export-ignore/export-subst attributes from the
# upstream tree; read-tree + checkout-index materializes every tracked file
# byte for byte, same as generate-branch.sh.
GIT_INDEX_FILE="$SCRATCH" git read-tree --empty
GIT_INDEX_FILE="$SCRATCH" git read-tree --prefix="$PROVIDER_PATH/" "$PROVIDER_SHA:$PROVIDER_PATH"
GIT_INDEX_FILE="$SCRATCH" git read-tree --prefix="$TESTING_PATH/" "$TESTING_SHA:$TESTING_PATH"
GIT_INDEX_FILE="$SCRATCH" git checkout-index -a -f --prefix="$SEED_DIR/"

{
  echo "seed_dir=$SEED_DIR"
  echo "provider_sha=$PROVIDER_SHA"
  echo "testing_sha=$TESTING_SHA"
} > "$OUT"
