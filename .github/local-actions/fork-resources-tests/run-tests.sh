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
# Fixture harness for the fork-owned resource renderer and the build environment
# export: the Dependabot directories, CODEOWNERS and CONTRIBUTING.md rendered from
# fork_owned, NOTICE-OSDU-SPI rendered from source headers, the init script end to end
# with a stubbed gh, and BUILD_ENV parsing.
#
# Usage:
#   ./run-tests.sh

# shellcheck disable=SC2016  # Markdown ownership rows are matched with literal backticks
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RENDER="$ROOT/.github/actions/upstream-filter/fork_resources.py"
BUILD_ENV_SH="$ROOT/.github/actions/java-build/build-env.sh"
DEPLOY="$ROOT/.github/local-actions/init-helpers/deploy-fork-resources.sh"
SYNC_TEMPLATE="$ROOT/.github/template-workflows/sync-template.yml"
RESOURCES="$ROOT/.github/fork-resources"
DEMO_CONFIG="$ROOT/.github/local-actions/upstream-filter-tests/config/demo.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note() { printf '\n== %s\n' "$*"; }
die()  { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()   { printf 'ok: %s\n' "$*"; }

render() { python3 "$RENDER" "$@"; }

replace_in_file() {
  python3 -c "
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
assert old in text, f'{old!r} not found in {path}'
open(path, 'w').write(text.replace(old, new))
" "$1" "$2" "$3"
}

expect_rc() {
  local want="$1"; shift
  local rc=0
  "$@" > "$TMP/out" 2> "$TMP/err" || rc=$?
  [ "$rc" = "$want" ] || die "expected exit $want, got $rc from: $* ($(cat "$TMP/err"))"
}

# The reference-service shape: provider tree with its pom one module down, Python test suite.
REF_CFG="$TMP/ref.yml"
cp "$DEMO_CONFIG" "$REF_CFG"
replace_in_file "$REF_CFG" "service: demo" "service: demo

fork_owned:
  - provider/demo-azure
  - testing/demo_test_azure"
replace_in_file "$REF_CFG" "  pom.xml: keep
  demo-test-core: keep
  demo-test-azure: fork
  demo-test-aws: strip" "  demo_test_core: keep
  demo_test_azure: fork"
replace_in_file "$REF_CFG" "  - testing/demo-test-core" "  - testing/demo_test_core"
python3 - "$REF_CFG" <<'EOF'
import sys
path = sys.argv[1]
head, _sep, _tail = open(path).read().partition("inject_testing_pom_azure_module: |")
open(path, "w").write(head + "inject_testing_pom_azure_module: |\n")
EOF

# The indexer-queue shape: top-level Azure modules and a Maven test tree, each with a root pom.
TOP_CFG="$TMP/top.yml"
cp "$DEMO_CONFIG" "$TOP_CFG"
replace_in_file "$TOP_CFG" "service: demo" "service: demo

fork_owned:
  - demo-azure-enqueue
  - demo-azure-requeue
  - testing/demo-test-azure"
replace_in_file "$TOP_CFG" "  docs: keep" "  docs: keep
  demo-azure-enqueue: strip
  demo-azure-requeue: strip"

REF_TREE="$TMP/ref-tree"
mkdir -p "$REF_TREE/provider/demo-azure/demo-aks" "$REF_TREE/provider/demo-azure/docs" "$REF_TREE/testing/demo_test_azure"
echo "<project/>" > "$REF_TREE/provider/demo-azure/demo-aks/pom.xml"
echo "print('azure')" > "$REF_TREE/testing/demo_test_azure/run_test.py"

TOP_TREE="$TMP/top-tree"
mkdir -p "$TOP_TREE/demo-azure-enqueue" "$TOP_TREE/demo-azure-requeue" "$TOP_TREE/testing/demo-test-azure"
for d in demo-azure-enqueue demo-azure-requeue testing/demo-test-azure; do echo "<project/>" > "$TOP_TREE/$d/pom.xml"; done

note "explicit: only a config that lists fork_owned"
expect_rc 0 render explicit --config "$REF_CFG"
expect_rc 1 render explicit --config "$DEMO_CONFIG"
expect_rc 1 render explicit --config "$TMP/absent.yml"
expect_rc 1 render explicit
printf 'service: demo\n' > "$TMP/broken.yml"
expect_rc 2 render explicit --config "$TMP/broken.yml"
for bad in 'demo azure' 'demo|azure' 'demo"azure'; do
  sed "s/demo-azure-enqueue/$bad/" "$TOP_CFG" > "$TMP/unsafe.yml"
  expect_rc 2 render explicit --config "$TMP/unsafe.yml"
  grep -q "fork_owned paths must be" "$TMP/err" || die "fork_owned '$bad' refused for another reason: $(cat "$TMP/err")"
  expect_rc 2 render codeowners --config "$TMP/unsafe.yml" < "$RESOURCES/CODEOWNERS"
done
ok "explicit list detected; conventional, absent and broken configs are not; unrenderable paths refused"

note "without fork_owned every template passes through byte for byte"
for kind in dependabot codeowners contributing; do
  case "$kind" in
    dependabot) src="$RESOURCES/dependabot.yml" ;;
    codeowners) src="$RESOURCES/CODEOWNERS" ;;
    contributing) src="$RESOURCES/CONTRIBUTING.md" ;;
  esac
  render "$kind" --config "$DEMO_CONFIG" --checkout "$REF_TREE" < "$src" > "$TMP/pass.$kind"
  cmp -s "$src" "$TMP/pass.$kind" || die "$kind changed without fork_owned"
  render "$kind" < "$src" > "$TMP/pass-noconfig.$kind"
  cmp -s "$src" "$TMP/pass-noconfig.$kind" || die "$kind changed without a config"
done
ok "dependabot.yml, CODEOWNERS and CONTRIBUTING.md unchanged"

note "dependabot: directories from fork-owned trees that hold a pom"
render dependabot --config "$REF_CFG" --checkout "$REF_TREE" < "$RESOURCES/dependabot.yml" > "$TMP/ref-dependabot.yml"
python3 - "$TMP/ref-dependabot.yml" '["/provider/demo-azure/demo-aks"]' <<'EOF'
import json, sys
text = open(sys.argv[1]).read()
dirs = [l.strip()[3:-1] for l in text.splitlines() if l.strip().startswith('- "/')]
assert dirs == json.loads(sys.argv[2]), dirs
EOF
render dependabot --config "$TOP_CFG" --checkout "$TOP_TREE" < "$RESOURCES/dependabot.yml" > "$TMP/top-dependabot.yml"
python3 - "$TMP/top-dependabot.yml" '["/demo-azure-enqueue", "/demo-azure-requeue", "/testing/demo-test-azure"]' <<'EOF'
import json, sys
text = open(sys.argv[1]).read()
dirs = [l.strip()[3:-1] for l in text.splitlines() if l.strip().startswith('- "/')]
assert dirs == json.loads(sys.argv[2]), dirs
EOF
diff <(grep -v '^      - "/' "$RESOURCES/dependabot.yml") <(grep -v '^      - "/' "$TMP/top-dependabot.yml") > /dev/null \
  || die "dependabot rendering changed more than the directories"
ok "nested provider pom found one module down; Python suite skipped; root poms kept"

note "dependabot: a discovered module with an unrenderable name is skipped with a warning"
cp -R "$REF_TREE" "$TMP/odd-tree"
mkdir -p "$TMP/odd-tree/provider/demo-azure/bad\"module"
echo "<project/>" > "$TMP/odd-tree/provider/demo-azure/bad\"module/pom.xml"
expect_rc 0 render dependabot --config "$REF_CFG" --checkout "$TMP/odd-tree" < "$RESOURCES/dependabot.yml"
cmp -s "$TMP/ref-dependabot.yml" "$TMP/out" || die "an unrenderable module name reached dependabot.yml"
grep -q 'warning: skipping module provider/demo-azure/bad"module' "$TMP/err" || die "skipped module not reported: $(cat "$TMP/err")"
cp -R "$REF_TREE" "$TMP/newline-tree"
FORGED="bad"$'\n'"::error::forged"
mkdir -p "$TMP/newline-tree/provider/demo-azure/$FORGED"
echo "<project/>" > "$TMP/newline-tree/provider/demo-azure/$FORGED/pom.xml"
expect_rc 0 render dependabot --config "$REF_CFG" --checkout "$TMP/newline-tree" < "$RESOURCES/dependabot.yml"
cmp -s "$TMP/ref-dependabot.yml" "$TMP/out" || die "a module name with a newline reached dependabot.yml"
! grep -q '^::' "$TMP/err" || die "a rejected module name opened a workflow command line: $(cat "$TMP/err")"
grep -qF 'warning: skipping module provider/demo-azure/bad\n::error::forged' "$TMP/err" || die "newline module not reported escaped: $(cat "$TMP/err")"
ok "unsafe modules left out and reported escaped, including a newline; safe sibling rendered as before"

note "dependabot: no fork-owned pom exits 3"
mkdir -p "$TMP/no-pom/provider/demo-azure" "$TMP/no-pom/testing/demo_test_azure"
expect_rc 3 render dependabot --config "$REF_CFG" --checkout "$TMP/no-pom" < "$RESOURCES/dependabot.yml"
ok "no directory to watch is reported, not rendered empty"

note "codeowners and contributing: fork_owned paths replace the conventional pair"
render codeowners --config "$TOP_CFG" < "$RESOURCES/CODEOWNERS" > "$TMP/codeowners"
grep -qxF "$(printf '%-32s%s' /demo-azure-enqueue/ '<owners>')" "$TMP/codeowners" || die "enqueue line missing or misaligned"
grep -qxF "$(printf '%-32s%s' /testing/demo-test-azure/ '<owners>')" "$TMP/codeowners" || die "testing line missing or misaligned"
! grep -v '^#' "$TMP/codeowners" | grep -q '<service>' || die "a <service> line survived"
render contributing --config "$REF_CFG" < "$RESOURCES/CONTRIBUTING.md" > "$TMP/contributing"
grep -q '^| `provider/demo-azure/`, `testing/demo_test_azure/`, `.spi/`' "$TMP/contributing" || die "ownership row not rendered"
ok "CODEOWNERS lines keep the owners column; CONTRIBUTING row names the trees"

note "template drift fails loudly"
grep -v 'testing/\*-test-azure' "$RESOURCES/dependabot.yml" > "$TMP/drift.yml"
expect_rc 2 render dependabot --config "$REF_CFG" --checkout "$REF_TREE" < "$TMP/drift.yml"
sed 's|provider/\*-azure|provider/*|' "$RESOURCES/CONTRIBUTING.md" > "$TMP/drift.md"
expect_rc 2 render contributing --config "$REF_CFG" < "$TMP/drift.md"
ok "a template without the default lines exits 2"

# A checkout whose Java headers name holders in the spellings upstream uses, plus lines that
# must not count: a body string, a header past line 20, a non-Java file, an untracked file and
# a template fixture under .github.
NOTICE_TREE="$TMP/notice-tree"
mkdir -p "$NOTICE_TREE/demo-core/src" "$NOTICE_TREE/provider/demo-azure/src"
java_file() { printf '%s\n' "${@:2}" "package demo;" > "$NOTICE_TREE/$1"; }
java_file demo-core/src/A.java "/*" " * Copyright 2017-2020, Schlumberger" " *" " * Licensed under the Apache License"
java_file demo-core/src/B.java "/* Copyright (c) 2020 Google LLC. All rights reserved. */" "// Copyright 2021 Google"
java_file demo-core/src/C.java "// Copyright © SLB" "// Copyright 2021 Microsoft"
java_file demo-core/src/D.java "/*" " *  Copyright © Amazon Web Services" " *  Copyright 2020 EPAM Systems, Inc." " */"
java_file provider/demo-azure/src/E.java "// Copyright © Microsoft Corporation" 'class E { String s = "Copyright Contoso"; }'
java_file provider/demo-azure/src/F.java "// Copyright © Azure"
java_file provider/demo-azure/src/J.java "// Copyright 2024 Fabrikam Ltd"
java_file demo-core/src/G.java $'\xef\xbb\xbf// Copyright 2020 Google LLC'
java_file demo-core/src/H.java "/**" " ** Copyright 2020 SLB" " */"
java_file demo-core/src/I.java $'// Copyright \xa9 Microsoft Corporation'
{ for _ in $(seq 1 19); do echo "// line"; done; echo "// Copyright The Open Group"; } > "$NOTICE_TREE/demo-core/src/Edge.java"
ln -s Missing.java "$NOTICE_TREE/demo-core/src/Broken.java"
mkdir -p "$NOTICE_TREE/.github/local-actions/fixtures"
echo "// Copyright Contoso" > "$NOTICE_TREE/.github/local-actions/fixtures/Fixture.java"
{ for _ in $(seq 1 20); do echo "// line"; done; echo "// Copyright Contoso"; } > "$NOTICE_TREE/demo-core/src/Late.java"
echo "Copyright Contoso" > "$NOTICE_TREE/demo-core/notes.md"
git -C "$NOTICE_TREE" -c init.defaultBranch=main init -q
git -C "$NOTICE_TREE" add -A
echo "// Copyright Contoso" > "$NOTICE_TREE/demo-core/src/Untracked.java"

note "notice: project and source from the URL, holders from the Java headers"
expect_rc 0 render notice --upstream-url "https://example.test/osdu/demo/.git" --checkout "$NOTICE_TREE" < "$RESOURCES/NOTICE-OSDU-SPI"
cp "$TMP/out" "$TMP/notice"
rm "$NOTICE_TREE/demo-core/src/Untracked.java"
grep -qx "Component: OSDU demo" "$TMP/notice" || die "project not named from the URL"
grep -qx "Source: https://example.test/osdu/demo" "$TMP/notice" || die "source not the URL without .git"
grep -q "community project demo and carries" "$TMP/notice" || die "project not named in the prose"
[ "$(grep '^  ' "$TMP/notice")" = "$(printf '  %s\n' "Microsoft Corporation" "SLB" "Google LLC" "Amazon.com, Inc. or its affiliates" "EPAM Systems, Inc." "Fabrikam Ltd" "The Open Group")" ] \
  || die "unexpected holders: $(grep '^  ' "$TMP/notice")"
! grep -q '<project>\|<upstream-url>\|<holders>\|Contoso' "$TMP/notice" || die "a placeholder or an uncounted holder survived"
diff <(grep -v '<project>\|<upstream-url>\|<holders>' "$RESOURCES/NOTICE-OSDU-SPI") \
     <(grep -v 'OSDU demo\|community project demo\|^Source: \|^  ' "$TMP/notice") > /dev/null \
  || die "notice rendering changed more than the placeholders"
[ "$(cat "$TMP/err")" = "warning: copyright holder kept as written: Fabrikam Ltd" ] || die "unexpected stderr: $(cat "$TMP/err")"
ok "aliases collapse, files count once per holder, most files first; BOM, Latin-1 and line-20 headers read; unknown holder kept with a warning"

note "notice: refusals"
mkdir -p "$TMP/no-java"
git -C "$TMP/no-java" -c init.defaultBranch=main init -q
expect_rc 4 render notice --upstream-url "https://example.test/osdu/demo" --checkout "$TMP/no-java" < "$RESOURCES/NOTICE-OSDU-SPI"
[ ! -s "$TMP/out" ] || die "rc 4 wrote a notice"
for bad in "ftp://example.test/osdu/demo" "git@example.test:osdu/demo.git" "https://example.test" "https://example.test/osdu/demo?x=1" $'https://example.test/osdu/demo\n::error::forged'; do
  expect_rc 2 render notice --upstream-url "$bad" --checkout "$NOTICE_TREE" < "$RESOURCES/NOTICE-OSDU-SPI"
  ! grep -q '^::' "$TMP/err" || die "a refused URL opened a workflow command line: $(cat "$TMP/err")"
done
grep -v '<holders>' "$RESOURCES/NOTICE-OSDU-SPI" > "$TMP/drift-notice"
expect_rc 2 render notice --upstream-url "https://example.test/osdu/demo" --checkout "$NOTICE_TREE" < "$TMP/drift-notice"
expect_rc 2 render notice --checkout "$NOTICE_TREE" < "$RESOURCES/NOTICE-OSDU-SPI"
ok "no headers exits 4; a non-http(s) or forged URL, a drifted template and a missing URL exit 2"

# Init end to end: a throwaway checkout with the template's resources and a gh that answers
# the CODEOWNERS variable.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2 $3" = "variable get CODEOWNERS" ] && { echo "@contoso/owners"; exit 0; }
exit 1
EOF
chmod +x "$TMP/bin/gh"

init_fork() {
  local ws="$1" cfg="$2" tree="$3"
  mkdir -p "$ws/.github/actions" "$ws/.github/local-actions"
  cp -R "$RESOURCES" "$ws/.github/fork-resources"
  cp -R "$ROOT/.github/actions/upstream-filter" "$ws/.github/actions/"
  cp "$ROOT/.github/sync-config.json" "$ws/.github/sync-config.json"
  [ -n "$cfg" ] && cp "$cfg" "$ws/.github/upstream-filter.yml"
  [ -n "$tree" ] && cp -R "$tree/." "$ws/"
  git -C "$ws" -c init.defaultBranch=main init -q
  git -C "$ws" add -A
  (cd "$ws" && PATH="$TMP/bin:$PATH" UPSTREAM_REPO_URL="${INIT_URL-https://example.test/demo.git}" bash "$DEPLOY" > "$ws.log")
}

note "init: a conventional fork plants what it planted before"
CONV="$TMP/conv"
mkdir -p "$CONV/provider/demo-azure" "$CONV/testing/demo-test-azure" "$CONV/.github/local-actions/fixtures"
echo "// Copyright © Microsoft Corporation" > "$CONV/.github/local-actions/fixtures/Main.java"
init_fork "$CONV" "$DEMO_CONFIG" ""
cmp -s "$RESOURCES/dependabot.yml" "$CONV/.github/dependabot.yml" || die "conventional dependabot.yml changed"
cmp -s "$RESOURCES/CONTRIBUTING.md" "$CONV/CONTRIBUTING.md" || die "conventional CONTRIBUTING.md changed"
sed 's|<owners>|@contoso/owners|g; s|<service>|demo|g' "$RESOURCES/CODEOWNERS" | cmp -s - "$CONV/.github/CODEOWNERS" \
  || die "conventional CODEOWNERS changed"
ok "dependabot.yml, CONTRIBUTING.md and CODEOWNERS as before"

note "init: a fork_owned fork plants its own paths"
OWN="$TMP/own"
init_fork "$OWN" "$TOP_CFG" "$TOP_TREE"
cmp -s "$TMP/top-dependabot.yml" "$OWN/.github/dependabot.yml" || die "fork_owned dependabot.yml not rendered"
grep -qxF "$(printf '%-32s%s' /demo-azure-requeue/ @contoso/owners)" "$OWN/.github/CODEOWNERS" || die "fork_owned CODEOWNERS not rendered"
grep -q '^| `demo-azure-enqueue/`, `demo-azure-requeue/`, `testing/demo-test-azure/`' "$OWN/CONTRIBUTING.md" \
  || die "fork_owned CONTRIBUTING.md not rendered"
ok "directories, owners and ownership row follow fork_owned"

note "init: no fork-owned pom leaves Dependabot unplanted with a warning"
NOPOM="$TMP/nopom"
init_fork "$NOPOM" "$REF_CFG" "$TMP/no-pom"
[ ! -e "$NOPOM/.github/dependabot.yml" ] || die "an unwatchable dependabot.yml was planted"
grep -q "::warning::No fork_owned tree holds a pom.xml" "$NOPOM.log" || die "no warning for the missing pom"
ok "warning raised, file absent"

note "init: NOTICE-OSDU-SPI planted from the fork's headers, never over an existing file"
render notice --upstream-url "https://example.test/demo.git" --checkout "$NOTICE_TREE" < "$RESOURCES/NOTICE-OSDU-SPI" > "$TMP/init-notice" 2> /dev/null
NOTICE_INIT="$TMP/notice-init"
init_fork "$NOTICE_INIT" "$DEMO_CONFIG" "$NOTICE_TREE"
cmp -s "$TMP/init-notice" "$NOTICE_INIT/NOTICE-OSDU-SPI" || die "init NOTICE-OSDU-SPI differs from the renderer's"
git -C "$NOTICE_INIT" ls-files --error-unmatch NOTICE-OSDU-SPI > /dev/null 2>&1 || die "NOTICE-OSDU-SPI not staged"
grep -q "::warning::NOTICE-OSDU-SPI: copyright holder kept as written: Fabrikam Ltd" "$NOTICE_INIT.log" || die "unknown holder not annotated"
[ ! -e "$NOTICE_INIT/.github/fork-resources" ] || die "fork-resources left behind"
grep -q "::warning::NOTICE-OSDU-SPI not planted: no Java source" "$CONV.log" || die "a fork whose only header is a template fixture was not warned"
[ ! -e "$CONV/NOTICE-OSDU-SPI" ] || die "a fork without headers got a notice"
KEPT_TREE="$TMP/kept-tree"
cp -R "$NOTICE_TREE" "$KEPT_TREE"
echo "edited by the fork" > "$KEPT_TREE/NOTICE-OSDU-SPI"
init_fork "$TMP/notice-kept" "$DEMO_CONFIG" "$KEPT_TREE"
[ "$(cat "$TMP/notice-kept/NOTICE-OSDU-SPI")" = "edited by the fork" ] || die "init overwrote an existing NOTICE-OSDU-SPI"
INIT_URL="" init_fork "$TMP/notice-nourl" "$DEMO_CONFIG" "$NOTICE_TREE"
[ ! -e "$TMP/notice-nourl/NOTICE-OSDU-SPI" ] || die "planted without an upstream URL"
grep -q "::warning::NOTICE-OSDU-SPI not planted: UPSTREAM_REPO_URL" "$TMP/notice-nourl.log" || die "no warning for the missing URL"
ok "planted and staged; unknown holder annotated; existing file kept; no headers or no URL warns"

# Template sync: the check-updates term and the plant block run as written in the workflow,
# in a fork checkout whose template ref carries the notice template.
python3 - "$SYNC_TEMPLATE" "$TMP/check-notice.sh" "$TMP/plant-notice.sh" <<'EOF'
import sys, yaml
steps = [s for job in yaml.safe_load(open(sys.argv[1]))["jobs"].values() for s in job.get("steps", [])]
def run(name):
    return next(s["run"] for s in steps if s.get("name") == name).splitlines()
def window(lines, start, stop):
    i = next(n for n, l in enumerate(lines) if l.strip().startswith(start))
    j = next(n for n in range(i + 1, len(lines)) if stop(lines[n]))
    return "\n".join(lines[i:j]) + "\n"
check = run("Check for template updates")
open(sys.argv[2], "w").write(window(check, "PLANT_NOTICE=false", lambda l: l.strip() == "fi") + "fi\necho \"PLANT_NOTICE=$PLANT_NOTICE\"\n")
plant = run("Sync template files")
open(sys.argv[3], "w").write(window(plant, 'if [ ! -f "NOTICE-OSDU-SPI" ]', lambda l: "Syncing sync configuration file" in l))
EOF
SYNC_FORK="$TMP/sync-fork"
cp -R "$NOTICE_TREE" "$SYNC_FORK"
TPL_BLOB=$(git -C "$SYNC_FORK" hash-object -w "$RESOURCES/NOTICE-OSDU-SPI")
TPL_TREE=$(printf '100644 blob %s\tNOTICE-OSDU-SPI\n' "$TPL_BLOB" | git -C "$SYNC_FORK" mktree)
TPL_TREE=$(printf '040000 tree %s\tfork-resources\n' "$TPL_TREE" | git -C "$SYNC_FORK" mktree)
TPL_TREE=$(printf '040000 tree %s\t.github\n' "$TPL_TREE" | git -C "$SYNC_FORK" mktree)
git -C "$SYNC_FORK" update-ref refs/remotes/template/main \
  "$(git -C "$SYNC_FORK" -c user.name=t -c user.email=t@example.test commit-tree "$TPL_TREE" -m template)"
sync_notice() {
  local script="$1" url="$2"
  mkdir -p "$TMP/runner"
  (cd "$SYNC_FORK" && RUNNER_TEMP="$TMP/runner" RENDER="$RENDER" UPSTREAM_URL="$url" bash -e "$script" > "$TMP/sync.log" 2>&1)
}

note "sync: a missing notice counts as an update and is planted from the fork's headers"
sync_notice "$TMP/check-notice.sh" "https://example.test/demo.git"
grep -qx "PLANT_NOTICE=true" "$TMP/sync.log" || die "missing notice not counted as an update: $(cat "$TMP/sync.log")"
sync_notice "$TMP/check-notice.sh" ""
grep -qx "PLANT_NOTICE=false" "$TMP/sync.log" || die "counted as an update without a URL"
sync_notice "$TMP/plant-notice.sh" "https://example.test/demo.git" || die "plant block failed: $(cat "$TMP/sync.log")"
cmp -s "$TMP/init-notice" "$SYNC_FORK/NOTICE-OSDU-SPI" || die "sync NOTICE-OSDU-SPI differs from the renderer's"
git -C "$SYNC_FORK" diff --cached --quiet -- NOTICE-OSDU-SPI && die "NOTICE-OSDU-SPI not staged"
grep -qx "::warning::NOTICE-OSDU-SPI: copyright holder kept as written: Fabrikam Ltd" "$TMP/sync.log" || die "unknown holder not annotated"
sync_notice "$TMP/check-notice.sh" "https://example.test/demo.git"
grep -qx "PLANT_NOTICE=false" "$TMP/sync.log" || die "a planted notice still counts as an update"
echo "edited by the fork" > "$SYNC_FORK/NOTICE-OSDU-SPI"
sync_notice "$TMP/plant-notice.sh" "https://example.test/demo.git"
[ "$(cat "$SYNC_FORK/NOTICE-OSDU-SPI")" = "edited by the fork" ] || die "sync overwrote an existing NOTICE-OSDU-SPI"
ok "counted, planted and staged once; unknown holder annotated; existing file kept"

note "sync: a notice that can't be rendered warns and the sync continues"
git -C "$SYNC_FORK" rm -q -f NOTICE-OSDU-SPI
sync_notice "$TMP/plant-notice.sh" "ftp://example.test/demo" || die "a render failure failed the sync step"
[ ! -e "$SYNC_FORK/NOTICE-OSDU-SPI" ] || die "planted from a refused URL"
grep -q "::warning::NOTICE-OSDU-SPI not planted: rendering failed" "$TMP/sync.log" || die "no warning for the render failure"
sync_notice "$TMP/plant-notice.sh" "" || die "a missing URL failed the sync step"
grep -q "::warning::UPSTREAM_REPO_URL is not set" "$TMP/sync.log" || die "no warning for the missing URL"
ok "refused URL and missing URL warn without failing the step"

note "build env: KEY=VALUE lines reach GITHUB_ENV with the workspace expanded"
run_build_env() {
  : > "$TMP/github_env"
  BUILD_ENV="$1" GITHUB_WORKSPACE=/work GITHUB_ENV="$TMP/github_env" bash "$BUILD_ENV_SH" > "$TMP/build-env.out" 2>&1
}
run_build_env $'SIS_DATA=$GITHUB_WORKSPACE/apachesis_setup/SIS_DATA\r\n\n# a comment\nOTHER=${GITHUB_WORKSPACE}/x=y\nPLAIN=$HOME\nPREFIX=$GITHUB_WORKSPACE_SUFFIX:$GITHUB_WORKSPACE:${GITHUB_WORKSPACE}x:$GITHUB_WORKSPACE'
[ "$(cat "$TMP/github_env")" = $'SIS_DATA=/work/apachesis_setup/SIS_DATA\nOTHER=/work/x=y\nPLAIN=$HOME\nPREFIX=$GITHUB_WORKSPACE_SUFFIX:/work:/workx:/work' ] \
  || die "unexpected GITHUB_ENV: $(cat "$TMP/github_env")"
run_build_env ""
[ ! -s "$TMP/github_env" ] || die "an empty BUILD_ENV wrote to GITHUB_ENV"
for bad in "NOEQUALS" "1BAD=x" "SPACE KEY=x" "PATH=/tmp" "GITHUB_TOKEN=x" "MAVEN_OPTS=-X" "M2_HOME=/x" "MAVEN_PROFILE=core" "GENERATE_COVERAGE=false"; do
  if run_build_env "$bad"; then die "BUILD_ENV '$bad' was accepted"; fi
  grep -q "::error::" "$TMP/build-env.out" || die "BUILD_ENV '$bad' failed without an error annotation"
done
ok "workspace expanded, nothing else; malformed and reserved names refused"

note "images: every published image carries the notices under /licenses/"
for f in Dockerfile acceptance.Dockerfile load.Dockerfile; do
  grep -qx 'COPY LICENSE NOTICE NOTICE-OSDU-SPI /licenses/' "$ROOT/build/$f" || die "build/$f must copy LICENSE, NOTICE and NOTICE-OSDU-SPI to /licenses/ by name"
done
for allow in '!LICENSE' '!NOTICE' '!NOTICE-OSDU-SPI'; do
  grep -qxF "$allow" "$ROOT/build/load.Dockerfile.dockerignore" || die "load sidecar dockerignore must re-admit $allow"
done
grep -q '^FROM --platform=$BUILDPLATFORM .* AS agent$' "$ROOT/build/Dockerfile" || die "the agent stage must run on the build platform"
grep -qx 'COPY --from=agent /agent/notices/ /licenses/applicationinsights-agent/' "$ROOT/build/Dockerfile" || die "the agent's license and notice files must reach /licenses/"
grep -qx 'COPY --from=agent /agent/applicationinsights-agent.jar /opt/agents/applicationinsights-agent.jar' "$ROOT/build/Dockerfile" || die "the agent must stay at /opt/agents/, where the entrypoint attaches it"
ok "service, acceptance and load images copy the notices; the agent's notices come from the verified jar"

printf '\nAll fork-resources and build-env checks passed.\n'
