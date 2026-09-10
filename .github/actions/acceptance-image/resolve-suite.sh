#!/usr/bin/env bash
#
# Decides which suite modules the acceptance image bakes and whether it can build
# at all: every tests.<name>.path the descriptor declares when .spi/service.yaml
# exists (ADR-040), else the upstream default <service>-acceptance-test. A missing
# default suite is a clean skip; a broken descriptor, or one naming a suite that
# is not there, halts with exit 2 rather than guessing. suite_dir is the
# acceptance suite (the image's run-time default); suite_dirs lists them all.
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
SUITE_DIRS="$SUITE_DIR"
SOURCE="default"
if [[ -f "$DESCRIPTOR_PATH" ]]; then
  REPORT="$(mktemp)"
  trap 'rm -f "$REPORT"' EXIT
  python3 "$RESOLVER" --contract-only --descriptor "$DESCRIPTOR_PATH" --report "$REPORT" > /dev/null
  SUITE_DIR="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['contract']['test_dir'])" "$REPORT")"
  # The acceptance suite leads so it is the image's run-time default.
  SUITE_DIRS="$(python3 -c "
import json, sys
suites = json.load(open(sys.argv[1]))['contract']['suites']
print(' '.join([suites['acceptance']] + [d for n, d in sorted(suites.items()) if n != 'acceptance']))" "$REPORT")"
  SOURCE="descriptor"
fi

BUILDABLE="true"
REASON=""
for dir in $SUITE_DIRS; do
  if [[ ! -d "$dir" ]]; then
    # The default is a guess, so its absence is a skip. A descriptor path is an
    # assertion the fork made, so its absence is a contract error (exit 2, as in
    # the engine): a typo must never read as "this fork has no suite".
    if [[ "$SOURCE" == "descriptor" ]]; then
      echo "::error::${DESCRIPTOR_PATH} names suite path '$dir', which does not exist in this checkout"
      exit 2
    fi
    BUILDABLE="false"
    REASON="suite directory '$dir' (${SOURCE}) not present"
  fi
done

{
  echo "suite_dir=$SUITE_DIR"
  echo "suite_dirs=$SUITE_DIRS"
  echo "buildable=$BUILDABLE"
  echo "reason=$REASON"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [[ "$BUILDABLE" == "true" ]]; then
  echo "✓ suites: $SUITE_DIRS (${SOURCE})"
else
  echo "ℹ acceptance image skipped: $REASON"
fi
