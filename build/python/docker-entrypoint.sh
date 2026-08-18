#!/bin/sh
# Canonical container entrypoint for OSDU SPI Python (uv) services, synced to every fork.
#
# The Stack chart cannot override a container command, so the uvicorn invocation is baked
# into the image and configured through validated environment values that the canonical
# Dockerfile bakes from build arguments:
#
#   SPI_APP_MODULE        required ASGI target, e.g. "wdmsworker.app:app"
#   SPI_APP_HOST          bind address (default 0.0.0.0)
#   SPI_APP_PORT          bind port (default 8080)
#   SPI_UVICORN_WORKERS   worker count (default 1)
#   SPI_UVICORN_LOG_LEVEL critical|error|warning|info|debug|trace
#   SPI_UVICORN_ROOT_PATH optional ASGI root path, e.g. "/api/wdms-worker"
#   SPI_HEALTH_PATH       optional container-local health path used by HEALTHCHECK
#
# Every value is validated before it reaches uvicorn: the entrypoint never evaluates a
# caller-supplied string and never passes free-form arguments through a shell.
set -eu

fail() {
  echo "spi-entrypoint: $1" >&2
  exit 1
}

matches() {
  printf '%s' "$1" | grep -Eq "$2"
}

MODULE_PATTERN='^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*:[A-Za-z_][A-Za-z0-9_]*$'
PATH_PATTERN='^/[A-Za-z0-9._~/-]*$'
PORT_PATTERN='^[0-9]{1,5}$'
WORKERS_PATTERN='^[0-9]{1,3}$'
HOST_PATTERN='^[A-Za-z0-9.:_-]+$'
LOG_LEVEL_PATTERN='^(critical|error|warning|info|debug|trace)$'

run_healthcheck() {
  health_path="${SPI_HEALTH_PATH:-}"
  if [ -z "$health_path" ]; then
    echo "spi-entrypoint: no SPI_HEALTH_PATH configured; healthcheck is a no-op"
    exit 0
  fi
  matches "$health_path" "$PATH_PATTERN" || fail "invalid SPI_HEALTH_PATH '$health_path'"
  matches "${SPI_APP_PORT:-8080}" "$PORT_PATTERN" || fail "invalid SPI_APP_PORT '${SPI_APP_PORT:-}'"

  # The URL is assembled inside Python from the environment, never by string
  # interpolation in the shell.
  exec python3 - <<'PYTHON'
import os
import sys
import urllib.request

port = os.environ.get("SPI_APP_PORT", "8080")
path = os.environ.get("SPI_HEALTH_PATH", "")
url = f"http://127.0.0.1:{port}{path}"
try:
    with urllib.request.urlopen(url, timeout=4) as response:
        sys.exit(0 if 200 <= response.status < 400 else 1)
except Exception as error:  # noqa: BLE001 - healthcheck reports, never raises
    print(f"healthcheck failed for {url}: {error}", file=sys.stderr)
    sys.exit(1)
PYTHON
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    healthcheck)
      run_healthcheck
      ;;
    *)
      # Explicit container args win, matching normal Docker behaviour.
      exec "$@"
      ;;
  esac
fi

APP_MODULE="${SPI_APP_MODULE:-}"
APP_HOST="${SPI_APP_HOST:-0.0.0.0}"
APP_PORT="${SPI_APP_PORT:-8080}"
WORKERS="${SPI_UVICORN_WORKERS:-1}"
LOG_LEVEL="${SPI_UVICORN_LOG_LEVEL:-info}"
ROOT_PATH="${SPI_UVICORN_ROOT_PATH:-}"

[ -n "$APP_MODULE" ] || fail "SPI_APP_MODULE is not set. Build the image with --build-arg APP_MODULE=<package.module:app>."
matches "$APP_MODULE" "$MODULE_PATTERN" || fail "invalid SPI_APP_MODULE '$APP_MODULE' (expected package.module:attribute)"
matches "$APP_HOST" "$HOST_PATTERN" || fail "invalid SPI_APP_HOST '$APP_HOST'"
matches "$APP_PORT" "$PORT_PATTERN" || fail "invalid SPI_APP_PORT '$APP_PORT'"
matches "$WORKERS" "$WORKERS_PATTERN" || fail "invalid SPI_UVICORN_WORKERS '$WORKERS'"
matches "$LOG_LEVEL" "$LOG_LEVEL_PATTERN" || fail "invalid SPI_UVICORN_LOG_LEVEL '$LOG_LEVEL'"

set -- uvicorn "$APP_MODULE" \
  --host "$APP_HOST" \
  --port "$APP_PORT" \
  --workers "$WORKERS" \
  --log-level "$LOG_LEVEL"

if [ -n "$ROOT_PATH" ]; then
  matches "$ROOT_PATH" "$PATH_PATTERN" || fail "invalid SPI_UVICORN_ROOT_PATH '$ROOT_PATH'"
  set -- "$@" --root-path "$ROOT_PATH"
fi

exec "$@"
