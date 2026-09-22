#!/bin/sh
# Entrypoint for build/load.Dockerfile. Waits for the schema service, obtains a bearer
# token, and runs upstream's DeploySharedSchemas.py against the system schemas endpoint.
# Arguments are appended to the loader verbatim. The loader's exit status is the verdict:
# it treats a schema that is already PUBLISHED as loaded, so a re-run passes.
#
# Env: SCHEMA_URL (required, the service base ending in /api/schema-service/v1),
#      BEARER_TOKEN (optional, skips the exchange), otherwise AZURE_TENANT_ID,
#      AZURE_CLIENT_ID and AZURE_FEDERATED_TOKEN_FILE as the workload identity webhook
#      injects them; TOKEN_RESOURCE (default https://management.azure.com/, the
#      v1 resource the token is minted for), WAIT_SECONDS (default 2700).
set -u

LOADER_HOME="${LOADER_HOME:-/loader}"
: "${SCHEMA_URL:?SCHEMA_URL is required}"
BASE="${SCHEMA_URL%/}"
INFO_URL="$BASE/info"
SYSTEM_URL="$BASE/schemas/system"
WAIT_SECONDS="${WAIT_SECONDS:-2700}"
TOKEN_RESOURCE="${TOKEN_RESOURCE:-https://management.azure.com/}"
LOG="${TMPDIR:-/tmp}/load.log"

# The deadline is wall-clock: each probe costs its 5s timeout on top of the sleep.
echo "Waiting for schema service at ${INFO_URL}..."
start_ts=$(date +%s)
until INFO_URL="$INFO_URL" python3 - <<'PY' 2>/dev/null
import os, sys, urllib.request
try:
    code = urllib.request.urlopen(os.environ["INFO_URL"], timeout=5).getcode()
except Exception:
    code = 0
sys.exit(0 if code == 200 else 1)
PY
do
  elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -ge "$WAIT_SECONDS" ]; then
    echo "ERROR: schema service did not return 200 after ${elapsed}s" >&2
    exit 1
  fi
  sleep 2
done
echo "Schema service ready after $(( $(date +%s) - start_ts ))s."

if [ -z "${BEARER_TOKEN:-}" ]; then
  # The v1 endpoint on purpose: the services read appid, which v2 tokens omit.
  echo "Acquiring bearer token through workload identity..."
  BEARER_TOKEN=$(TOKEN_RESOURCE="$TOKEN_RESOURCE" python3 - <<'PY'
import json, os, sys, urllib.parse, urllib.request
tenant = os.environ.get("AZURE_TENANT_ID", "")
client = os.environ.get("AZURE_CLIENT_ID", "")
token_file = os.environ.get("AZURE_FEDERATED_TOKEN_FILE", "/var/run/secrets/azure/tokens/azure-identity-token")
if not tenant or not client:
    sys.exit("AZURE_TENANT_ID and AZURE_CLIENT_ID are required when BEARER_TOKEN is unset")
with open(token_file) as fh:
    assertion = fh.read().strip()
authority = os.environ.get("AZURE_AUTHORITY_HOST", "https://login.microsoftonline.com/").rstrip("/")
body = urllib.parse.urlencode({
    "client_id": client,
    "resource": os.environ["TOKEN_RESOURCE"],
    "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    "client_assertion": assertion,
    "grant_type": "client_credentials",
}).encode()
req = urllib.request.Request(f"{authority}/{tenant}/oauth2/token", data=body, method="POST")
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
except urllib.error.HTTPError as exc:
    sys.exit(f"token exchange failed: HTTP {exc.code} {exc.read().decode(errors='replace')[:400]}")
token = payload.get("access_token")
if not token:
    sys.exit(f"token exchange returned no access_token: {payload}")
print(token)
PY
  ) || exit 1
fi
case "$BEARER_TOKEN" in
  Bearer\ *) ;;
  *) BEARER_TOKEN="Bearer $BEARER_TOKEN" ;;
esac
export BEARER_TOKEN

echo "Loading shared schemas into ${SYSTEM_URL}..."
# Redirect then cat, so $? is the loader's exit status and not a pipe's.
python3 "$LOADER_HOME/deployments/scripts/DeploySharedSchemas.py" -u "$SYSTEM_URL" "$@" >"$LOG" 2>&1
ret=$?
cat "$LOG"
if [ "$ret" -ne 0 ]; then
  echo "Schema load failed with exit code ${ret}." >&2
  exit "$ret"
fi
echo "Schema load completed."
