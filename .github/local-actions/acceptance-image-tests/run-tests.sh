#!/usr/bin/env bash
#
# Fixture harness for the acceptance-image action's suite resolution and the
# canonical acceptance Dockerfile's contract. No Docker daemon, no network.
# Fails fast: the first broken assertion stops the run with a non-zero exit.
#
# Usage:
#   ./run-tests.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_SUITE="$HERE/../../actions/acceptance-image/resolve-suite.sh"
RESOLVER="$HERE/../../actions/acceptance-resolver/resolve.py"
DOCKERFILE="$HERE/../../../build/acceptance.Dockerfile"
ENTRYPOINT="$HERE/../../../build/acceptance-entrypoint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note()  { printf '\n== %s\n' "$*"; }
die()   { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()    { printf 'ok: %s\n' "$*"; }

output_value() {
  local file="$1" name="$2"
  grep "^${name}=" "$file" | head -1 | cut -d= -f2-
}

resolve_suite() {
  local workspace="$1" out="$2"
  shift 2
  (cd "$workspace" && env "$@" RESOLVER="$RESOLVER" GITHUB_OUTPUT="$out" "$RESOLVE_SUITE")
}


note "default: the upstream <service>-acceptance-test module"
WS1="$TMP/ws-default"
mkdir -p "$WS1/demo-acceptance-test"
resolve_suite "$WS1" "$TMP/out1.txt" SERVICE_NAME=demo >/dev/null
[ "$(output_value "$TMP/out1.txt" suite_dir)" = "demo-acceptance-test" ] || die "default suite dir wrong"
[ "$(output_value "$TMP/out1.txt" buildable)" = "true" ] || die "default suite must be buildable"
ok "default module selected"

note "descriptor override: tests.acceptance.path wins"
WS2="$TMP/ws-descriptor"
mkdir -p "$WS2/.spi" "$WS2/custom-tests"
cat > "$WS2/.spi/service.yaml" <<'EOF'
schemaVersion: 3
service: { name: demo, archetype: java-maven-azure }
tests:
  acceptance:
    type: maven
    path: custom-tests
EOF
resolve_suite "$WS2" "$TMP/out2.txt" SERVICE_NAME=demo >/dev/null
[ "$(output_value "$TMP/out2.txt" suite_dir)" = "custom-tests" ] || die "descriptor override lost"
[ "$(output_value "$TMP/out2.txt" suite_dirs)" = "custom-tests" ] || die "single suite must list itself"
[ "$(output_value "$TMP/out2.txt" buildable)" = "true" ] || die "override suite must be buildable"
ok "descriptor override honored"

note "named suites: every declared path is baked, acceptance first"
WS2B="$TMP/ws-suites"
mkdir -p "$WS2B/.spi" "$WS2B/demo-acceptance-test" "$WS2B/testing"
cat > "$WS2B/.spi/service.yaml" <<'EOF'
schemaVersion: 3
service: { name: demo, archetype: java-maven-azure }
tests:
  integration:
    type: maven
    path: testing
  acceptance:
    type: maven
    path: demo-acceptance-test
EOF
resolve_suite "$WS2B" "$TMP/out2b.txt" SERVICE_NAME=demo >/dev/null
[ "$(output_value "$TMP/out2b.txt" suite_dir)" = "demo-acceptance-test" ] || die "acceptance must be the default suite"
[ "$(output_value "$TMP/out2b.txt" suite_dirs)" = "demo-acceptance-test testing" ] || die "suite_dirs must list acceptance first"
rmdir "$WS2B/testing"
RC=0
resolve_suite "$WS2B" "$TMP/out2c.txt" SERVICE_NAME=demo >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || die "a declared suite that is absent must exit 2, got $RC"
ok "named suites resolved"

note "clean skip: an absent suite directory is not an error"
WS3="$TMP/ws-absent"
mkdir -p "$WS3"
resolve_suite "$WS3" "$TMP/out3.txt" SERVICE_NAME=demo >/dev/null
[ "$(output_value "$TMP/out3.txt" buildable)" = "false" ] || die "absent suite must not be buildable"
output_value "$TMP/out3.txt" reason | grep -q "demo-acceptance-test" || die "skip reason must name the directory"
ok "clean skip with reason"

note "halt: a descriptor naming an absent suite is a typo, not an empty fork"
WS3B="$TMP/ws-descriptor-absent"
mkdir -p "$WS3B/.spi" "$WS3B/demo-acceptance-test"
cat > "$WS3B/.spi/service.yaml" <<'EOF'
schemaVersion: 3
service: { name: demo, archetype: java-maven-azure }
tests:
  acceptance:
    type: maven
    path: demo-acceptance-tset
EOF
RC=0
resolve_suite "$WS3B" "$TMP/out3b.txt" SERVICE_NAME=demo >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || die "descriptor-named absent suite must exit 2, got $RC"
ok "descriptor path is an assertion, not a hint"

note "halt: a broken descriptor fails the build, never a guess"
WS4="$TMP/ws-broken"
mkdir -p "$WS4/.spi" "$WS4/demo-acceptance-test"
cat > "$WS4/.spi/service.yaml" <<'EOF'
schemaVersion: 3
service: { name: demo, archetype: java-maven-azure }
tests:
  acceptance:
    type: maven
    path: demo-acceptance-test
    bindings:
      X: { source: cosmos }
EOF
RC=0
resolve_suite "$WS4" "$TMP/out4.txt" SERVICE_NAME=demo >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || die "broken descriptor must propagate exit 2, got $RC"
ok "engine halt propagates"

note "guard: SERVICE_NAME is required"
RC=0
env -u SERVICE_NAME GITHUB_OUTPUT="$TMP/out5.txt" "$RESOLVE_SUITE" >/dev/null 2>&1 || RC=$?
[ "$RC" -ne 0 ] || die "missing SERVICE_NAME must fail"
ok "missing SERVICE_NAME fails"

note "Dockerfile contract: suite paths, select stage, entrypoint, argv default"
grep -q '^ARG SUITE_DIRS$' "$DOCKERFILE" || die "SUITE_DIRS build arg missing"
grep -q 'SUITE_DIRS=${{ steps.suite.outputs.suite_dirs }}' "$HERE/../../actions/acceptance-image/action.yml" || die "action must pass every suite path"
grep -q ' AS select$' "$DOCKERFILE" || die "select stage missing: the service source must not reach the image"
grep -q '^COPY --from=select /suite/ /suite/$' "$DOCKERFILE" || die "maven stage must copy only the selected suites"
grep -q '/suite/.default-suite-dir' "$DOCKERFILE" || die "the default suite must be recorded for the entrypoint"
grep -qF 'cp -R "/src/$dir/." "/suite/$dir/"' "$DOCKERFILE" || die "select stage must copy suite contents into the destination, not nest under it"
grep -q 'acceptance-entrypoint.sh' "$DOCKERFILE" || die "entrypoint not baked"
grep -q '^CMD \["verify"\]$' "$DOCKERFILE" || die "default command must be verify"
grep -q 'dependency:go-offline' "$DOCKERFILE" || die "dependencies must be pre-resolved at build"
grep -q 'install -DskipTests' "$DOCKERFILE" || die "a reactor suite must be installed so sibling modules resolve"
grep -q 'linux/amd64' "$HERE/../../actions/acceptance-image/action.yml" || die "amd64-only platform lost"
head -1 "$ENTRYPOINT" | grep -q '^#!/bin/sh' || die "entrypoint must be POSIX sh"
grep -q 'exec mvn' "$ENTRYPOINT" || die "entrypoint must exec maven with argv"
grep -q '/suite/.default-suite-dir' "$ENTRYPOINT" || die "entrypoint must default SUITE_DIR from the image"
ok "Dockerfile and entrypoint contract"

note "entrypoint: selects a baked suite and refuses one that is not"
IMG="$TMP/image"
mkdir -p "$IMG/suite/demo-acceptance-test" "$IMG/suite/testing" "$IMG/bin"
printf 'demo-acceptance-test' > "$IMG/suite/.default-suite-dir"
touch "$IMG/suite/demo-acceptance-test/pom.xml" "$IMG/suite/testing/pom.xml"
printf '#!/bin/sh\necho "mvn $PWD $*"\n' > "$IMG/bin/mvn"; chmod +x "$IMG/bin/mvn"
sed "s|/suite|$IMG/suite|g" "$ENTRYPOINT" > "$IMG/entrypoint.sh"; chmod +x "$IMG/entrypoint.sh"
OUT="$(PATH="$IMG/bin:$PATH" "$IMG/entrypoint.sh" verify 2>/dev/null)"
[[ "$OUT" == "mvn $IMG/suite/demo-acceptance-test -B --no-transfer-progress verify" ]] || die "default suite not selected: $OUT"
OUT="$(SUITE_DIR=testing PATH="$IMG/bin:$PATH" "$IMG/entrypoint.sh" -pl x test 2>/dev/null)"
[[ "$OUT" == "mvn $IMG/suite/testing -B --no-transfer-progress -pl x test" ]] || die "SUITE_DIR not honored: $OUT"
RC=0
SUITE_DIR=nope PATH="$IMG/bin:$PATH" "$IMG/entrypoint.sh" verify >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || die "an unbaked SUITE_DIR must exit 2, got $RC"
ok "entrypoint suite selection"

note "build context: the sidecar ignore file overrides the upstream .dockerignore"
IGNORE="${DOCKERFILE}.dockerignore"
[ -f "$IGNORE" ] || die "missing ${IGNORE##*/}: forks inherit an upstream .dockerignore excluding .*, which strips .mvn"
if grep -qE '^[[:space:]]*(\.\*|\.mvn)' "$IGNORE"; then
  die "sidecar ignore must keep .mvn — the suite pom resolves \${repo.releases.url} from the community settings"
fi
ok "sidecar dockerignore present and keeps .mvn"

note "root .mvn is optional: the settings-less path must stay reachable"
grep -q 'if \[ -d /src/.mvn \]' "$DOCKERFILE" || die "the select stage must tolerate a fork without .mvn"
grep -q 'if \[ -f /suite/.mvn/community-maven.settings.xml \]' "$DOCKERFILE" || die "settings must be optional at prewarm"
ok "optional .mvn keeps the fallback live"

note "a suiteless fork skips before the push path demands a token"
ACTION="$HERE/../../actions/acceptance-image/action.yml"
suite_at="$(grep -n 'id: suite' "$ACTION" | head -1 | cut -d: -f1)"
gate_at="$(grep -n 'Validate push prerequisites' "$ACTION" | head -1 | cut -d: -f1)"
[ -n "$suite_at" ] && [ -n "$gate_at" ] || die "suite resolution or push gate step missing"
[ "$gate_at" -gt "$suite_at" ] || die "push validation must follow suite resolution, or push=true breaks the documented clean skip"
grep -qF "buildable == 'true' && inputs.push == 'true'" "$ACTION" || die "push gate must also require a buildable suite"
ok "push token requirement gated on a buildable suite"

printf '\nAll acceptance image harness checks passed.\n'
