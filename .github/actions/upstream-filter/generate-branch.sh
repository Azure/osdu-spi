#!/usr/bin/env bash
#
# Generate the filtered fork_upstream commit without leaving the current checkout.
#
# Extracts the upstream tree to a scratch directory, runs the filter engine over
# it, serializes the result through a scratch index, and writes a merge-shaped
# commit: first parent the current fork_upstream tip, second parent the upstream
# tip, so upstream history, blame, and attribution are preserved. The calling
# checkout's working tree and index are never touched.
#
# Usage:
#   generate-branch.sh <base_sha> <upstream_sha> <config_path> <out_file>
#
# Writes key=value lines to <out_file>:
#   filter_rev=<engine version + config hash>
#   report=<path to the engine's JSON report>
#   tree=<generated tree sha>
#   has_changes=true|false
#   commit=<generated commit sha>          (only when has_changes=true)
#
# Exit codes follow the engine: 0 success, 1 operational error, 2 halt.
#
# Outside RUNNER_TEMP (e.g. local runs), the scratch dir is removed on success
# and kept on failure so the halt report stays readable.

set -euo pipefail

BASE_SHA="$1"
UPSTREAM_SHA="$2"
CONFIG="$3"
OUT="$4"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${RUNNER_TEMP:-}" ]; then
  WORKDIR="$RUNNER_TEMP"
else
  WORKDIR="$(mktemp -d)"
  cleanup_workdir() {
    local exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      rm -rf "$WORKDIR"
    fi
  }
  trap cleanup_workdir EXIT
fi
GEN="$WORKDIR/generated-upstream"
SCRATCH="$WORKDIR/generated-upstream.index"
REPORT="$WORKDIR/upstream-filter-report.json"
rm -rf "$GEN" "$SCRATCH"
mkdir -p "$GEN"

# git archive would honor export-ignore/export-subst attributes from the
# upstream tree; read-tree + checkout-index materializes every tracked file
# byte for byte.
GIT_INDEX_FILE="$SCRATCH" git read-tree "$UPSTREAM_SHA"
GIT_INDEX_FILE="$SCRATCH" git checkout-index -a -f --prefix="$GEN/"

python3 "$HERE/upstream_filter.py" \
  --mode generate --config "$CONFIG" --checkout "$GEN" --report "$REPORT"
FILTER_REV=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['filter_rev'])" "$REPORT")

GITDIR="$(git rev-parse --absolute-git-dir)"
# --force: the extraction contains upstream's own .gitignore, and the runner may
# carry a core.excludesfile; every extracted file was tracked upstream and must
# reach the tree regardless of what any ignore rule says.
(cd "$GEN" && GIT_INDEX_FILE="$SCRATCH" git --git-dir="$GITDIR" --work-tree="$GEN" add -A --force)
TREE=$(GIT_INDEX_FILE="$SCRATCH" git write-tree)

{
  echo "filter_rev=$FILTER_REV"
  echo "report=$REPORT"
  echo "tree=$TREE"
} > "$OUT"

if [ "$TREE" = "$(git rev-parse "${BASE_SHA}^{tree}")" ]; then
  echo "has_changes=false" >> "$OUT"
  exit 0
fi

COMMIT=$(git commit-tree "$TREE" -p "$BASE_SHA" -p "$UPSTREAM_SHA" \
  -m "chore: generate filtered upstream tree" \
  -m "Upstream-Sha: $UPSTREAM_SHA
Filter-Rev: $FILTER_REV")

{
  echo "has_changes=true"
  echo "commit=$COMMIT"
} >> "$OUT"
