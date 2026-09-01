#!/usr/bin/env bash
#
# Decides which suite module the acceptance image bakes and whether it can build
# at all: the descriptor's tests.acceptance.path when .spi/service.yaml exists
# (ADR-040), else the upstream default <service>-acceptance-test. A missing
# default suite is a clean skip; a broken descriptor, or one naming a suite that
# is not there, halts with exit 2 rather than guessing.
#
# Env: SERVICE_NAME (required), DESCRIPTOR_PATH (default .spi/service.yaml),
#      RESOLVER (path to the acceptance resolver engine)
# Local: SERVICE_NAME=demo GITHUB_OUTPUT=/dev/stdout ./resolve-suite.sh

set -euo pipefail

if [[ -z "${SERVICE_NAME:-}" ]]; then
  echo "Error: SERVICE_NAME is required"
  exit 1
fi

DESCRIPTOR_PATH="${DESCRIPTOR_PATH:-.spi/service.yaml}"
RESOLVER="${RESOLVER:-.github/actions/acceptance-resolver/resolve.py}"

SUITE_DIR="${SERVICE_NAME}-acceptance-test"
SOURCE="default"
if [[ -f "$DESCRIPTOR_PATH" ]]; then
  REPORT="$(mktemp)"
  trap 'rm -f "$REPORT"' EXIT
  python3 "$RESOLVER" --contract-only --descriptor "$DESCRIPTOR_PATH" --report "$REPORT" > /dev/null
  SUITE_DIR="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['contract']['test_dir'])" "$REPORT")"
  SOURCE="descriptor"
fi

BUILDABLE="true"
REASON=""
if [[ ! -d "$SUITE_DIR" ]]; then
  # The default is a guess, so its absence is a skip. A descriptor path is an
  # assertion the fork made, so its absence is a contract error (exit 2, as in
  # the engine): a typo must never read as "this fork has no suite".
  if [[ "$SOURCE" == "descriptor" ]]; then
    echo "::error::${DESCRIPTOR_PATH} names acceptance suite '$SUITE_DIR', which does not exist in this checkout"
    exit 2
  fi
  BUILDABLE="false"
  REASON="suite directory '$SUITE_DIR' (${SOURCE}) not present"
fi

{
  echo "suite_dir=$SUITE_DIR"
  echo "buildable=$BUILDABLE"
  echo "reason=$REASON"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [[ "$BUILDABLE" == "true" ]]; then
  echo "✓ acceptance suite: $SUITE_DIR (${SOURCE})"
else
  echo "ℹ acceptance image skipped: $REASON"
fi
