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
# Fixture harness for the upstream-owned-files action: a throwaway repository
# with main and fork_upstream, exercised through the same script the action runs.
#
# Usage:
#   ./run-tests.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$HERE/../../actions/upstream-owned-files/list.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note() { printf '\n== %s\n' "$*"; }
die()  { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()   { printf 'ok: %s\n' "$*"; }

output_value() {
  local file="$1" name="$2"
  grep "^${name}=" "$file" | head -1 | cut -d= -f2-
}
output_block() {
  local file="$1" name="$2"
  awk -v n="$name" '$0 == n"<<UPSTREAM_OWNED_EOF"{p=1; next} $0 == "UPSTREAM_OWNED_EOF"{p=0} p' "$file"
}

git_q() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# Bare origin with main (root pom, provider pom, filter config) and fork_upstream (root pom only).
ORIGIN="$TMP/origin.git"; SRC="$TMP/src"; WS="$TMP/ws"
git_q init -q --bare "$ORIGIN"
git_q init -q "$SRC"
mkdir -p "$SRC/provider/demo-azure" "$SRC/.github"
echo "root v1" > "$SRC/pom.xml"; echo "azure v1" > "$SRC/provider/demo-azure/pom.xml"; echo "service: demo" > "$SRC/.github/upstream-filter.yml"
git_q -C "$SRC" add -A && git_q -C "$SRC" commit -q -m "main"
git_q -C "$SRC" checkout -q --orphan fork_upstream && git_q -C "$SRC" rm -rqf . && echo "root v1" > "$SRC/pom.xml"
git_q -C "$SRC" add -A && git_q -C "$SRC" commit -q -m "upstream"
git_q -C "$SRC" checkout -q main
git_q -C "$SRC" remote add origin "$ORIGIN" && git_q -C "$SRC" push -q origin main fork_upstream
git_q clone -q "$ORIGIN" "$WS"
BASE=$(git -C "$WS" rev-parse main)

run_list() {
  local out="$1"; shift
  : > "$out"
  (cd "$WS" && env "$@" GITHUB_OUTPUT="$out" bash "$LIST")
}
branch_with() {
  local name="$1"; shift
  git_q -C "$WS" checkout -q -b "$name" main
  for f in "$@"; do mkdir -p "$(dirname "$WS/$f")"; echo "$name" > "$WS/$f"; done
  git_q -C "$WS" add -A && git_q -C "$WS" commit -q -m "$name"
  git -C "$WS" rev-parse HEAD
}

note "root pom edit is upstream-owned"
HEAD=$(branch_with edit-root pom.xml)
run_list "$TMP/o1" BASE_REF=main HEAD_REF=edit-root BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null
[ "$(output_value "$TMP/o1" checked)" = "true" ] || die "expected checked=true"
[ "$(output_block "$TMP/o1" files)" = "pom.xml" ] || die "expected pom.xml, got: $(output_block "$TMP/o1" files)"
ok "pom.xml listed"

note "azure pom edit is fork-owned"
HEAD=$(branch_with edit-azure provider/demo-azure/pom.xml)
run_list "$TMP/o2" BASE_REF=main HEAD_REF=edit-azure BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null
[ "$(output_value "$TMP/o2" checked)" = "true" ] || die "expected checked=true"
[ -z "$(output_value "$TMP/o2" files)" ] && ! grep -q 'files<<' "$TMP/o2" || die "expected no files"
ok "nothing listed"

note "mixed edit lists only the upstream-owned file"
HEAD=$(branch_with edit-both pom.xml provider/demo-azure/pom.xml)
run_list "$TMP/o3" BASE_REF=main HEAD_REF=edit-both BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null
[ "$(output_block "$TMP/o3" files)" = "pom.xml" ] || die "expected only pom.xml"
ok "only pom.xml listed"

note "deleting the filter config in the PR does not switch the check off"
git_q -C "$WS" checkout -q -b drop-filter main && git_q -C "$WS" rm -q .github/upstream-filter.yml && echo "x" > "$WS/pom.xml"
git_q -C "$WS" add -A && git_q -C "$WS" commit -q -m "drop" && HEAD=$(git -C "$WS" rev-parse HEAD)
run_list "$TMP/o4" BASE_REF=main HEAD_REF=drop-filter BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null
[ "$(output_value "$TMP/o4" checked)" = "true" ] || die "expected the base tree to decide"
ok "base tree decides"

note "exemptions"
HEAD=$(branch_with fork_integration pom.xml)
run_list "$TMP/o5" BASE_REF=main HEAD_REF=fork_integration BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null
[ "$(output_value "$TMP/o5" checked)" = "false" ] || die "same-repo fork_integration must be exempt"
run_list "$TMP/o6" BASE_REF=main HEAD_REF=fork_integration BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=false SYNC_MODE= >/dev/null
[ "$(output_value "$TMP/o6" checked)" = "true" ] || die "a fork-repo branch named fork_integration is not exempt"
run_list "$TMP/o7" BASE_REF=fork_integration HEAD_REF=x BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null
[ "$(output_value "$TMP/o7" checked)" = "false" ] || die "non-main base must be exempt"
run_list "$TMP/o8" BASE_REF=main HEAD_REF=x BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE=mirror >/dev/null
[ "$(output_value "$TMP/o8" checked)" = "false" ] || die "mirror mode must be exempt"
ok "same-repo automation heads, non-main base, mirror mode"

note "missing fork_upstream fails closed"
git -C "$WS" push -q origin --delete fork_upstream && git -C "$WS" update-ref -d refs/remotes/origin/fork_upstream
HEAD=$(git -C "$WS" rev-parse edit-root)
if run_list "$TMP/o9" BASE_REF=main HEAD_REF=edit-root BASE_SHA="$BASE" HEAD_SHA="$HEAD" SAME_REPO=true SYNC_MODE= >/dev/null 2>&1; then
  die "expected a failure without fork_upstream"
fi
ok "fails without the branch"

printf '\nAll upstream-owned-files tests passed\n'
