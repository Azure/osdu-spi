#!/usr/bin/env bash
#
# Phase: lockfile and export drift.
#
# `uv lock --locked` proves uv.lock still matches pyproject.toml. The export leg
# (requirements files regenerated from the lock) only runs when the repository
# supplies its own regeneration script — the template never invents an export
# command for a service that has none.
#
# Environment:
#   RUN_LOCK_EXPORT_DRIFT   - "true" when a regeneration script was resolved
#   LOCK_REGENERATION_SCRIPT- repository-relative .sh path (validated)
#   LOCK_DRIFT_PATHS        - comma-separated paths compared after regeneration

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

spi_group_start "uv lock --locked"
if ! uv lock --locked; then
  spi_group_end
  echo "::error::uv.lock is out of date with pyproject.toml. Run 'uv lock' and commit the result."
  exit 1
fi
spi_group_end

if ! spi_enabled "${RUN_LOCK_EXPORT_DRIFT:-false}"; then
  echo "No lock export regeneration script configured; export drift check skipped."
  exit 0
fi

mapfile -t DRIFT_PATHS < <(spi_list "${LOCK_DRIFT_PATHS:-}")

spi_group_start "Regenerate exported requirements (${LOCK_REGENERATION_SCRIPT})"
bash "${LOCK_REGENERATION_SCRIPT}"
spi_group_end

if [ "${#DRIFT_PATHS[@]}" -eq 0 ]; then
  echo "No lock drift paths configured; skipping the diff comparison."
  exit 0
fi

if ! git diff --exit-code -- "${DRIFT_PATHS[@]}"; then
  echo "::error::Lock/export drift detected. Re-run ${LOCK_REGENERATION_SCRIPT} locally and commit: ${LOCK_DRIFT_PATHS}"
  exit 1
fi

echo "Lockfile and exported requirements are consistent."
