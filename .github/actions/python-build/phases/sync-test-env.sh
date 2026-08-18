#!/usr/bin/env bash
#
# Phase: synchronise the locked test environment.
#
# Uses the committed lockfile only. `--locked` fails when uv.lock is stale rather
# than silently re-resolving, so CI can never install a dependency set that the
# lockfile (and therefore the image build) does not describe.
#
# Environment:
#   TEST_EXTRAS - comma-separated, already validated extras (may be empty)

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

mapfile -t EXTRA_ARGS < <(spi_extra_args "${TEST_EXTRAS:-}")

spi_group_start "uv sync --locked ${TEST_EXTRAS:-<no extras>}"
uv sync --locked "${EXTRA_ARGS[@]}"
spi_group_end

echo "Locked test environment ready."
