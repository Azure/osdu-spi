#!/usr/bin/env bash
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Materializes the seed source for the fork-owned Azure trees.
#
# For each fork-owned tree (the engine's paths mode lists them), resolves the
# newest upstream commit that still contains the tree and extracts it into one
# scratch directory for the engine's --seed-source input. The trees are resolved
# independently: upstream can delete them in different commits.
#
# A path deleted through a merge is invisible to simplified history: rev-list
# without --full-history returns nothing, and with it the newest result is the
# deletion commit itself, whose first parent is not necessarily the side that
# carried the tree. The walk checks the commit, then each parent, and takes the
# first that resolves the path.
#
# Usage: seed-source.sh <upstream_ref> <out_file> <tree>...
#
# Writes key=value lines to <out_file>:
#   seed_dir=<directory holding every extracted tree>
#   trailers=<file of "Seeded-From: <tree> <commit>" lines, one per tree>
#
# The calling checkout's working tree and index are never touched.

set -euo pipefail

REF="$1"
OUT="$2"
shift 2
if [ "$#" -eq 0 ]; then
  echo "seed-source: no trees to seed" >&2
  exit 1
fi

if [ -n "${RUNNER_TEMP:-}" ]; then
  WORKDIR="$RUNNER_TEMP"
else
  WORKDIR="$(mktemp -d)"
fi
SEED_DIR="$WORKDIR/seed-source"
SCRATCH="$WORKDIR/seed-source.index"
TRAILERS="$WORKDIR/seed-source.trailers"
rm -rf "$SEED_DIR" "$SCRATCH" "$TRAILERS"
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

# git archive would honor export-ignore/export-subst attributes from the
# upstream tree; read-tree + checkout-index materializes every tracked file
# byte for byte, same as generate-branch.sh.
GIT_INDEX_FILE="$SCRATCH" git read-tree --empty
: > "$TRAILERS"
for tree in "$@"; do
  sha=$(resolve_path_sha "$tree")
  GIT_INDEX_FILE="$SCRATCH" git read-tree --prefix="$tree/" "$sha:$tree"
  echo "Seeded-From: $tree $sha" >> "$TRAILERS"
done
GIT_INDEX_FILE="$SCRATCH" git checkout-index -a -f --prefix="$SEED_DIR/"

{
  echo "seed_dir=$SEED_DIR"
  echo "trailers=$TRAILERS"
} > "$OUT"
