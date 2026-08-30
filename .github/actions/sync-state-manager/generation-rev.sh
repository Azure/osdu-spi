#!/usr/bin/env bash
#
# Generation Revision Script
#
# Prints the identity of every input, other than the upstream commit itself,
# that determines the generated tree. Durable no-op state is only trusted while
# this value still matches: a filter config or engine change makes a previously
# no-op upstream commit produce a different tree (ADR-024, ADR-038).
#
# Arguments:
#   $1 - Repository root (optional, defaults to the enclosing git work tree)
#
# Environment Variables:
#   SYNC_MODE - "mirror" for the customer tier (ADR-039), otherwise filter mode
#
# Usage:
#   ./generation-rev.sh

set -euo pipefail

MODE="${SYNC_MODE:-filter}"

if [[ "$MODE" == "mirror" ]]; then
  # Mirror generation copies the upstream tree verbatim. The engine and config
  # are never read, so the upstream commit is the only input.
  echo "mirror"
  exit 0
fi

if [[ $# -ge 1 && -n "$1" ]]; then
  REPO_ROOT="$1"
else
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
fi

# Every input to the no-change comparison other than the upstream commit:
# the config and engine decide what is kept, and generate-branch.sh decides how
# the tree is extracted, serialized, and compared.
REV="filter"
for input in \
  "$REPO_ROOT/.github/upstream-filter.yml" \
  "$REPO_ROOT/.github/actions/upstream-filter/upstream_filter.py" \
  "$REPO_ROOT/.github/actions/upstream-filter/generate-branch.sh"
do
  if [[ -f "$input" ]]; then
    REV="$REV-$(git hash-object "$input" | cut -c1-12)"
  else
    REV="$REV-absent"
  fi
done

echo "$REV"
