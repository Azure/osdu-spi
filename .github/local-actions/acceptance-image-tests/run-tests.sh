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
[ "$(output_value "$TMP/out2.txt" buildable)" = "true" ] || die "override suite must be buildable"
ok "descriptor override honored"

note "clean skip: an absent suite directory is not an error"
WS3="$TMP/ws-absent"
mkdir -p "$WS3"
resolve_suite "$WS3" "$TMP/out3.txt" SERVICE_NAME=demo >/dev/null
[ "$(output_value "$TMP/out3.txt" buildable)" = "false" ] || die "absent suite must not be buildable"
output_value "$TMP/out3.txt" reason | grep -q "demo-acceptance-test" || die "skip reason must name the directory"
ok "clean skip with reason"

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

note "Dockerfile contract: suite arg, entrypoint, argv default"
grep -q '^ARG SUITE_DIR$' "$DOCKERFILE" || die "SUITE_DIR build arg missing"
grep -q 'acceptance-entrypoint.sh' "$DOCKERFILE" || die "entrypoint not baked"
grep -q '^CMD \["verify"\]$' "$DOCKERFILE" || die "default command must be verify"
grep -q 'dependency:go-offline' "$DOCKERFILE" || die "dependencies must be pre-resolved at build"
grep -q 'linux/amd64' "$HERE/../../actions/acceptance-image/action.yml" || die "amd64-only platform lost"
head -1 "$ENTRYPOINT" | grep -q '^#!/bin/sh' || die "entrypoint must be POSIX sh"
grep -q 'exec mvn' "$ENTRYPOINT" || die "entrypoint must exec maven with argv"
ok "Dockerfile and entrypoint contract"

note "build context: the sidecar ignore file overrides the upstream .dockerignore"
IGNORE="${DOCKERFILE}.dockerignore"
[ -f "$IGNORE" ] || die "missing ${IGNORE##*/}: forks inherit an upstream .dockerignore excluding .*, which strips .mvn"
if grep -qE '^[[:space:]]*(\.\*|\.mvn)' "$IGNORE"; then
  die "sidecar ignore must keep .mvn — the suite pom resolves \${repo.releases.url} from the community settings"
fi
ok "sidecar dockerignore present and keeps .mvn"

printf '\nAll acceptance image harness checks passed.\n'
