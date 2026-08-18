#!/usr/bin/env bash
#
# Phase: locked runtime environment and provider import smoke.
#
# The universal lockfile can contain a provider extra that never installs or
# imports. This phase installs exactly what the container image installs
# (`--locked --no-dev` plus the runtime extras) and imports the declared runtime
# modules, proving the deployed dependency set before an image is ever built.
#
# It deliberately runs last: it replaces the test environment with the runtime
# environment.
#
# Environment:
#   RUNTIME_EXTRAS         - comma-separated, validated extras (may be empty)
#   RUNTIME_IMPORT_MODULES - comma-separated dotted module names (may be empty)
#   DISTRIBUTION_NAME      - PEP 508 distribution name for the metadata check

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

mapfile -t EXTRA_ARGS < <(spi_extra_args "${RUNTIME_EXTRAS:-}")

spi_group_start "uv sync --locked --no-dev ${RUNTIME_EXTRAS:-<no extras>}"
uv sync --locked --no-dev "${EXTRA_ARGS[@]}"
spi_group_end

if [ -z "${RUNTIME_IMPORT_MODULES:-}" ] && [ -z "${DISTRIBUTION_NAME:-}" ]; then
  echo "No runtime modules or distribution name configured; import smoke skipped."
  exit 0
fi

spi_group_start "Runtime import smoke"
# The module names are passed through the environment and imported by name, never
# interpolated into a python -c string.
uv run --frozen --no-dev "${EXTRA_ARGS[@]}" python - <<'PYTHON'
import importlib
import os
import sys

failures = []

distribution = os.environ.get("DISTRIBUTION_NAME", "").strip()
if distribution:
    try:
        from importlib.metadata import version

        print(f"{distribution}=={version(distribution)}")
    except Exception as error:  # noqa: BLE001 - reported, not raised
        failures.append(f"metadata for '{distribution}': {error}")

modules = [
    module.strip()
    for module in os.environ.get("RUNTIME_IMPORT_MODULES", "").split(",")
    if module.strip()
]
for module in modules:
    try:
        importlib.import_module(module)
        print(f"import {module}: ok")
    except Exception as error:  # noqa: BLE001 - reported, not raised
        failures.append(f"import '{module}': {error}")

for failure in failures:
    print(f"::error::Runtime smoke failed for {failure}")

sys.exit(1 if failures else 0)
PYTHON
spi_group_end

echo "Runtime environment installs and imports correctly."
