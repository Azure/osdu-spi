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
# Fixture harness for the Component Governance pipeline steps (ADR-047). It covers the
# logic a live run rarely exercises and that would fail silently: which commit's images
# the gate trusts, whether a downloaded NOTICE belongs to this run's complete scan, which
# NOTICE refresh may replace another, the one-time NOTICE cutover, and the gate's copy of
# Validation's push filter. Fixture repositories and a scripted HTTP API on 127.0.0.1;
# no network.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CG="$ROOT/.github/actions/component-governance"
PIPELINE="$ROOT/.azuredevops/component-governance.yml"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
API_PID=""
stop_api() {
  if [ -n "$API_PID" ]; then kill "$API_PID" 2>/dev/null || true; wait "$API_PID" 2>/dev/null || true; API_PID=""; fi
}
trap 'stop_api; rm -rf "$TMP"' EXIT

note()  { printf '\n== %s\n' "$*"; }
die()   { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()    { printf 'ok: %s\n' "$*"; }

mkdir -p "$TMP/home"
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.com
export CG_POLL_SECONDS=0 PYTHONDONTWRITEBYTECODE=1
REPO="Azure/osdu-spi-demo"
TOKEN_HEADER="AUTHORIZATION: basic $(printf '%s' 'x-access-token:tok-123' | base64)"

# Runs a command that must fail with output containing a fixed string.
run_fail() {
  local desc="$1" pattern="$2" out
  shift 2
  if out=$("$@" 2>&1); then die "$desc: succeeded, wanted a failure containing '$pattern'"; fi
  grep -qF -- "$pattern" <<<"$out" || die "$desc: output does not contain '$pattern':
$out"
  ok "$desc"
}

# Runs a command that must succeed with output containing a fixed string. Captures first, so an early
# grep exit cannot break the producer's pipe.
expect_out() {
  local pattern="$1" out
  shift
  out=$("$@" 2>&1) || die "$*: failed:
$out"
  grep -qF -- "$pattern" <<<"$out" || die "$*: output does not contain '$pattern':
$out"
}

start_api() {
  stop_api
  rm -f "$TMP/api.port"
  : > "$TMP/api.log"
  python3 "$HERE/fake_api.py" "$1" "$TMP/api.port" "$TMP/api.log" &
  API_PID=$!
  for _ in $(seq 100); do [ -s "$TMP/api.port" ] && break; sleep 0.05; done
  [ -s "$TMP/api.port" ] || die "fake API did not start"
  API="http://127.0.0.1:$(cat "$TMP/api.port")"
}

api_calls() { grep -c "$1" "$TMP/api.log" || true; }

json_get() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }

# ---------------------------------------------------------------- fixture fork

# upstream S -> U; generated tree G with U as its only parent (first generation);
# then the seeded fork commit F with Seeded-From S.
make_fork() {
  local d="$1"
  git init -q -b main "$d"
  cd "$d"
  echo one > up.txt && git add up.txt && git commit -qm "upstream: first"
  S=$(git rev-parse HEAD)
  echo two > up.txt && git commit -qam "upstream: tip"
  U=$(git rev-parse HEAD)
  G=$(git commit-tree "$U^{tree}" -p "$U" -m "chore: generate filtered upstream tree" -m "Upstream-Sha: $U
Filter-Rev: 0123456")
  git reset -q --hard "$G"
  mkdir -p provider/demo-azure .mvn build .spi deployments/shared-schemas demo-acceptance-test/python testing docs
  printf '<project><build><plugins><plugin><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>\n' \
    > provider/demo-azure/pom.xml
  echo '<settings/>' > .mvn/community-maven.settings.xml
  printf 'FROM scratch\nARG APPLICATIONINSIGHTS_AGENT_VERSION=3.7.8\n' > build/Dockerfile
  echo '{}' > deployments/shared-schemas/a.json
  echo pytest > demo-acceptance-test/python/requirements.txt
  echo tests > testing/README
  echo docs > docs/index.md
  cat > .spi/service.yaml <<'EOF'
schemaVersion: 3
service: { name: demo, archetype: java-maven-azure }
tests: {}
componentGovernance:
  upstream: https://community.opengroup.org/osdu/platform/system/demo
  ignoreDirectories: [demo-acceptance-test/python, testing]
EOF
  git add -A && git commit -qm "chore: seed Azure trees" -m "Seeded-From: provider/demo-azure $S"
  F=$(git rev-parse HEAD)
  cd - >/dev/null
}

resolve() {  # dir [images]
  (cd "$1" && OUT="$TMP/out" BUILD_REPOSITORY_NAME="$REPO" BUILD_SOURCEVERSION="$(git rev-parse HEAD)" \
    BUILD_SOURCESDIRECTORY="$1" CG_IMAGES="${2:-auto}" python3 "$CG/resolve_inputs.py")
}

FORK="$TMP/fork"
make_fork "$FORK"

note "resolve: inputs, manifest and variables from the descriptor"
rm -rf "$TMP/out"
out=$(resolve "$FORK")
sha12=${F:0:12}
grep -qxF "##vso[task.setvariable variable=MAVEN_ARGS]--settings=$FORK/.mvn/community-maven.settings.xml -P core,azure -pl provider/demo-azure -am" <<<"$out" \
  || die "MAVEN_ARGS not set to the inferred module: $out"
grep -qxF "##vso[task.setvariable variable=dockerImagesToScan]ghcr.io/azure/osdu-spi-demo:sha-$sha12,ghcr.io/azure/osdu-spi-demo-load:sha-$sha12" <<<"$out" \
  || die "images not the commit's service and loader images: $out"
grep -qxF "##vso[task.setvariable variable=ComponentDetection.IgnoreDirectories]demo-acceptance-test/python,testing" <<<"$out" \
  || die "ignored directories not set"
cmp -s "$FORK/cgmanifest.json" "$TMP/out/cgmanifest.json" || die "cgmanifest.json differs between the checkout and OUT"
python3 - "$TMP/out/cgmanifest.json" "$U" "$S" <<'PY' || die "cgmanifest.json registrations are wrong"
import json, sys
regs = [r["component"] for r in json.load(open(sys.argv[1]))["registrations"]]
url = "https://community.opengroup.org/osdu/platform/system/demo"
assert regs[0] == {"type": "git", "git": {"repositoryUrl": url, "commitHash": sys.argv[2]}}, regs
assert regs[1] == {"type": "git", "git": {"repositoryUrl": url, "commitHash": sys.argv[3]}}, regs
assert regs[2]["maven"] == {"groupId": "com.microsoft.azure", "artifactId": "applicationinsights-agent", "version": "3.7.8"}, regs
assert len(regs) == 3
PY
[ "$(json_get "$TMP/out/cg-inputs.json" 'd["generatedCommit"], d["upstreamCommit"], d["seeds"], d["imagesAuto"], d["imagesCommit"]')" \
  = "$G $U ['$S'] True $F" ] || die "cg-inputs.json does not record the provenance and the image commit"
ok "upstream + seed commits and the agent registered; module inferred; images and ignores set"
rm -rf "$TMP/named" && cp -a "$FORK" "$TMP/named"
echo "  image: demo-service" >> "$TMP/named/.spi/service.yaml"
expect_out "##vso[task.setvariable variable=dockerImagesToScan]ghcr.io/azure/demo-service:sha-$sha12,ghcr.io/azure/demo-service-load:sha-$sha12" \
  resolve "$TMP/named"
ok "image names Validation's package when SERVICE_NAME differs from the repository"

# ---------------------------------------------------------------- image gate

GATE="$TMP/gate"
rm -rf "$GATE" && cp -a "$FORK" "$GATE"
echo 'class A {}' > "$GATE/provider/demo-azure/A.java"
git -C "$GATE" add -A && git -C "$GATE" commit -qm "feat: code"
CODE=$(git -C "$GATE" rev-parse HEAD)
mkdir -p "$GATE/.github/workflows" && echo "name: x" > "$GATE/.github/workflows/x.yml"
echo more >> "$GATE/docs/index.md"
# A template sync from long ago: its grace period is over.
git -C "$GATE" add -A && GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" git -C "$GATE" commit -qm "chore: template sync"
DOCS=$(git -C "$GATE" rev-parse HEAD)
echo "LICENSE text" > "$GATE/LICENSE" && echo "notice" > "$GATE/NOTICE"
git -C "$GATE" add -A && git -C "$GATE" commit -qm "chore(notice): refresh"
NOTICEC=$(git -C "$GATE" rev-parse HEAD)
# A documentation tip pushed just now, whose push may still publish an image for code below it.
echo again >> "$GATE/docs/index.md"
git -C "$GATE" add -A && git -C "$GATE" commit -qm "docs: tip"
FRESH=$(git -C "$GATE" rev-parse HEAD)

check_run() {  # status conclusion suite
  printf '{"status": "%s", "conclusion": %s, "app": {"slug": "github-actions"}, "check_suite": {"id": %s}}' "$1" "$2" "$3"
}
gate_routes() {  # file; then lines "sha|check-runs json|actions-runs json"
  local file="$1" first=1 sha runs push
  shift
  { echo "["
    for spec in "$@"; do
      IFS='|' read -r sha runs push <<<"$spec"
      [ $first = 1 ] || echo ","
      first=0
      printf '{"method": "GET", "path": "/repos/%s/commits/%s/check-runs.*", "responses": %s},\n' "$REPO" "$sha" "$runs"
      printf '{"method": "GET", "path": "/repos/%s/actions/runs.head_sha=%s.*", "responses": %s}\n' "$REPO" "$sha" "$push"
    done
    printf ',{"method": "GET", "path": "/repos/%s/pulls.head=Azure%%3Amain.*", "responses": [{"status": 200, "json": %s}]}\n' "$REPO" "${PULLS_FROM_MAIN:-[]}"
    printf ',{"method": "GET", "path": "/repos/%s/check-suites/7", "responses": [{"status": 200, "json": {"head_branch": "main"}}]}\n' "$REPO"
    echo "]"; } > "$file"
}
ok_runs() { printf '[{"status": 200, "json": {"check_runs": [%s]}}]' "$(check_run "$@")"; }
no_runs='[{"status": 200, "json": {"check_runs": []}}]'
push_suite='[{"status": 200, "json": {"workflow_runs": [{"check_suite_id": 7}]}}]'
no_push='[{"status": 200, "json": {"workflow_runs": []}}]'
forbidden='[{"status": 403, "json": {"message": "Resource not accessible by integration"}}]'

gate() {  # head [images]
  git -C "$GATE" checkout -q "$1"
  git -C "$GATE" config --local http.https://github.com/.extraheader "$TOKEN_HEADER"
  resolve "$GATE" "${2:-auto}" > /dev/null
  (cd "$GATE" && OUT="$TMP/out" BUILD_REPOSITORY_NAME="$REPO" BUILD_SOURCESDIRECTORY="$GATE" GITHUB_API_URL="$API" \
    CG_IMAGE_GRACE_SECONDS="${GRACE:-0}" CG_IMAGE_WAIT_SECONDS=30 python3 "$CG/wait_images.py")
}
no_credential() {
  ! git -C "$GATE" config --local --get-regexp '^http\..*\.extraheader$' >/dev/null || die "the GitHub credential survived the gate"
}

note "gate: waits for the commit's push-event Docker Push"
gate_routes "$TMP/r.json" "$CODE|[{\"status\": 200, \"json\": {\"check_runs\": [$(check_run in_progress null 7)]}}, {\"status\": 200, \"json\": {\"check_runs\": [$(check_run completed '"success"' 7)]}}]|$push_suite"
start_api "$TMP/r.json"
out=$(gate "$CODE")
grep -qF "Docker Push succeeded for $CODE (matched by push-event workflow runs)" <<<"$out" || die "gate did not pass: $out"
[ "$(api_calls 'check-runs')" -ge 2 ] || die "gate did not poll an in-progress run"
grep -qF '"auth": "Bearer tok-123"' "$TMP/api.log" || die "gate did not use the checkout's token"
[ "$(json_get "$TMP/out/cg-inputs.json" 'd["imagesCommit"]')" = "$CODE" ] || die "image commit changed"
no_credential
ok "in-progress run waited out; token used, then removed"

note "gate: a push Validation ignores falls back to its first parent once its grace is over"
gate_routes "$TMP/r.json" "$DOCS|$no_runs|$no_push" "$CODE|$(ok_runs completed '"success"' 7)|$push_suite"
start_api "$TMP/r.json"
out=$(GRACE=600 gate "$DOCS" 2>&1) || die "an old template-sync commit did not fall back to its parent: $out"
c12=${CODE:0:12}
grep -qF "changes only files Validation's push filter ignores" <<<"$out" || die "fallback not explained: $out"
grep -qxF "##vso[task.setvariable variable=dockerImagesToScan]ghcr.io/azure/osdu-spi-demo:sha-$c12,ghcr.io/azure/osdu-spi-demo-load:sha-$c12" <<<"$out" \
  || die "images not rewritten to the parent's: $out"
[ "$(json_get "$TMP/out/cg-inputs.json" 'd["imagesCommit"], d["images"].count("'"$c12"'")')" = "$CODE 2" ] || die "cg-inputs.json not updated"
no_credential
ok "template-sync commit scanned with its parent's published images"
gate_routes "$TMP/r.json" "$NOTICEC|$no_runs|$no_push" "$DOCS|$no_runs|$no_push" "$CODE|$(ok_runs completed '"success"' 7)|$push_suite"
start_api "$TMP/r.json"
run_fail "a NOTICE refresh is validated, so it is not skipped" "No push-triggered Docker Push run exists for $NOTICEC" gate "$NOTICEC"
no_credential
gate_routes "$TMP/r.json" "$FRESH|[{\"status\": 200, \"json\": {\"check_runs\": []}}, {\"status\": 200, \"json\": {\"check_runs\": [$(check_run completed '"success"' 7)]}}]|$push_suite"
start_api "$TMP/r.json"
out=$(GRACE=600 gate "$FRESH" 2>&1) || die "a recent documentation tip did not wait for its own push: $out"
grep -qF "Docker Push succeeded for $FRESH" <<<"$out" || die "a recent tip's own image was not awaited: $out"
! grep -qF "changes only files" <<<"$out" || die "a recent tip fell back before its checks could appear"
ok "a recent documentation tip waits for its own push before falling back"

note "gate: refusals"
gate_routes "$TMP/r.json" "$CODE|$no_runs|$no_push"
start_api "$TMP/r.json"
run_fail "code commit with no published image" "No push-triggered Docker Push run exists for $CODE" gate "$CODE"
gate_routes "$TMP/r.json" "$CODE|$(ok_runs completed '"success"' 9)|$no_push"
start_api "$TMP/r.json"
run_fail "a pull_request run's merge-commit image does not count" "No push-triggered Docker Push run" gate "$CODE"
no_credential

note "gate: without Actions read access, check suites of main"
gate_routes "$TMP/r.json" "$CODE|$(ok_runs completed '"success"' 7)|$forbidden"
start_api "$TMP/r.json"
expect_out "matched by check suites of main" gate "$CODE"
ok "check suite of main accepted"
PULLS_FROM_MAIN='[{"number": 3}]' gate_routes "$TMP/r.json" "$CODE|$(ok_runs completed '"success"' 7)|$forbidden"
start_api "$TMP/r.json"
run_fail "a pull request from main makes main's checks ambiguous" "has pull requests from main" gate "$CODE"
no_credential

note "gate: explicit images are not verified"
: > "$TMP/api.log"
expect_out "not verified before registration" gate "$CODE" "ghcr.io/azure/osdu-spi-demo:v1.2.3"
[ ! -s "$TMP/api.log" ] || die "gate called GitHub for explicit images"
no_credential
ok "warned, no API call, credential removed"
stop_api

# ---------------------------------------------------------------- NOTICE download

fetch() {
  rm -rf "$TMP/notice"
  NOTICE_OUT="$TMP/notice" CG_SCAN_PHASE="Register shipped components" SYSTEM_ACCESSTOKEN=ado-tok \
    SYSTEM_TEAMPROJECTID=proj1 BUILD_REPOSITORY_NAME="$REPO" BUILD_BUILDID=100 SYSTEM_COLLECTIONID=coll1 \
    SYSTEM_DEFINITIONID=12 CG_POLL_ATTEMPTS=3 SYSTEM_COLLECTIONURI="$API/org/" python3 "$CG/fetch_notice.py"
}
snapshot() {  # build of the scan job's snapshot; other definitions and jobs never match
  printf '{"status": 200, "json": {"value": [{"moniker": "refs/heads/main", "snapshotTypes": [
    {"typeId": 9, "buildType": "vsts://coll1/proj1/12/x", "phaseDisplayName": "Register shipped components", "latestScanBuildIdentifier": "%s"},
    {"typeId": 8, "buildType": "vsts://coll1/proj1/13/x", "phaseDisplayName": "Register shipped components", "latestScanBuildIdentifier": "100"},
    {"typeId": 10, "buildType": "vsts://coll1/proj1/12/x", "phaseDisplayName": "Generate NOTICE from Component Governance", "latestScanBuildIdentifier": "100"}]}]}}' "$1"
}
notice_routes() {  # branches-responses scan-log
  cat > "$TMP/r.json" <<EOF
[{"method": "GET", "path": "/org/_apis/resourceareas/7136235f-d277-4c27-9194-e3ada05fea2c.*",
  "responses": [{"status": 200, "json": {"locationUrl": "{base}/gov/"}}]},
 {"method": "GET", "path": "/gov/proj1/_apis/componentgovernance/governedrepositories.api-version=7.1-preview.1",
  "responses": [{"status": 200, "json": {"value": [{"id": 5, "name": "azure/osdu-spi-demo"}]}}]},
 {"method": "GET", "path": "/gov/proj1/_apis/componentgovernance/governedrepositories/5/branches.*", "responses": [$1]},
 {"method": "GET", "path": "/gov/proj1/_apis/componentgovernance/governedrepositories/5/Notice.snapshotTypeId=9&.*",
  "responses": [{"status": 200, "json": {"content": "NOTICES\r\n---------------------------------------------------------\r\nfoo 1.0 - MIT\r\n",
    "excludedComponents": {"noDefinition": ["maven/mavencentral/com.azure/azure-core/1.60.0"], "notSupported": [{"displayName": "openssl", "displayVersion": "3.3"}]}}}]},
 {"method": "GET", "path": "/org/proj1/_apis/build/builds/100/timeline.*",
  "responses": [{"status": 200, "json": {"records": [{"id": "j1", "type": "Job", "name": "Register shipped components"},
    {"id": "t1", "type": "Task", "parentId": "j1", "name": "Component Detection", "result": "succeeded",
     "task": {"name": "ComponentGovernanceComponentDetection"}, "log": {"url": "{base}/org/proj1/_apis/build/builds/100/logs/7"}}]}}]},
 {"method": "GET", "path": "/org/proj1/_apis/build/builds/100/logs/7", "responses": [{"status": 200, "text": "$2"}]}]
EOF
  start_api "$TMP/r.json"
}

note "notice: this build's snapshot, its NOTICE and the gap report"
notice_routes "$(snapshot 99), $(snapshot 100)" "Detection completed"
fetch > /dev/null
! grep -q $'\r' "$TMP/notice/NOTICE" && grep -qx "foo 1.0 - MIT" "$TMP/notice/NOTICE" || die "NOTICE not written with LF endings"
grep -qF '`com.azure:azure-core:1.60.0`' "$TMP/notice/notice-report.md" || die "gap report misses the noDefinition component"
ok "waited for build 100's scan-job snapshot, ignoring other definitions, jobs and builds"
notice_routes "$(snapshot 100), $(snapshot 101)" "ok"
run_fail "snapshot superseded by a concurrent run" "now belongs to build ['101']" fetch
notice_routes "$(snapshot 100)" 'Processing of image ghcr.io/azure/osdu-spi-demo:sha-0123 (kind \"DockerImage\") failed'
run_fail "an image the scan could not process" "ghcr.io/azure/osdu-spi-demo:sha-0123 could not be scanned" fetch
stop_api

# ---------------------------------------------------------------- NOTICE pull request

ORIGIN="$TMP/origin.git"
git init -q --bare -b main "$ORIGIN"
SEED="$TMP/seed"
git clone -q "$ORIGIN" "$SEED" 2>/dev/null
mkdir -p "$SEED/.github"
printf 'Upstream FOSSA notice\n' > "$SEED/NOTICE"
cat > "$SEED/.github/upstream-filter.yml" <<'EOF'
# Per-service upstream filter config (ADR-038).
service: demo

top_level:
  LICENSE: keep
  NOTICE: keep
  pom.xml: keep

expected_kept:
  - pom.xml
EOF
git -C "$SEED" add -A && git -C "$SEED" commit -qm "chore: fork" && git -C "$SEED" push -q origin main
MAIN=$(git -C "$SEED" rev-parse HEAD)
mkdir -p "$TMP/gen"
printf 'Generated NOTICE\n' > "$TMP/gen/NOTICE"
printf '## Component Governance NOTICE\n\nreport body\n' > "$TMP/gen/notice-report.md"
HEAD_BRANCH="chore/notice-refresh/main"
BOT="osdu-spi-component-governance@users.noreply.github.com"

pr_routes() {  # open-pulls compare-status
  cat > "$TMP/r.json" <<EOF
[{"method": "GET", "path": "/repos/$REPO/pulls.head=Azure%3Achore%2Fnotice-refresh%2Fmain&base=main&state=open",
  "responses": [{"status": 200, "json": $1}]},
 {"method": "POST", "path": "/repos/$REPO/pulls",
  "responses": [{"status": 201, "json": {"number": 1, "html_url": "https://github.com/$REPO/pull/1", "user": {"login": "azure-pipelines[bot]"}}}]},
 {"method": "PATCH", "path": "/repos/$REPO/pulls/1",
  "responses": [{"status": 200, "json": {"number": 1, "html_url": "https://github.com/$REPO/pull/1", "user": {"login": "azure-pipelines[bot]"}}}]},
 {"method": "GET", "path": "/repos/$REPO/compare/.*", "responses": [{"status": 200, "json": {"status": "${2:-ahead}"}}]}]
EOF
  start_api "$TMP/r.json"
}
refresh() {  # source-commit build-id
  local w="$TMP/work"
  rm -rf "$w" && git clone -q "$ORIGIN" "$w" 2>/dev/null && git -C "$w" checkout -q "$1"
  git -C "$w" config --local http.https://github.com/.extraheader "$TOKEN_HEADER"
  (cd "$w" && NOTICE_OUT="$TMP/gen" BUILD_SOURCESDIRECTORY="$w" BUILD_REPOSITORY_NAME="$REPO" BUILD_SOURCEBRANCH=refs/heads/main \
    BUILD_SOURCEVERSION="$1" BUILD_BUILDID="$2" SYSTEM_COLLECTIONURI=https://dev.azure.com/org/ SYSTEM_TEAMPROJECT=OSDU-SPI \
    GITHUB_API_URL="$API" python3 "$CG/notice_pr.py")
}
tip_trailer() { git -C "$ORIGIN" log -1 --format="%(trailers:key=$1,valueonly)" "$HEAD_BRANCH" | tr -d '\n'; }
request_body() { python3 -c "
import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r['method'] == sys.argv[2]:
        print(r['body']['body'] if sys.argv[3] == 'body' else r['body'].get(sys.argv[3]))
" "$TMP/api.log" "$1" "$2"; }

note "notice PR: first refresh replaces NOTICE and cuts NOTICE over to the fork"
pr_routes '[]'
expect_out "opened pull request #1" refresh "$MAIN" 100
[ "$(git -C "$ORIGIN" show "$HEAD_BRANCH:NOTICE")" = "Generated NOTICE" ] || die "NOTICE not replaced"
[ "$(git -C "$ORIGIN" diff --name-only "main..$HEAD_BRANCH" | tr '\n' ' ')" = ".github/upstream-filter.yml NOTICE " ] \
  || die "refresh changed more than NOTICE and the filter verdict"
[ "$(git -C "$ORIGIN" diff -U0 "main..$HEAD_BRANCH" -- .github/upstream-filter.yml | grep '^[-+] ' | tr '\n' '|')" = "-  NOTICE: keep|+  NOTICE: strip|" ] \
  || die "filter verdict not flipped exactly"
[ "$(git -C "$ORIGIN" log -1 --format='%ae %ce' "$HEAD_BRANCH")" = "$BOT $BOT" ] || die "refresh not authored by the automation"
[ "$(tip_trailer Source-Commit) $(tip_trailer Build-Id)" = "$MAIN 100" ] || die "trailers missing"
! git -C "$ORIGIN" log -1 --format=%B "$HEAD_BRANCH" | grep -qF "[skip ci]" || die "refresh skips CI"
[ "$(request_body POST draft) $(request_body POST head) $(request_body POST base)" = "True $HEAD_BRANCH main" ] || die "draft PR fields wrong"
request_body POST body | grep -qF "One-time cutover: NOTICE becomes fork-owned" || die "cutover not explained"
request_body POST body | grep -qF "add the \`port\` label" || die "port label not requested"
request_body POST body | grep -qF "report body" || die "gap report not in the PR body"
ok "draft PR with NOTICE, the strip verdict, trailers and cutover steps"

note "notice PR: only a newer source or a later build replaces the branch"
pr_routes '[{"number": 1}]'
expect_out "updated pull request #1" refresh "$MAIN" 101
[ "$(tip_trailer Build-Id)" = 101 ] || die "later build did not replace the branch"
run_fail "an earlier build of the same commit" "was refreshed by build 101, not older than this build 100" refresh "$MAIN" 100
git -C "$SEED" commit -q --allow-empty -m "feat: next" && git -C "$SEED" push -q origin main
NEXT=$(git -C "$SEED" rev-parse HEAD)
pr_routes '[{"number": 1}]' behind
run_fail "a source commit the branch's source is not behind" "(compare: behind); not replacing it" refresh "$NEXT" 50
pr_routes '[{"number": 1}]' ahead
refresh "$NEXT" 50 > /dev/null
[ "$(tip_trailer Source-Commit)" = "$NEXT" ] || die "newer source did not replace the branch"
ok "later build and newer source replace; older ones are refused"

note "notice PR: branches this automation does not own"
git -C "$SEED" fetch -q origin "$HEAD_BRANCH" && git -C "$SEED" checkout -q -B foreign FETCH_HEAD
git -C "$SEED" commit -q --allow-empty -m "fix: by hand"
git -C "$SEED" push -q -f origin "foreign:$HEAD_BRANCH"
run_fail "a human commit on the refresh branch" "has commits from someone else" refresh "$NEXT" 60
git -C "$SEED" checkout -q -B foreign "$NEXT"
GIT_AUTHOR_EMAIL="$BOT" GIT_COMMITTER_EMAIL="$BOT" git -C "$SEED" commit -q --allow-empty -m "chore: no trailers"
git -C "$SEED" push -q -f origin "foreign:$HEAD_BRANCH"
run_fail "a refresh without trailers" "has no Source-Commit/Build-Id trailers" refresh "$NEXT" 60
git -C "$ORIGIN" update-ref -d "refs/heads/$HEAD_BRANCH"

note "notice PR: after the cutover"
git -C "$SEED" checkout -q main
sed -i 's/  NOTICE: keep/  NOTICE: strip/' "$SEED/.github/upstream-filter.yml"
printf 'Older generated NOTICE\n' > "$SEED/NOTICE"
git -C "$SEED" commit -qam "chore(notice): cut over" && git -C "$SEED" push -q origin main
CUT=$(git -C "$SEED" rev-parse HEAD)
pr_routes '[]'
refresh "$CUT" 70 > /dev/null
[ "$(git -C "$ORIGIN" diff --name-only "main..$HEAD_BRANCH")" = NOTICE ] || die "refresh after the cutover touched the filter"
! request_body POST body | grep -qF "One-time cutover" || die "cutover explained again after it happened"
ok "a fork-owned NOTICE refreshes alone"
stop_api

# ---------------------------------------------------------------- invariants

note "invariants: the gate, Validation, sync and the pipeline agree"
python3 - "$ROOT" <<'PY' || die "the gate's ignored paths differ from validate.yml's push paths-ignore"
import importlib.util, re, sys
root = sys.argv[1]
lines = open(f"{root}/.github/template-workflows/validate.yml").read().splitlines()
start = lines.index("  push:")
block = lines[start + 1:]
i = next(n for n, l in enumerate(block) if l.strip() == "paths-ignore:")
patterns = []
for l in block[i + 1:]:
    m = re.fullmatch(r"\s+- '([^']+)'", l)
    if not m:
        break
    patterns.append(m.group(1))
spec = importlib.util.spec_from_file_location("w", f"{root}/.github/actions/component-governance/wait_images.py")
mod = importlib.util.module_from_spec(spec)
sys.path.insert(0, f"{root}/.github/actions/component-governance")
spec.loader.exec_module(mod)
assert tuple(patterns) == mod.VALIDATION_IGNORED, (patterns, mod.VALIDATION_IGNORED)
assert "NOTICE" not in patterns, "a NOTICE refresh must publish the image that ships it"
g = mod.glob_re
assert g("**.md").fullmatch("a/b/c.md") and g("**.md").fullmatch("README.md")
assert g(".github/*.json").fullmatch(".github/x.json") and not g(".github/*.json").fullmatch(".github/a/x.json")
assert g(".github/actions/**").fullmatch(".github/actions/a/b.py") and not g("LICENSE").fullmatch("LICENSE.txt")
PY
ok "gate skips exactly the pushes Validation ignores, and NOTICE is validated"
python3 - "$ROOT/.github/sync-config.json" <<'PY' || die "sync-config.json does not sync the pipeline"
import json, sys
assert ".azuredevops/component-governance.yml" in [f["path"] for f in json.load(open(sys.argv[1]))["sync_rules"]["files"]]
PY
ok "the pipeline is a synced file"
for s in $(grep -o '\$CG_SCRIPTS/[a-z_]*\.py' "$PIPELINE" | sort -u); do
  [ -f "$CG/${s#\$CG_SCRIPTS/}" ] || die "pipeline runs missing script $s"
done
grep -qxF '    value: .github/actions/component-governance' "$PIPELINE" || die "CG_SCRIPTS does not name this action"
grep -qF 'sparseCheckoutPatterns: /NOTICE /.github/upstream-filter.yml /.github/actions/component-governance/' "$PIPELINE" \
  || die "the NOTICE job does not check out its scripts and the files it changes"
grep -qF 'displayName: ${{ variables.CG_SCAN_PHASE }}' "$PIPELINE" || die "scan job is not named by CG_SCAN_PHASE"
ok "every script the pipeline runs exists and the NOTICE job checks it out"

printf '\nAll component governance checks passed.\n'
