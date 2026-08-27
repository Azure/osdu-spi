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

note "generate: inline comments in the config are ignored"
H15="$TMP/h15"
fresh_copy "$H15"
CONFIG_COMMENTS="$TMP/demo-comments.yml"
cp "$CONFIG" "$CONFIG_COMMENTS"
replace_in_file "$CONFIG_COMMENTS" "top_level:" "top_level:  # every top-level entry"
replace_in_file "$CONFIG_COMMENTS" "  pom.xml: keep" "  pom.xml: keep  # root reactor"
replace_in_file "$CONFIG_COMMENTS" "  - provider" "  - provider  # non-azure providers"
engine --mode generate --config "$CONFIG_COMMENTS" --checkout "$H15" > /dev/null
diff -r "$GEN1" "$H15" > /dev/null || die "inline comments changed the generated tree"
ok "inline comments ignored"

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

note "halt: fork testing verdict without a module injection"
H18="$TMP/h18"
fresh_copy "$H18"
CONFIG_NO_TESTINJ="$TMP/demo-no-test-inject.yml"
cp "$CONFIG" "$CONFIG_NO_TESTINJ"
replace_in_file "$CONFIG_NO_TESTINJ" "inject_testing_pom_azure_module: |
          <module>demo-test-azure</module>" "inject_testing_pom_azure_module: |"
expect_halt "fork verdict with empty testing injection halts" CONFIG_INVALID "$TMP/h18.json" \
  engine --mode generate --config "$CONFIG_NO_TESTINJ" --checkout "$H18" --report "$TMP/h18.json"

note "halt: testing module injection without a fork verdict"
H19="$TMP/h19"
fresh_copy "$H19"
CONFIG_NO_FORK="$TMP/demo-no-fork.yml"
cp "$CONFIG" "$CONFIG_NO_FORK"
replace_in_file "$CONFIG_NO_FORK" "demo-test-azure: fork" "demo-test-azure: strip"
expect_halt "testing injection without a fork verdict halts" CONFIG_INVALID "$TMP/h19.json" \
  engine --mode generate --config "$CONFIG_NO_FORK" --checkout "$H19" --report "$TMP/h19.json"

note "generate: empty expected_absent block parses as an empty list, not a map"
H0C="$TMP/h0c"
fresh_copy "$H0C"
CONFIG_EMPTY_ABSENT="$TMP/demo-empty-expected-absent.yml"
cp "$CONFIG" "$CONFIG_EMPTY_ABSENT"
replace_in_file "$CONFIG_EMPTY_ABSENT" "expected_absent:
  - provider
  - devops
  - demo-core-plus
  - .gitlab-ci.yml
  - testing/demo-test-azure
  - testing/demo-test-aws" "expected_absent:"
engine --mode generate --config "$CONFIG_EMPTY_ABSENT" --checkout "$H0C" --report "$TMP/h0c.json" > /dev/null
[ "$(report_field "$TMP/h0c.json" "r['ok']")" = "True" ] || die "empty expected_absent block did not parse as an empty list"
ok "empty expected_absent block parses as [] and the run completes"

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

note "halt: fossa modules body that is not a list"
H16="$TMP/h16"
fresh_copy "$H16"
cat > "$H16/.fossa.yml" <<'EOF'
version: 1

analyze:
  modules:
    demo-core:
      type: mvn
EOF
expect_halt "mapping-shaped fossa modules halts" FOSSA_UNPARSEABLE "$TMP/h16.json" \
  engine --mode generate --config "$CONFIG" --checkout "$H16" --report "$TMP/h16.json"

note "generate: comment lines inside fossa modules do not end the scan"
H17="$TMP/h17"
fresh_copy "$H17"
cat > "$H17/.fossa.yml" <<'EOF'
version: 1

analyze:
  modules:
  # core module
  - name: demo-core
    type: mvn
    target: demo-core/pom.xml
    path: .
  # azure module
  - name: demo-azure
    type: mvn
    target: provider/demo-azure/pom.xml
    path: .
EOF
engine --mode generate --config "$CONFIG" --checkout "$H17" > /dev/null
grep -q "name: demo-core" "$H17/.fossa.yml" || die "kept module lost with comment lines present"
! grep -q "name: demo-azure" "$H17/.fossa.yml" || die "stripped module survives with comment lines present"
ok "comments skipped, filtering intact"

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

note "halt: verify catches a missing injected profile"
H20="$TMP/h20"
rm -rf "$H20"
cp -R "$GEN1" "$H20"
python3 -c "
import re, sys
path = sys.argv[1]
text = open(path).read()
new = re.sub(r'<profile>\s*<id>azure</id>.*?</profile>\s*', '', text, flags=re.S)
assert new != text, 'azure profile not found in generated pom'
open(path, 'w').write(new)
" "$H20/pom.xml"
expect_halt "missing injected profile halts verify" INJECT_MISSING "$TMP/h20.json" \
  engine --mode verify --config "$CONFIG" --checkout "$H20" --report "$TMP/h20.json"

note "halt: verify catches a missing injected testing module"
H21="$TMP/h21"
rm -rf "$H21"
cp -R "$GEN1" "$H21"
replace_in_file "$H21/testing/pom.xml" "<module>demo-test-azure</module>" ""
expect_halt "missing injected testing module halts verify" INJECT_MISSING "$TMP/h21.json" \
  engine --mode verify --config "$CONFIG" --checkout "$H21" --report "$TMP/h21.json"

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

note "stamp: whitespace-padded version elements are rewritten"
PMW="$TMP/post-merge-padded"
rm -rf "$PMW"
cp -R "$GEN1" "$PMW"
engine --mode seed --config "$CONFIG" --checkout "$PMW" --seed-source "$FIXTURE" > /dev/null
for pom in pom.xml testing/pom.xml testing/demo-test-core/pom.xml; do
  replace_in_file "$PMW/$pom" "0.31.0-SNAPSHOT" "0.32.0-SNAPSHOT"
done
replace_in_file "$PMW/provider/demo-azure/pom.xml" ">0.31.0-SNAPSHOT<" "> 0.31.0-SNAPSHOT <"
engine --mode stamp --config "$CONFIG" --checkout "$PMW" > /dev/null
! grep -q "0.31.0-SNAPSHOT" "$PMW/provider/demo-azure/pom.xml" || die "padded pre-bump version survives"
grep -q "0.32.0-SNAPSHOT" "$PMW/provider/demo-azure/pom.xml" || die "padded version was not rewritten"
ok "padded version rewritten, padding preserved"

note "cli: a malformed invocation exits 1, not the halt code"
rc=0
engine --mode bogus --config "$CONFIG" --checkout "$GEN1" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || die "bad --mode: expected exit 1, got $rc"
ok "invocation errors exit 1"

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
git -C "$PLUMB" ls-tree -r --name-only "$commit" | grep -qx "NOTICE" || die "export-ignore file missing from the generated tree"
[ "$(git -C "$PLUMB" rev-parse "$commit:archive-metadata.txt")" = "$(git -C "$PLUMB" rev-parse "$UP_SHA:archive-metadata.txt")" ] || die "export-subst placeholder was expanded during materialization"
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

note "plumbing: first generation with no base is a single-parent commit"
GEN_OUT3="$TMP/generate3.env"
(cd "$PLUMB" && bash "$(dirname "$ENGINE")/generate-branch.sh" "" "$UP_SHA" "$CONFIG" "$GEN_OUT3")
# shellcheck disable=SC1090
. "$GEN_OUT3"
[ "${has_changes:-}" = "true" ] || die "first generation reported no changes"
FIRST_COMMIT="$commit"
PARENTS=$(git -C "$PLUMB" rev-list --parents -n 1 "$FIRST_COMMIT" | wc -w | tr -d ' ')
[ "$PARENTS" = "2" ] || die "first-generation commit is not single-parent"
[ "$(git -C "$PLUMB" rev-parse "$FIRST_COMMIT^")" = "$UP_SHA" ] || die "first-generation parent is not the upstream tip"
git -C "$PLUMB" cat-file -p "$FIRST_COMMIT" | grep -q "Upstream-Sha: $UP_SHA" || die "Upstream-Sha trailer missing from first generation"
git -C "$PLUMB" cat-file -p "$FIRST_COMMIT" | grep -q "Filter-Rev: $filter_rev" || die "Filter-Rev trailer missing from first generation"
[ "$tree" = "$TREE1" ] || die "first generation produced a different tree"
GEN_OUT4="$TMP/generate4.env"
(cd "$PLUMB" && bash "$(dirname "$ENGINE")/generate-branch.sh" "$FIRST_COMMIT" "$UP_SHA" "$CONFIG" "$GEN_OUT4")
# shellcheck disable=SC1090
. "$GEN_OUT4"
[ "${has_changes:-}" = "false" ] || die "retry against the first generation did not converge"
ok "single-parent first generation; retry converges to no changes"

note "plumbing: mirror mode produces the verbatim upstream tree (ADR-039)"
MIR_OUT="$TMP/mirror.env"
(cd "$PLUMB" && SYNC_MODE=mirror bash "$(dirname "$ENGINE")/generate-branch.sh" "$BASE_SHA" "$UP_SHA" "$TMP/no-such-config.yml" "$MIR_OUT")
# shellcheck disable=SC1090
. "$MIR_OUT"
[ "${has_changes:-}" = "true" ] || die "mirror generation reported no changes"
[ "$filter_rev" = "mirror" ] || die "mirror filter_rev is not the sentinel"
if grep -q '^report=' "$MIR_OUT"; then
  die "mirror output carries a report= line"
fi
[ "$tree" = "$(git -C "$PLUMB" rev-parse "${UP_SHA}^{tree}")" ] || die "mirror tree is not the verbatim upstream tree"
git -C "$PLUMB" ls-tree --name-only "$commit" | grep -qx "provider" || die "provider/ missing from the mirror tree"
git -C "$PLUMB" ls-tree --name-only "$commit" | grep -qx "devops" || die "devops/ missing from the mirror tree"
MIR_PARENTS=$(git -C "$PLUMB" rev-list --parents -n 1 "$commit" | wc -w | tr -d ' ')
[ "$MIR_PARENTS" = "3" ] || die "mirror commit is not merge-shaped"
git -C "$PLUMB" cat-file -p "$commit" | grep -q "Upstream-Sha: $UP_SHA" || die "Upstream-Sha trailer missing from mirror commit"
git -C "$PLUMB" cat-file -p "$commit" | grep -q "Filter-Rev: mirror" || die "Filter-Rev sentinel missing from mirror commit"
git -C "$PLUMB" cat-file -p "$commit" | grep -q "chore: mirror upstream tree" || die "mirror commit message is wrong"
if [ -n "$(git -C "$PLUMB" status --porcelain)" ]; then
  die "mirror plumbing dirtied the calling checkout"
fi
MIRROR_COMMIT="$commit"
MIR_OUT2="$TMP/mirror2.env"
(cd "$PLUMB" && SYNC_MODE=mirror bash "$(dirname "$ENGINE")/generate-branch.sh" "$MIRROR_COMMIT" "$UP_SHA" "$TMP/no-such-config.yml" "$MIR_OUT2")
# shellcheck disable=SC1090
. "$MIR_OUT2"
[ "${has_changes:-}" = "false" ] || die "mirror retry against its own commit did not converge"
MIR_OUT3="$TMP/mirror3.env"
(cd "$PLUMB" && SYNC_MODE=mirror bash "$(dirname "$ENGINE")/generate-branch.sh" "" "$UP_SHA" "$TMP/no-such-config.yml" "$MIR_OUT3")
# shellcheck disable=SC1090
. "$MIR_OUT3"
MIR_PARENTS=$(git -C "$PLUMB" rev-list --parents -n 1 "$commit" | wc -w | tr -d ' ')
[ "$MIR_PARENTS" = "2" ] || die "mirror first generation is not single-parent"
[ "$(git -C "$PLUMB" rev-parse "$commit^")" = "$UP_SHA" ] || die "mirror first-generation parent is not the upstream tip"
ok "mirror mode: verbatim tree, sentinel trailer, no report, converges"

note "seed-source: extracts trees, surviving a deletion through an ours-merge"
SSR="$TMP/seed-source-repo"
rm -rf "$SSR"
git init -q "$SSR"
git -C "$SSR" config user.name harness
git -C "$SSR" config user.email harness@local
cp -R "$FIXTURE/." "$SSR/"
rm -rf "$SSR/provider"
git -C "$SSR" add -A -f
git -C "$SSR" commit -qm "mainline without provider trees"
git -C "$SSR" checkout -q -b azure-src
cp -R "$FIXTURE/provider" "$SSR/provider"
git -C "$SSR" add -A -f
git -C "$SSR" commit -qm "add provider trees"
SIDE_SHA=$(git -C "$SSR" rev-parse HEAD)
git -C "$SSR" checkout -q -
git -C "$SSR" merge -q -s ours --no-ff -m "drop provider through a merge" azure-src
TIP_SHA=$(git -C "$SSR" rev-parse HEAD)
# The trap seed-source.sh exists for: simplified history hides the deletion.
[ -z "$(git -C "$SSR" rev-list -1 "$TIP_SHA" -- provider/demo-azure)" ] || die "expected simplified history to return nothing for the merge-deleted tree"
SS_OUT="$TMP/seed-source.env"
(cd "$SSR" && RUNNER_TEMP="$TMP/seed-source-scratch" bash "$(dirname "$ENGINE")/seed-source.sh" HEAD demo "$SS_OUT")
# shellcheck disable=SC1090
. "$SS_OUT"
[ -f "$seed_dir/provider/demo-azure/pom.xml" ] || die "provider tree missing from the seed source"
[ -f "$seed_dir/testing/demo-test-azure/pom.xml" ] || die "testing tree missing from the seed source"
[ "$provider_sha" = "$SIDE_SHA" ] || die "provider tree not taken from the deletion commit's surviving parent"
[ "$testing_sha" = "$TIP_SHA" ] || die "testing tree not taken from the tip"
ok "merge-deleted tree resolved via the deletion commit's parents; split sources composed"

note "template config: substituted for demo, generates the fixture cleanly"
TTC="$TMP/template-config.yml"
sed "s|<service>|demo|g" "$HERE/../../fork-resources/upstream-filter.yml" > "$TTC"
# archive-metadata.txt is a fixture-only file (export-subst probe), not part of
# the conventional service shape the template describes.
replace_in_file "$TTC" "top_level:" "top_level:
  archive-metadata.txt: keep"
TGEN="$TMP/template-gen"
fresh_copy "$TGEN"
engine --mode generate --config "$TTC" --checkout "$TGEN" --report "$TMP/template-gen.json" > /dev/null
[ -f "$TGEN/demo-core/pom.xml" ] || die "template config stripped demo-core"
[ ! -d "$TGEN/provider" ] || die "template config kept provider/"
grep -q "<module>provider/demo-azure</module>" "$TGEN/pom.xml" || die "template config azure profile injection missing"
ok "fork-resources template aligns with the conventional fixture"

note "halt: stamp refuses a literal one reference bumps and another keeps"
HAM="$TMP/stamp-ambiguous"
rm -rf "$HAM"
cp -R "$GEN1" "$HAM"
engine --mode seed --config "$CONFIG" --checkout "$HAM" --seed-source "$FIXTURE" > /dev/null
replace_in_file "$HAM/testing/demo-test-core/pom.xml" "0.31.0-SNAPSHOT" "0.32.0-SNAPSHOT"
expect_halt "identity collision halts instead of silently rewriting" STAMP_AMBIGUOUS "$TMP/h11.json" \
  engine --mode stamp --config "$CONFIG" --checkout "$HAM" --report "$TMP/h11.json"

printf '\nAll upstream-filter harness checks passed.\n'
