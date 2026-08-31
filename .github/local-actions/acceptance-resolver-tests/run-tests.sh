#!/usr/bin/env bash
#
# Fixture harness for the acceptance resolver engine.
#
# Drives the closed source vocabulary, the resolution precedence, both modes,
# every typed failure category, and the determinism gate against fixture
# facts envelopes. No cluster, no Azure calls. Fails fast: the first broken
# assertion stops the run with a non-zero exit.
#
# Usage:
#   ./run-tests.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/../../actions/acceptance-resolver/resolve.py"
SCHEMA="$HERE/../../actions/acceptance-resolver/service-descriptor.schema.json"
FIXTURES="$HERE/fixtures"
FACTS="$FIXTURES/info.json"
FACTS_TODAY="$FIXTURES/info-today.json"
DESCRIPTOR="$FIXTURES/service.yaml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note()  { printf '\n== %s\n' "$*"; }
die()   { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()    { printf 'ok: %s\n' "$*"; }

engine() { python3 "$ENGINE" "$@"; }

report_field() {
  python3 -c "import json,sys; print(eval(sys.argv[2], {'r': json.load(open(sys.argv[1]))}))" "$1" "$2"
}

env_value() {
  local file="$1" name="$2"
  grep "^${name}=" "$file" | head -1 | cut -d= -f2-
}

SECRETS="$TMP/secrets.json"
cat > "$SECRETS" <<'EOF'
{"demo-client-secret": "s3cret-value", "app-sp-password": "p4ssword-value"}
EOF

# Runs the engine expecting a typed failure: exit code, a stderr fragment,
# and the error code recorded in the report.
expect_fail() {
  local desc="$1" want_rc="$2" want_msg="$3" want_code="$4"
  shift 4
  local rc=0 stderr_file="$TMP/stderr.txt" report="$TMP/fail-report.json"
  rm -f "$report"
  "$@" --report "$report" >/dev/null 2>"$stderr_file" || rc=$?
  [ "$rc" -eq "$want_rc" ] || die "$desc: expected exit $want_rc, got $rc"
  grep -qF "$want_msg" "$stderr_file" || die "$desc: stderr does not name '$want_msg'"
  [ "$(report_field "$report" "r['error']['code']")" = "$want_code" ] \
    || die "$desc: expected error code $want_code"
  ok "$desc"
}

# Writes a descriptor variant: copies the fixture and applies one text substitution.
variant() {
  local out="$1" old="$2" new="$3"
  python3 - "$DESCRIPTOR" "$out" "$old" "$new" <<'PY'
import sys
src, out, old, new = sys.argv[1:5]
text = open(src).read()
assert old in text, f"{old!r} not found in fixture descriptor"
open(out, "w").write(text.replace(old, new))
PY
}


note "bind: happy path resolves every source kind"
ENV1="$TMP/happy.env"
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$ENV1" --secrets "$SECRETS" --report "$TMP/happy.json" >/dev/null 2>&1 \
  || die "happy path bind failed"
[ "$(env_value "$ENV1" DEMO_BASE_URL)" = "https://osdu.spi.example.com/api/demo/v1/" ] \
  || die "gateway suffix: expected trailing slash stripped then suffix appended"
[ "$(env_value "$ENV1" DEMO_TENANT)" = "opendes" ] || die "partition must be the primary entry"
[ "$(env_value "$ENV1" LEGAL_TAG)" = "opendes-public-usa-dataset-1" ] \
  || die "legalTag must read the primary partition's legal_tag"
[ "$(env_value "$ENV1" TEST_OPENID_PROVIDER_URL)" = "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0" ] \
  || die "openid must read azure.openid_issuer"
[ "$(env_value "$ENV1" CLIENT_TENANT)" = "11111111-2222-3333-4444-555555555555" ] \
  || die "tenant must read azure.tenant_id"
[ "$(env_value "$ENV1" VENDOR)" = "azure" ] || die "static value lost"
[ "$(env_value "$ENV1" SEARCH_URL)" = "https://osdu.spi.example.com/api/demo/v1/search" ] \
  || die "template must render from the resolved map"
[ "$(env_value "$ENV1" TESTER_TOKEN)" = "tok-123" ] || die "user source must read the caller env"
[ "$(env_value "$ENV1" RETRY_COUNT)" = "3" ] || die "declared default lost"
[ "$(env_value "$ENV1" CLIENT_SECRET)" = "s3cret-value" ] || die "keyvault: source lost"
[ "$(env_value "$ENV1" SP_PASSWORD)" = "p4ssword-value" ] || die "keyVaultBindings lost"
[ "$(report_field "$TMP/happy.json" "len(r['missing'])")" = "0" ] || die "happy path reports missing"
ok "all eleven bindings resolved"

note "run: happy path succeeds and reports the contract"
touch "$TMP/run.env" && chmod 644 "$TMP/run.env"
TESTER_TOKEN="tok-123" engine --mode run --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$TMP/run.env" --secrets "$SECRETS" --report "$TMP/run.json" >/dev/null 2>&1 \
  || die "happy path run failed"
MODE="$(python3 -c "import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))" "$TMP/run.env")"
[ "$MODE" = "0o600" ] || die "env file must be owner-only even over a loose pre-existing file, got $MODE"
ok "env file is 0600"
[ "$(report_field "$TMP/run.json" "r['contract']['test_dir']")" = "demo-acceptance-test" ] || die "test_dir wrong"
[ "$(report_field "$TMP/run.json" "r['contract']['maven_arguments']")" = "['verify', '-DskipTests=false']" ] \
  || die "maven argv tokens wrong"
[ "$(report_field "$TMP/run.json" "r['contract']['timeout_minutes']")" = "30" ] || die "timeout wrong"
[ "$(report_field "$TMP/run.json" "r['contract']['requires']['loads']")" = "['reference-data']" ] || die "requires.loads wrong"
[ "$(report_field "$TMP/run.json" "r['contract']['dependencies']")" = "['entitlements']" ] || die "dependencies wrong"
[ "$(report_field "$TMP/run.json" "r['key_vault']['vault']")" = "kv-spi-demo" ] || die "vault name wrong"
[ "$(report_field "$TMP/run.json" "sorted(r['key_vault']['secret_names'])")" = "['app-sp-password', 'demo-client-secret']" ] \
  || die "secret names wrong"
ok "contract fields reported"

note "determinism: same inputs, byte-identical env file"
ENV2="$TMP/happy2.env"
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$ENV2" --secrets "$SECRETS" >/dev/null 2>&1
cmp -s "$ENV1" "$ENV2" || die "two identical runs produced different env files"
ok "byte-identical"

note "precedence: explicit process env wins verbatim, no suffix appended"
ENV3="$TMP/override.env"
DEMO_BASE_URL="http://localhost:8080" TESTER_TOKEN="tok-123" engine --mode bind \
  --descriptor "$DESCRIPTOR" --facts "$FACTS" --env-file "$ENV3" --secrets "$SECRETS" >/dev/null 2>&1
[ "$(env_value "$ENV3" DEMO_BASE_URL)" = "http://localhost:8080" ] \
  || die "explicit env must win verbatim (no suffix)"
[ "$(env_value "$ENV3" SEARCH_URL)" = "http://localhost:8080search" ] \
  || die "template must render from the overridden value"
ok "explicit env wins"

note "missing facts (today's envelope): bind warns and still writes"
ENV4="$TMP/today.env"
RC=0
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS_TODAY" \
  --env-file "$ENV4" --secrets "$SECRETS" --report "$TMP/today.json" >/dev/null 2>"$TMP/today-err.txt" || RC=$?
[ "$RC" -eq 0 ] || die "bind must exit 0 on missing facts"
grep -q "TEST_OPENID_PROVIDER_URL" "$TMP/today-err.txt" || die "bind must warn about the openid binding"
grep -q "LEGAL_TAG" "$TMP/today-err.txt" || die "bind must warn about the legalTag binding"
grep -q "^DEMO_TENANT=" "$ENV4" || die "resolvable bindings must still be written"
grep -q "^TEST_OPENID_PROVIDER_URL=" "$ENV4" && die "unresolved binding must be omitted, not empty"
[ "$(report_field "$TMP/today.json" "len(r['missing'])")" = "2" ] || die "expected exactly 2 missing"
ok "bind warns, writes, reports"

note "missing facts (today's envelope): run refuses with a typed reason"
RC=0
echo "STALE=from-an-earlier-run" > "$TMP/refused.env"
TESTER_TOKEN="tok-123" engine --mode run --descriptor "$DESCRIPTOR" --facts "$FACTS_TODAY" \
  --env-file "$TMP/refused.env" --secrets "$SECRETS" --report "$TMP/refused.json" >/dev/null 2>"$TMP/refused-err.txt" || RC=$?
[ "$RC" -eq 3 ] || die "run must exit 3 on missing facts, got $RC"
[ ! -e "$TMP/refused.env" ] || die "refusal must remove a stale env file, not leave it for the caller"
grep -q "LEGAL_TAG" "$TMP/refused-err.txt" || die "refusal must name the unresolved binding"
[ "$(report_field "$TMP/refused.json" "r['error']['category']")" = "env-not-ready" ] || die "wrong error category"
ok "typed env-not-ready refusal"

note "missing secrets: bind warns, run refuses"
RC=0
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$TMP/nosec.env" >/dev/null 2>"$TMP/nosec-err.txt" || RC=$?
[ "$RC" -eq 0 ] || die "bind without secrets must still exit 0"
grep -q "demo-client-secret" "$TMP/nosec-err.txt" || die "bind must name the unsupplied secret"
RC=0
TESTER_TOKEN="tok-123" engine --mode run --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$TMP/nosec2.env" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 3 ] || die "run without secrets must exit 3, got $RC"
ok "secrets follow the same two-audience rule"

note "parser: quoted scalars may carry '#'; inline comments still strip"
variant "$TMP/quoted-hash.yaml" "archetype: java-maven-azure }" \
  'archetype: java-maven-azure, description: "demo # service" }'
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$TMP/quoted-hash.yaml" --facts "$FACTS" \
  --env-file "$TMP/qh.env" --secrets "$SECRETS" >/dev/null 2>&1 \
  || die "a quoted scalar containing ' # ' must parse"
[ "$(env_value "$TMP/qh.env" VENDOR)" = "azure" ] || die "quoted '#' corrupted the parse"
variant "$TMP/inline-comment.yaml" "timeoutMinutes: 30" "timeoutMinutes: 30 # generous cap"
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$TMP/inline-comment.yaml" --facts "$FACTS" \
  --env-file "$TMP/ic.env" --secrets "$SECRETS" --report "$TMP/ic.json" >/dev/null 2>&1 \
  || die "an inline comment must still strip"
[ "$(report_field "$TMP/ic.json" "r['contract']['timeout_minutes']")" = "30" ] \
  || die "inline comment leaked into the value"
ok "quote-aware comment stripping"

note "halt: unknown source kind exits 2 naming the key"
variant "$TMP/bad-source.yaml" "{ source: partition }" "{ source: cosmos }"
expect_fail "unknown source" 2 "bindings.DEMO_TENANT.source 'cosmos'" "UNKNOWN_SOURCE" \
  engine --mode bind --descriptor "$TMP/bad-source.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: unknown descriptor key exits 2 naming the key"
variant "$TMP/bad-key.yaml" "timeoutMinutes: 30" "retries: 5"
expect_fail "unknown key" 2 "descriptor.tests.acceptance.retries" "UNKNOWN_KEY" \
  engine --mode bind --descriptor "$TMP/bad-key.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: reserved environment names are rejected"
variant "$TMP/reserved1.yaml" "CLIENT_TENANT" "GITHUB_TENANT"
expect_fail "reserved prefix GITHUB_" 2 "GITHUB_TENANT" "RESERVED_ENV_NAME" \
  engine --mode bind --descriptor "$TMP/reserved1.yaml" --facts "$FACTS" --env-file "$TMP/x.env"
variant "$TMP/reserved2.yaml" "CLIENT_TENANT" "AZURE_CLIENT_ID"
expect_fail "reserved name AZURE_CLIENT_ID" 2 "AZURE_CLIENT_ID" "RESERVED_ENV_NAME" \
  engine --mode bind --descriptor "$TMP/reserved2.yaml" --facts "$FACTS" --env-file "$TMP/x.env"
variant "$TMP/reserved3.yaml" "CLIENT_TENANT" "SPI_STACK_POINTER"
expect_fail "reserved prefix SPI_STACK_" 2 "SPI_STACK_POINTER" "RESERVED_ENV_NAME" \
  engine --mode bind --descriptor "$TMP/reserved3.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: a Maven argument is one argv token, never a shell string"
variant "$TMP/bad-maven.yaml" "[verify, -DskipTests=false]" '["verify -DskipTests=false"]'
expect_fail "maven shell string" 2 "mavenArguments[0]" "DESCRIPTOR_INVALID" \
  engine --mode bind --descriptor "$TMP/bad-maven.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: unsupported schemaVersion"
variant "$TMP/bad-version.yaml" "schemaVersion: 3" "schemaVersion: 2"
expect_fail "schemaVersion 2" 2 "schemaVersion" "UNSUPPORTED_SCHEMA_VERSION" \
  engine --mode bind --descriptor "$TMP/bad-version.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: templates may reference only non-template, non-secret bindings"
variant "$TMP/bad-tref.yaml" '${DEMO_BASE_URL}search' '${SEARCH_URL}again'
expect_fail "template referencing template" 2 "SEARCH_URL" "TEMPLATE_REF" \
  engine --mode bind --descriptor "$TMP/bad-tref.yaml" --facts "$FACTS" --env-file "$TMP/x.env"
variant "$TMP/bad-sref.yaml" '${DEMO_BASE_URL}search' '${CLIENT_SECRET}leak'
expect_fail "template referencing secret" 2 "CLIENT_SECRET" "TEMPLATE_REF" \
  engine --mode bind --descriptor "$TMP/bad-sref.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: one name cannot live in both bindings and keyVaultBindings"
variant "$TMP/dup.yaml" "SP_PASSWORD: app-sp-password" "VENDOR: app-sp-password"
expect_fail "duplicate env name" 2 "VENDOR" "DESCRIPTOR_INVALID" \
  engine --mode bind --descriptor "$TMP/dup.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "halt: a keyvault binding cannot declare a default"
variant "$TMP/kv-default.yaml" "{ source: keyvault:demo-client-secret }" \
  '{ source: keyvault:demo-client-secret, default: oops }'
expect_fail "keyvault default" 2 "CLIENT_SECRET" "DESCRIPTOR_INVALID" \
  engine --mode bind --descriptor "$TMP/kv-default.yaml" --facts "$FACTS" --env-file "$TMP/x.env"

note "agreement point: caller and facts must agree on gateway and partition"
TESTER_TOKEN="tok-123" engine --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$TMP/agree.env" --secrets "$SECRETS" \
  --expect-gateway "https://osdu.spi.example.com" --expect-partition "opendes" \
  --report "$TMP/agree.json" >/dev/null 2>&1 || die "matching expectations must pass"
[ "$(report_field "$TMP/agree.json" "sorted(r['agreement_checked'])")" = "['gateway', 'partition']" ] \
  || die "agreement checks not recorded"
expect_fail "gateway mismatch" 4 "disagree on gateway" "AGREEMENT_MISMATCH" \
  env TESTER_TOKEN=tok-123 python3 "$ENGINE" --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$TMP/x.env" --secrets "$SECRETS" --expect-gateway "https://other.example.com"
expect_fail "partition mismatch" 4 "disagree on partition" "AGREEMENT_MISMATCH" \
  env TESTER_TOKEN=tok-123 python3 "$ENGINE" --mode bind --descriptor "$DESCRIPTOR" --facts "$FACTS" \
  --env-file "$TMP/x.env" --secrets "$SECRETS" --expect-partition "closedes"
ok "trailing-slash-insensitive gateway comparison, typed mismatch"

note "infra: wrong facts apiVersion is a typed refusal"
python3 -c "
import json
facts = json.load(open('$FACTS'))
facts['apiVersion'] = 'spi.osdu.dev/v2'
json.dump(facts, open('$TMP/facts-v2.json', 'w'))
"
expect_fail "facts apiVersion" 4 "spi.osdu.dev/v2" "FACTS_API_VERSION" \
  engine --mode bind --descriptor "$DESCRIPTOR" --facts "$TMP/facts-v2.json" --env-file "$TMP/x.env"

note "schema file: published contract parses and pins version 3"
python3 -c "
import json
schema = json.load(open('$SCHEMA'))
assert schema['properties']['schemaVersion']['const'] == 3
assert 'keyvault:' in schema['\$defs']['binding']['properties']['source']['pattern']
"
ok "service-descriptor.schema.json consistent"

printf '\nAll acceptance resolver harness checks passed.\n'
