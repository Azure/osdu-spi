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
# Fixture harness for the acceptance-image action's suite resolution and the
# canonical acceptance Dockerfile's contract. No Docker daemon; only loopback network.
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
TMP="$(cd "$(mktemp -d)" && pwd -P)"
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

note "clean skip: a deploy-only descriptor builds no acceptance image"
WS3D="$TMP/ws-deploy-only"
mkdir -p "$WS3D/.spi"
cat > "$WS3D/.spi/service.yaml" <<'EOF'
schemaVersion: 3
service: { name: demo, archetype: java-maven-azure }
tests: {}
EOF
resolve_suite "$WS3D" "$TMP/out3d.txt" SERVICE_NAME=demo >/dev/null
[ "$(output_value "$TMP/out3d.txt" buildable)" = "false" ] || die "deploy-only descriptor must not be buildable"
output_value "$TMP/out3d.txt" reason | grep -q "deploy only" || die "skip reason must say deploy only"
ok "deploy-only skip with reason"

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
grep -q 'dependency:resolve dependency:resolve-plugins' "$DOCKERFILE" || die "dependencies must be pre-resolved at build"
! grep -q 'dependency:go-offline' "$DOCKERFILE" || die "go-offline resolves artifacts the build never uses"
grep -q 'install -DskipTests -DskipITs' "$DOCKERFILE" || die "a reactor suite must be installed, without running its suites, so sibling modules resolve"
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

note "verdict: reports decide, not the exit code or the console"
VERDICT="$HERE/../../actions/acceptance-image/suite-verdict.py"
report() {  # dir tests skipped failures errors
  mkdir -p "$1"
  printf '<?xml version="1.0"?><testsuite name="t" tests="%s" skipped="%s" failures="%s" errors="%s"/>\n' "$2" "$3" "$4" "$5" > "$1/TEST-t.xml"
}
verdict() {  # exit-code reports-dir -> prints line, returns script status
  python3 "$VERDICT" --exit-code "$1" --reports "$2"
}
V="$TMP/verdict"
report "$V/pass/target/surefire-reports" 3 1 0 0
OUT="$(verdict 0 "$V/pass")" || die "a zero exit with tests run must pass: $OUT"
[[ "$OUT" == "pass: 2 tests, 1 skipped" ]] || die "pass line wrong: $OUT"
report "$V/nested/mod-azure/target/failsafe-reports" 2 0 0 0
verdict 0 "$V/nested" >/dev/null || die "reports in a submodule's failsafe dir must count"
report "$V/skipped/target/surefire-reports" 1 1 0 0
OUT="$(verdict 0 "$V/skipped" || true)"
verdict 0 "$V/skipped" >/dev/null && die "all tests skipped must not pass"
[[ "$OUT" == FAIL:*"no tests executed"* ]] || die "skipped verdict wrong: $OUT"
report "$V/ignored/target/surefire-reports" 1 0 1 0
verdict 0 "$V/ignored" >/dev/null && die "a failure under a zero exit (failure.ignore) must not pass"
mkdir -p "$V/empty"
verdict 0 "$V/empty" >/dev/null && die "no reports at all must not pass"
report "$V/nonzero/target/surefire-reports" 5 0 0 0
verdict 1 "$V/nonzero" >/dev/null && die "a nonzero exit must fail even with green reports"
OUT="$(verdict 124 "$V/nonzero" || true)"
[[ "$OUT" == FAIL:*"timed out"* ]] || die "exit 124 must read as a timeout: $OUT"
mkdir -p "$V/stray/target/other"; report "$V/stray/target/other" 9 0 0 0
verdict 0 "$V/stray" >/dev/null && die "TEST-*.xml outside a surefire or failsafe dir must not count"
ok "suite verdict"

note "forward trust store: only the served CA is imported, through the image's keytool"
TRUSTSTORE="$HERE/../../actions/acceptance-image/forward-truststore.sh"
F="$TMP/forward"
mkdir -p "$F/bin"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$F/ca.key" -out "$F/ca.pem" -days 1 -subj "/CN=forward-ca" 2>/dev/null
leaf() {  # name subject: a leaf signed by the forward CA
  openssl req -newkey rsa:2048 -nodes -keyout "$F/$1.key" -out "$F/$1.csr" -subj "$2" 2>/dev/null
  openssl x509 -req -in "$F/$1.csr" -CA "$F/ca.pem" -CAkey "$F/ca.key" -CAcreateserial -out "$F/$1.pem" -days 1 2>/dev/null
}
leaf leaf "/CN=localhost"
leaf decoy "/CN=CA:TRUE"
# The suite image's in-container script runs against the host JDK, with /trust mapped to the mount.
HOST_JAVA_HOME="${JAVA_HOME:-$(java -XshowSettings:properties -version 2>&1 | awk '/java.home =/ { print $3 }')}"
cat > "$F/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "${0##*/} $*" > "$FORWARD_DOCKER_LOG"
while [ $# -gt 0 ]; do
  case "$1" in
    -v) dir="${2%%:*}"; shift ;;
    -c) script="$2"; shift ;;
  esac
  shift
done
JAVA_HOME="$HOST_JAVA_HOME" sh -c "$script" sh "$dir"
STUB
chmod +x "$F/bin/docker"
cp "$F/bin/docker" "$F/bin/podman"
serve() {  # port cert [chain] -> server pid in SERVER, waits until it listens
  local chain=()
  [ -z "${3:-}" ] || chain=(-cert_chain "$3")
  openssl s_server -accept "$1" -cert "$2" -key "${2%.pem}.key" ${chain[@]+"${chain[@]}"} -quiet >/dev/null 2>&1 &
  SERVER=$!
  for _ in $(seq 1 25); do (exec 3<> "/dev/tcp/127.0.0.1/$1") 2>/dev/null && return; sleep 0.2; done
}
stop() { { kill "$SERVER"; wait "$SERVER"; } 2>/dev/null || true; }
truststore() {  # out-dir port -> script status
  PATH="$F/bin:$PATH" FORWARD_DOCKER_LOG="$F/docker.log" HOST_JAVA_HOME="$HOST_JAVA_HOME" \
    bash "$TRUSTSTORE" img "$1" "$2" >/dev/null 2>&1
}
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
[ -x "$HOST_JAVA_HOME/bin/keytool" ] || die "the trust store check needs a JDK keytool (JAVA_HOME=$HOST_JAVA_HOME)"

PORT="$(free_port)"
serve "$PORT" "$F/leaf.pem" "$F/ca.pem"
truststore "$F/out" "$PORT" || { stop; die "a TLS forward serving a CA must build a store"; }
stop
CAS=("$F/out"/ca-*.pem)
[ "${#CAS[@]}" -eq 1 ] || die "exactly the CA must be imported, got ${#CAS[@]}"
cmp -s "${CAS[0]}" "$F/ca.pem" || die "the imported certificate is not the served CA"
grep -q -- "--entrypoint sh -v $F/out:/trust img" "$F/docker.log" || die "keytool must run in the suite image: $(cat "$F/docker.log")"
list() { "$HOST_JAVA_HOME/bin/keytool" -list -keystore "$1" -storepass changeit "${@:2}" 2>/dev/null; }
list "$F/out/cacerts" -alias "${CAS[0]##*/}" >/dev/null || die "the forwarded CA is not in the store"
ROOT="$(list "$HOST_JAVA_HOME/lib/security/cacerts" | awk -F, '/trustedCertEntry/ { print $1; exit }')"
[ -n "$ROOT" ] && list "$F/out/cacerts" -alias "$ROOT" >/dev/null || die "the image's own roots must stay trusted ($ROOT)"

PORT="$(free_port)"
serve "$PORT" "$F/decoy.pem"
RC=0; truststore "$F/decoy-out" "$PORT" || RC=$?
stop
[ "$RC" -eq 1 ] || die "a leaf whose subject reads CA:TRUE must not be trusted, got $RC"

mkdir -p "$F/stale"
cp "$F/ca.pem" "$F/stale/chain-$PORT-1.pem"
RC=0; truststore "$F/stale" "$PORT" || RC=$?
[ "$RC" -eq 1 ] || die "a chain left by an earlier run must not be imported, got $RC"
[ -z "$(find "$F/stale" -name 'ca-*.pem')" ] || die "a stale chain was promoted to a CA"

RC=0; truststore "$F/bad" "9200;x" || RC=$?
[ "$RC" -eq 1 ] || die "a non-numeric port must exit 1, got $RC"

PORT="$(free_port)"
serve "$PORT" "$F/leaf.pem" "$F/ca.pem"
RC=0
(cd "$F" && CONTAINER_ENGINE=podman truststore rel-out "$PORT") || RC=$?
stop
[ "$RC" -eq 0 ] || die "a relative out-dir under CONTAINER_ENGINE=podman must build a store, got $RC"
grep -q -- "^podman run .* -v $F/rel-out:/trust img" "$F/docker.log" \
  || die "CONTAINER_ENGINE must run the image with an absolute mount: $(cat "$F/docker.log")"
[ -s "$F/rel-out/cacerts" ] || die "the relative out-dir store was not written"

PORT="$(free_port)"
serve "$PORT" "$F/leaf.pem" "$F/ca.pem"
rm -f "$F/docker.log"
RC=0
PATH="$F/bin:$PATH" FORWARD_DOCKER_LOG="$F/docker.log" JAVA_HOME="$HOST_JAVA_HOME" \
  bash "$TRUSTSTORE" --host-jdk "$F/host-out" "$PORT" >/dev/null 2>&1 || RC=$?
NOJDK=0
PATH="$F/bin:$PATH" JAVA_HOME="$F/no-jdk" bash "$TRUSTSTORE" --host-jdk "$F/nojdk-out" "$PORT" >/dev/null 2>"$F/nojdk.err" || NOJDK=$?
mkdir -p "$F/nojava"
for tool in openssl awk seq sleep mkdir rm mv cat; do ln -sf "$(command -v "$tool")" "$F/nojava/$tool"; done
NOJAVA=0
env -u JAVA_HOME PATH="$F/nojava" "$(command -v bash)" "$TRUSTSTORE" --host-jdk "$F/nojava-out" "$PORT" >/dev/null 2>"$F/nojava.err" || NOJAVA=$?
REL=0
(cd "$F" && mkdir -p cdpath-target && CDPATH="$F/elsewhere:." PATH="$F/bin:$PATH" FORWARD_DOCKER_LOG="$F/cdpath.log" \
  HOST_JAVA_HOME="$HOST_JAVA_HOME" bash "$TRUSTSTORE" img cdpath-target "$PORT" >/dev/null 2>&1) || REL=$?
stop
[ "$RC" -eq 0 ] || die "--host-jdk must build a store, got $RC"
[ "$NOJDK" -eq 1 ] && grep -q "no host JDK keytool" "$F/nojdk.err" || die "--host-jdk without a JDK must name it, got $NOJDK"
[ "$NOJAVA" -eq 1 ] && grep -q "no host JDK keytool" "$F/nojava.err" || die "--host-jdk with no java on PATH must name it, got $NOJAVA"
[ "$REL" -eq 0 ] && [ -s "$F/cdpath-target/cacerts" ] || die "CDPATH must not redirect a relative out-dir, got $REL"
[ ! -e "$F/docker.log" ] || die "--host-jdk must not start a container: $(cat "$F/docker.log")"
HOST_CAS=("$F/host-out"/ca-*.pem)
list "$F/host-out/cacerts" -alias "${HOST_CAS[0]##*/}" >/dev/null || die "--host-jdk did not import the forwarded CA"
list "$F/host-out/cacerts" -alias "$ROOT" >/dev/null || die "--host-jdk lost the host JDK's own roots"
ok "forward trust store"

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
