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
# Fixture harness for the load-image action's payload resolution, the canonical
# load Dockerfile's contract, and the entrypoint's control flow. No Docker daemon,
# no network. Fails fast: the first broken assertion stops the run with a
# non-zero exit.
#
# Usage:
#   ./run-tests.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="$HERE/../../actions/load-image"
RESOLVE="$ACTION_DIR/resolve-payload.sh"
DOCKERFILE="$HERE/../../../build/load.Dockerfile"
IGNORE="${DOCKERFILE}.dockerignore"
ENTRYPOINT="$HERE/../../../build/load-entrypoint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note()  { printf '\n== %s\n' "$*"; }
die()   { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()    { printf 'ok: %s\n' "$*"; }

output_value() {
  local file="$1" name="$2"
  grep "^${name}=" "$file" | head -1 | cut -d= -f2-
}

resolve() {
  local workspace="$1" out="$2"
  (cd "$workspace" && GITHUB_OUTPUT="$out" "$RESOLVE")
}

plant_loader() {
  mkdir -p "$1/deployments/scripts"
  touch "$1/deployments/scripts/DeploySharedSchemas.py" "$1/deployments/scripts/Utility.py" "$1/deployments/scripts/requirements.txt"
}


note "clean skip: a fork without the payload is not an error"
WS1="$TMP/ws-none"
mkdir -p "$WS1"
plant_loader "$WS1"
resolve "$WS1" "$TMP/out1.txt" >/dev/null
[ "$(output_value "$TMP/out1.txt" buildable)" = "false" ] || die "absent payload must not be buildable"
output_value "$TMP/out1.txt" reason | grep -q "deployments/shared-schemas" || die "skip reason must name the payload directory"
ok "clean skip with reason"

note "build: payload and loader present"
WS2="$TMP/ws-payload"
mkdir -p "$WS2/deployments/shared-schemas/osdu"
plant_loader "$WS2"
resolve "$WS2" "$TMP/out2.txt" >/dev/null
[ "$(output_value "$TMP/out2.txt" buildable)" = "true" ] || die "payload with loader must be buildable"
[ "$(output_value "$TMP/out2.txt" payload_dir)" = "deployments/shared-schemas" ] || die "payload_dir output wrong"
[ "$(output_value "$TMP/out2.txt" reason)" = "" ] || die "a buildable payload carries no skip reason"
ok "payload resolved"

note "halt: payload present but a loader file missing names the file"
for missing in DeploySharedSchemas.py Utility.py requirements.txt; do
  WS3="$TMP/ws-missing-$missing"
  mkdir -p "$WS3/deployments/shared-schemas"
  plant_loader "$WS3"
  rm "$WS3/deployments/scripts/$missing"
  RC=0
  OUT="$(resolve "$WS3" "$TMP/out3.txt" 2>&1)" || RC=$?
  [ "$RC" -eq 2 ] || die "missing $missing must exit 2, got $RC"
  echo "$OUT" | grep -q "deployments/scripts/$missing" || die "halt must name the missing file: $OUT"
done
ok "missing loader halts with the file named"

note "Dockerfile contract: only the payload and the three loader files enter the image"
grep -q '^COPY deployments/shared-schemas/ deployments/shared-schemas/$' "$DOCKERFILE" || die "payload COPY missing or moved: the loader resolves it relative to deployments/"
grep -q '^COPY deployments/scripts/DeploySharedSchemas.py deployments/scripts/Utility.py deployments/scripts/$' "$DOCKERFILE" || die "loader COPY must name exactly the two upstream modules"
grep -q '^COPY deployments/scripts/requirements.txt deployments/scripts/requirements.txt$' "$DOCKERFILE" || die "requirements COPY missing"
grep -q 'deployments/scripts/azure' "$DOCKERFILE" && die "the Dockerfile must not reference deployments/scripts/azure: upstream deletes it"
grep -q 'load-entrypoint.sh' "$DOCKERFILE" || die "entrypoint not baked"
grep -q '^USER loader$' "$DOCKERFILE" || die "the loader must not run as root"
grep -q '^FROM docker.io/library/python:[0-9.]*-slim@sha256:' "$DOCKERFILE" || die "base image must be a digest-pinned python slim"
grep -q 'linux/amd64,linux/arm64' "$ACTION_DIR/action.yml" || die "push builds must cover both platforms the service image does"
ok "Dockerfile contract"

note "build context: the sidecar ignore file admits only the image inputs"
[ -f "$IGNORE" ] || die "missing ${IGNORE##*/}: forks inherit an upstream .dockerignore, and the payload must not depend on it"
grep -qx '\*' "$IGNORE" || die "sidecar must start from excluding everything"
for allow in '!build/load-entrypoint.sh' '!deployments/scripts/DeploySharedSchemas.py' '!deployments/scripts/Utility.py' '!deployments/scripts/requirements.txt' '!deployments/shared-schemas/'; do
  grep -qxF "$allow" "$IGNORE" || die "sidecar must re-admit $allow"
done
grep -q 'azure' "$IGNORE" && die "sidecar must not admit anything under deployments/scripts/azure"
ok "sidecar dockerignore narrows the context to the image inputs"

note "entrypoint: control flow with a stubbed python3"
head -1 "$ENTRYPOINT" | grep -q '^#!/bin/sh' || die "entrypoint must be POSIX sh"
IMG="$TMP/image"
mkdir -p "$IMG/bin" "$IMG/loader/deployments/scripts"
touch "$IMG/loader/deployments/scripts/DeploySharedSchemas.py"
# The stub answers the /info probe from PROBE, records loader argv, and exits with LOADER_RC
# after printing LOADER_OUT. Heredoc programs (the probe and the token exchange) arrive as
# "python3 -" with the program on stdin; the loader arrives as a path.
cat > "$IMG/bin/python3" <<'STUB'
#!/bin/sh
if [ "$1" = "-" ]; then
  prog=$(cat)
  case "$prog" in
    *urlopen*INFO_URL*) [ "${PROBE:-200}" = "200" ] && exit 0 || exit 1 ;;
    *client_assertion*) echo "exchanged-token"; echo "exchange" >> "$STUB_LOG"; exit 0 ;;
  esac
  exit 99
fi
echo "loader $* auth=$BEARER_TOKEN" >> "$STUB_LOG"
printf '%s\n' "${LOADER_OUT:-All schemas registered}"
exit "${LOADER_RC:-0}"
STUB
chmod +x "$IMG/bin/python3"
run_entrypoint() {  # extra env assignments..., then entrypoint args after --
  : > "$IMG/stub.log"
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  env -u BEARER_TOKEN PATH="$IMG/bin:$PATH" STUB_LOG="$IMG/stub.log" LOADER_HOME="$IMG/loader" TMPDIR="$IMG" \
    WAIT_SECONDS=1 SCHEMA_URL="http://schema.test/api/schema-service/v1/" ${envs[@]+"${envs[@]}"} sh "$ENTRYPOINT" "$@"
}

RC=0; run_entrypoint BEARER_TOKEN=abc -- >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] || die "happy path with BEARER_TOKEN must exit 0, got $RC"
grep -q 'loader .*DeploySharedSchemas.py -u http://schema.test/api/schema-service/v1/schemas/system auth=Bearer abc' "$IMG/stub.log" || die "loader must target /schemas/system with a Bearer-prefixed token: $(cat "$IMG/stub.log")"
grep -q '^exchange' "$IMG/stub.log" && die "BEARER_TOKEN set must skip the token exchange"
ok "BEARER_TOKEN path"

run_entrypoint "BEARER_TOKEN=Bearer xyz" -- -e >/dev/null 2>&1 || die "an already-prefixed token must pass"
grep -q 'schemas/system -e auth=Bearer xyz$' "$IMG/stub.log" || die "extra arguments must reach the loader and the prefix must not double: $(cat "$IMG/stub.log")"
ok "argument pass-through and Bearer prefix"

run_entrypoint -- >/dev/null 2>&1 || die "workload identity path must exit 0"
grep -q '^exchange' "$IMG/stub.log" || die "unset BEARER_TOKEN must exchange the federated token"
grep -q 'auth=Bearer exchanged-token' "$IMG/stub.log" || die "the exchanged token must reach the loader: $(cat "$IMG/stub.log")"
grep -q '/oauth2/token"' "$ENTRYPOINT" || die "the exchange must use the v1 endpoint: the services read appid, which v2 tokens omit"
grep -q '"resource":' "$ENTRYPOINT" || die "the v1 exchange takes a resource, not a scope"
grep -q 'oauth2/v2.0' "$ENTRYPOINT" && die "no v2 endpoint: its tokens omit appid"
ok "workload identity exchange"

RC=0; run_entrypoint BEARER_TOKEN=abc PROBE=503 -- >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 1 ] || die "a service that never answers 200 must exit 1, got $RC"
grep -q '^loader' "$IMG/stub.log" && die "the loader must not run before the service answers"
ok "wait deadline"

RC=0; run_entrypoint BEARER_TOKEN=abc LOADER_RC=1 -- >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 1 ] || die "a loader failure must propagate, got $RC"
ok "loader exit code mapping"

RC=0; env -u SCHEMA_URL PATH="$IMG/bin:$PATH" sh "$ENTRYPOINT" >/dev/null 2>&1 || RC=$?
[ "$RC" -ne 0 ] || die "missing SCHEMA_URL must fail"
ok "SCHEMA_URL required"

note "a payload-less fork skips before the push path demands a token"
ACTION="$ACTION_DIR/action.yml"
payload_at="$(grep -n 'id: payload' "$ACTION" | head -1 | cut -d: -f1)"
gate_at="$(grep -n 'Validate push prerequisites' "$ACTION" | head -1 | cut -d: -f1)"
[ -n "$payload_at" ] && [ -n "$gate_at" ] || die "payload resolution or push gate step missing"
[ "$gate_at" -gt "$payload_at" ] || die "push validation must follow payload resolution, or push=true breaks the documented clean skip"
grep -qF "buildable == 'true' && inputs.push == 'true'" "$ACTION" || die "push gate must also require a buildable payload"
ok "push token requirement gated on a buildable payload"

printf '\nAll load image harness checks passed.\n'
