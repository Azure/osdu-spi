#!/usr/bin/env bash
#
# Fixture harness for the upstream filter engine.
#
# Drives every halt code plus the idempotence and determinism gates against the
# synthetic "demo" service fixture. Fails fast: the first broken assertion stops
# the run with a non-zero exit.
#
# Usage:
#   ./run-tests.sh

# shellcheck disable=SC2154  # has_changes/commit/tree/filter_rev are sourced from generate-branch.sh output
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/../../actions/upstream-filter/upstream_filter.py"
FIXTURE="$HERE/fixtures/upstream"
CONFIG="$HERE/config/demo.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note()  { printf '\n== %s\n' "$*"; }
die()   { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()    { printf 'ok: %s\n' "$*"; }

engine() { python3 "$ENGINE" "$@"; }

halt_code() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['halts'][0]['code'])" "$1"
}

report_field() {
  python3 -c "import json,sys; print(eval(sys.argv[2], {'r': json.load(open(sys.argv[1]))}))" "$1" "$2"
}

replace_in_file() {
  python3 -c "
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
assert old in text, f'{old!r} not found in {path}'
open(path, 'w').write(text.replace(old, new))
" "$1" "$2" "$3"
}

expect_halt() {
  local desc="$1" code="$2" report="$3"
  shift 3
  local rc=0
  "$@" > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || die "$desc: expected exit 2, got $rc"
  [ "$(halt_code "$report")" = "$code" ] || die "$desc: expected halt $code, got $(halt_code "$report")"
  ok "$desc"
}

fresh_copy() {
  rm -rf "$1"
  cp -R "$FIXTURE" "$1"
}

note "generate: happy path"
GEN1="$TMP/gen1"
fresh_copy "$GEN1"
engine --mode generate --config "$CONFIG" --checkout "$GEN1" --report "$TMP/gen1.json" > /dev/null

for absent in provider devops demo-core-plus .gitlab-ci.yml testing/demo-test-azure testing/demo-test-aws; do
  [ ! -e "$GEN1/$absent" ] || die "generate left $absent behind"
done
for present in pom.xml demo-core/pom.xml demo-core/src/Main.java demo-acceptance-test/pom.xml \
               testing/pom.xml testing/demo-test-core/pom.xml .fossa.yml .mvn/community-maven.settings.xml \
               .mvn/wrapper/maven-wrapper.jar NOTICE docs/index.md .gitignore; do
  [ -e "$GEN1/$present" ] || die "generate lost $present"
done
grep -q '<id>azure</id>' "$GEN1/pom.xml" || die "azure profile not injected into root pom"
grep -q '<module>provider/demo-azure</module>' "$GEN1/pom.xml" || die "azure profile module missing from root pom"
grep -q '<id>core</id>' "$GEN1/pom.xml" || die "core profile lost"
grep -q '<id>Default</id>' "$GEN1/pom.xml" || die "Default profile lost"
! grep -q '<id>aws</id>' "$GEN1/pom.xml" || die "aws profile survives"
! grep -q 'demo-core-plus' "$GEN1/pom.xml" || die "demo-core-plus module line survives"
grep -q '<module>demo-test-azure</module>' "$GEN1/testing/pom.xml" || die "azure test module not injected"
! grep -q 'demo-test-aws' "$GEN1/testing/pom.xml" || die "aws test module line survives"
grep -q 'demo-core' "$GEN1/.fossa.yml" || die "kept fossa module lost"
for gone in demo-core-plus demo-azure demo-aws; do
  ! grep -q "name: $gone" "$GEN1/.fossa.yml" || die "stripped fossa module $gone survives"
done
[ "$(report_field "$TMP/gen1.json" "r['ok']")" = "True" ] || die "report not ok"
KEPT_REPORTED="$(report_field "$TMP/gen1.json" "r['counts']['kept_files']")"
KEPT_ACTUAL="$(find "$GEN1" -type f | wc -l | tr -d ' ')"
[ "$KEPT_REPORTED" = "$KEPT_ACTUAL" ] || die "kept_files $KEPT_REPORTED != actual $KEPT_ACTUAL"
FILTER_REV="$(report_field "$TMP/gen1.json" "r['filter_rev']")"
[ -n "$FILTER_REV" ] || die "filter_rev missing from report"
ok "generated tree has the expected shape ($KEPT_ACTUAL files kept, filter_rev $FILTER_REV)"

note "generate: determinism (repeated runs are byte-identical)"
GEN2="$TMP/gen2"
fresh_copy "$GEN2"
engine --mode generate --config "$CONFIG" --checkout "$GEN2" --report "$TMP/gen2.json" > /dev/null
diff -r "$GEN1" "$GEN2" > /dev/null || die "two generate runs differ"
diff "$TMP/gen1.json" "$TMP/gen2.json" > /dev/null || die "two generate reports differ"
ok "byte-identical trees and reports"

note "generate: idempotence (a second pass over the output is a no-op)"
GEN3="$TMP/gen3"
rm -rf "$GEN3"
cp -R "$GEN1" "$GEN3"
engine --mode generate --config "$CONFIG" --checkout "$GEN3" > /dev/null
diff -r "$GEN1" "$GEN3" > /dev/null || die "generate applied to its own output changed the tree"
ok "converged"

note "verify: passes on a generated tree without mutating it"
engine --mode verify --config "$CONFIG" --checkout "$GEN1" > /dev/null
diff -r "$GEN1" "$GEN2" > /dev/null || die "verify mutated the tree"
ok "clean verify"

note "generate: commented-out legacy profiles block does not capture the injection"
H11="$TMP/h11"
fresh_copy "$H11"
replace_in_file "$H11/pom.xml" "</profiles>" "</profiles>
    <!--
    <profiles>
        <profile>
            <id>legacy</id>
        </profile>
    </profiles>
    -->"
engine --mode generate --config "$CONFIG" --checkout "$H11" > /dev/null
python3 -c "
import sys, xml.etree.ElementTree as ET
ids = [e.text for e in ET.parse(sys.argv[1]).getroot().iter() if e.tag.rsplit('}', 1)[-1] == 'id']
assert 'azure' in ids, f'azure profile is not live XML: {ids}'
assert 'legacy' not in ids, 'commented legacy profile became live'
" "$H11/pom.xml"
ok "azure profile is live XML; commented block untouched"

note "generate: fossa modules at the key's own column still filter"
H12="$TMP/h12"
fresh_copy "$H12"
cat > "$H12/.fossa.yml" <<'EOF'
version: 1

analyze:
  modules:
  - name: demo-core
    type: mvn
    target: demo-core/pom.xml
    path: .
  - name: demo-azure
    type: mvn
    target: provider/demo-azure/pom.xml
    path: .
EOF
engine --mode generate --config "$CONFIG" --checkout "$H12" > /dev/null
grep -q "name: demo-core" "$H12/.fossa.yml" || die "kept same-column fossa module lost"
! grep -q "name: demo-azure" "$H12/.fossa.yml" || die "stripped same-column fossa module survives"
ok "same-column list style filtered"

note "generate: module line with a trailing comment still prunes"
H13="$TMP/h13"
fresh_copy "$H13"
replace_in_file "$H13/pom.xml" "<module>demo-core-plus</module>" "<module>demo-core-plus</module> <!-- community only -->"
engine --mode generate --config "$CONFIG" --checkout "$H13" > /dev/null
! grep -q "demo-core-plus" "$H13/pom.xml" || die "trailing-comment module line survives"
ok "pruned"

note "generate: fully commented module line neither prunes nor halts"
H14="$TMP/h14"
fresh_copy "$H14"
replace_in_file "$H14/pom.xml" "<module>demo-core</module>" "<module>demo-core</module>
                <!-- <module>demo-retired</module> -->"
engine --mode generate --config "$CONFIG" --checkout "$H14" > /dev/null
grep -q "demo-retired" "$H14/pom.xml" || die "commented module line was removed"
ok "left in place"

note "halt: config missing"
expect_halt "missing config fails closed" CONFIG_MISSING "$TMP/h0.json" \
  engine --mode generate --config "$TMP/does-not-exist.yml" --checkout "$GEN1" --report "$TMP/h0.json"

note "halt: inject_root_pom_azure_profile set without an inject verdict"
H0B="$TMP/h0b"
fresh_copy "$H0B"
CONFIG_NO_INJECT="$TMP/demo-no-inject.yml"
cp "$CONFIG" "$CONFIG_NO_INJECT"
replace_in_file "$CONFIG_NO_INJECT" "azure: inject" "azure: strip"
expect_halt "non-empty inject block without an inject verdict halts" CONFIG_INVALID "$TMP/h0b.json" \
  engine --mode generate --config "$CONFIG_NO_INJECT" --checkout "$H0B" --report "$TMP/h0b.json"

note "halt: unknown top-level entry"
H1="$TMP/h1"
fresh_copy "$H1"
mkdir "$H1/new-shared-module"
touch "$H1/new-shared-module/pom.xml"
expect_halt "new top-level module halts" UNKNOWN_TOP_LEVEL "$TMP/h1.json" \
  engine --mode generate --config "$CONFIG" --checkout "$H1" --report "$TMP/h1.json"

note "halt: unknown testing entry"
H2="$TMP/h2"
fresh_copy "$H2"
mkdir "$H2/testing/demo-test-gcp"
touch "$H2/testing/demo-test-gcp/pom.xml"
expect_halt "new testing module halts" UNKNOWN_TESTING_ENTRY "$TMP/h2.json" \
  engine --mode generate --config "$CONFIG" --checkout "$H2" --report "$TMP/h2.json"

note "halt: unknown root pom profile"
H3="$TMP/h3"
fresh_copy "$H3"
replace_in_file "$H3/pom.xml" "    </profiles>" "        <profile>
            <id>ibm</id>
        </profile>
    </profiles>"
expect_halt "new profile halts" UNKNOWN_PROFILE "$TMP/h3.json" \
  engine --mode generate --config "$CONFIG" --checkout "$H3" --report "$TMP/h3.json"

note "halt: unknown fossa module"
H4="$TMP/h4"
fresh_copy "$H4"
cat >> "$H4/.fossa.yml" <<'EOF'
    - name: demo-gcp
      type: mvn
      target: provider/demo-gcp/pom.xml
      path: .
EOF
expect_halt "new fossa module halts" UNKNOWN_FOSSA_MODULE "$TMP/h4.json" \
  engine --mode generate --config "$CONFIG" --checkout "$H4" --report "$TMP/h4.json"

note "halt: expected_kept path missing (upstream rename fails loud)"
H5="$TMP/h5"
fresh_copy "$H5"
rm -rf "$H5/testing/demo-test-core"
expect_halt "renamed kept module halts" EXPECTED_KEPT_MISSING "$TMP/h5.json" \
  engine --mode generate --config "$CONFIG" --checkout "$H5" --report "$TMP/h5.json"

note "halt: verify catches contamination on a generated tree"
H6="$TMP/h6"
rm -rf "$H6"
cp -R "$GEN1" "$H6"
mkdir -p "$H6/provider/demo-aws"
expect_halt "reintroduced provider tree halts verify" STRIPPED_PATH_SURVIVES "$TMP/h6.json" \
  engine --mode verify --config "$CONFIG" --checkout "$H6" --report "$TMP/h6.json"

note "seed: copies the fork-owned trees from a source checkout"
SEEDED="$TMP/seeded"
rm -rf "$SEEDED"
cp -R "$GEN1" "$SEEDED"
engine --mode seed --config "$CONFIG" --checkout "$SEEDED" --seed-source "$FIXTURE" --report "$TMP/seed.json" > /dev/null
[ -f "$SEEDED/provider/demo-azure/pom.xml" ] || die "seed missed provider tree"
[ -f "$SEEDED/testing/demo-test-azure/pom.xml" ] || die "seed missed testing tree"
[ "$(report_field "$TMP/seed.json" "len(r['seeded'])")" = "2" ] || die "seed report wrong"
ok "both trees seeded"

note "halt: seed refuses an existing target"
expect_halt "second seed halts" SEED_TARGET_EXISTS "$TMP/h7.json" \
  engine --mode seed --config "$CONFIG" --checkout "$SEEDED" --seed-source "$FIXTURE" --report "$TMP/h7.json"

note "halt: seed refuses a source without the trees"
H8="$TMP/h8"
rm -rf "$H8"
cp -R "$GEN1" "$H8"
expect_halt "generated tree is not a seed source" SEED_SOURCE_MISSING "$TMP/h8.json" \
  engine --mode seed --config "$CONFIG" --checkout "$H8" --seed-source "$GEN1" --report "$TMP/h8.json"

note "stamp: rewrites every pre-bump version after a simulated merge"
PM="$TMP/post-merge"
rm -rf "$PM"
cp -R "$GEN1" "$PM"
engine --mode seed --config "$CONFIG" --checkout "$PM" --seed-source "$FIXTURE" > /dev/null
for pom in pom.xml testing/pom.xml testing/demo-test-core/pom.xml; do
  replace_in_file "$PM/$pom" "0.31.0-SNAPSHOT" "0.32.0-SNAPSHOT"
done
engine --mode stamp --config "$CONFIG" --checkout "$PM" --report "$TMP/stamp.json" > /dev/null
for pom in provider/demo-azure/pom.xml testing/demo-test-azure/pom.xml; do
  ! grep -q "0.31.0-SNAPSHOT" "$PM/$pom" || die "pre-bump version survives in $pom"
  grep -q "0.32.0-SNAPSHOT" "$PM/$pom" || die "bumped version missing from $pom"
done
[ "$(report_field "$TMP/stamp.json" "len(r['stamp']['rewrites']) > 0")" = "True" ] || die "stamp reported no rewrites"
ok "no pre-bump version survives"

note "stamp: a second pass is a no-op"
engine --mode stamp --config "$CONFIG" --checkout "$PM" --report "$TMP/stamp2.json" > /dev/null
[ "$(report_field "$TMP/stamp2.json" "len(r['stamp']['rewrites'])")" = "0" ] || die "no-op stamp rewrote something"
ok "converged"

note "stamp: provider and testing trees follow their own reference versions"
PMD="$TMP/post-merge-diverged"
rm -rf "$PMD"
cp -R "$GEN1" "$PMD"
engine --mode seed --config "$CONFIG" --checkout "$PMD" --seed-source "$FIXTURE" > /dev/null
replace_in_file "$PMD/pom.xml" "0.31.0-SNAPSHOT" "0.32.0-SNAPSHOT"
replace_in_file "$PMD/testing/pom.xml" "0.31.0-SNAPSHOT" "0.40.0-SNAPSHOT"
replace_in_file "$PMD/testing/demo-test-core/pom.xml" "0.31.0-SNAPSHOT" "0.40.0-SNAPSHOT"
engine --mode stamp --config "$CONFIG" --checkout "$PMD" > /dev/null
grep -q "0.32.0-SNAPSHOT" "$PMD/provider/demo-azure/pom.xml" || die "provider pom missed the root version"
grep -q "0.40.0-SNAPSHOT" "$PMD/testing/demo-test-azure/pom.xml" || die "testing pom missed the testing version"
! grep -q "0.31.0-SNAPSHOT" "$PMD/provider/demo-azure/pom.xml" || die "pre-bump survives in the provider pom"
! grep -q "0.31.0-SNAPSHOT" "$PMD/testing/demo-test-azure/pom.xml" || die "pre-bump survives in the testing pom"
ok "each tree stamped to its own reference"

note "halt: stamp without fork-owned poms"
expect_halt "stamp needs the merged fork trees" STAMP_NO_FORK_POMS "$TMP/h9.json" \
  engine --mode stamp --config "$CONFIG" --checkout "$GEN1" --report "$TMP/h9.json"

note "halt: stamp without a reference pom"
H10="$TMP/h10"
rm -rf "$H10"
cp -R "$PM" "$H10"
rm "$H10/testing/demo-test-core/pom.xml"
expect_halt "missing reference pom halts" STAMP_REF_MISSING "$TMP/h10.json" \
  engine --mode stamp --config "$CONFIG" --checkout "$H10" --report "$TMP/h10.json"

note "plumbing: generate-branch.sh writes a merge-shaped filtered commit"
PLUMB="$TMP/plumb"
rm -rf "$PLUMB"
git init -q "$PLUMB"
git -C "$PLUMB" config user.name harness
git -C "$PLUMB" config user.email harness@local
git -C "$PLUMB" commit -qm "previous fork_upstream tip" --allow-empty
BASE_SHA=$(git -C "$PLUMB" rev-parse HEAD)
cp -R "$FIXTURE/." "$PLUMB/"
git -C "$PLUMB" add -A -f
git -C "$PLUMB" commit -qm "upstream tip"
UP_SHA=$(git -C "$PLUMB" rev-parse HEAD)
GEN_OUT="$TMP/generate.env"
(cd "$PLUMB" && bash "$(dirname "$ENGINE")/generate-branch.sh" "$BASE_SHA" "$UP_SHA" "$CONFIG" "$GEN_OUT")
# shellcheck disable=SC1090
. "$GEN_OUT"
[ "${has_changes:-}" = "true" ] || die "plumbing reported no changes"
PARENTS=$(git -C "$PLUMB" rev-list --parents -n 1 "$commit" | wc -w | tr -d ' ')
[ "$PARENTS" = "3" ] || die "generated commit is not merge-shaped"
git -C "$PLUMB" cat-file -p "$commit" | grep -q "Upstream-Sha: $UP_SHA" || die "Upstream-Sha trailer missing"
git -C "$PLUMB" cat-file -p "$commit" | grep -q "Filter-Rev: $filter_rev" || die "Filter-Rev trailer missing"
TREE_FILES=$(git -C "$PLUMB" ls-tree -r --name-only "$commit" | wc -l | tr -d ' ')
[ "$TREE_FILES" = "$KEPT_ACTUAL" ] || die "commit tree has $TREE_FILES files, expected $KEPT_ACTUAL"
git -C "$PLUMB" ls-tree -r --name-only "$commit" | grep -q "maven-wrapper.jar" || die "ignored-but-tracked upstream file missing from the generated tree"
if [ -n "$(git -C "$PLUMB" status --porcelain)" ]; then
  die "plumbing dirtied the calling checkout"
fi
TREE1="$tree"
GEN_OUT2="$TMP/generate2.env"
(cd "$PLUMB" && bash "$(dirname "$ENGINE")/generate-branch.sh" "$BASE_SHA" "$UP_SHA" "$CONFIG" "$GEN_OUT2")
# shellcheck disable=SC1090
. "$GEN_OUT2"
[ "$tree" = "$TREE1" ] || die "two plumbing runs produced different trees"
ok "merge-shaped commit with trailers, clean checkout, deterministic tree"

printf '\nAll upstream-filter harness checks passed.\n'
