#!/usr/bin/env bash
#
# Phase: optional packaging validation.
#
# `uv build` proves the project still produces a wheel and sdist from the locked
# source tree. The canonical Python image installs from source plus lockfile, so
# this is a validation step, not the image input.
#
# Environment:
#   PACKAGE_BUILD - "true" to run the packaging validation

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

if ! spi_enabled "${PACKAGE_BUILD:-false}"; then
  echo "Packaging validation disabled (package_build=false)."
  exit 0
fi

spi_group_start "uv build"
uv build --out-dir dist
spi_group_end

ls -l dist
