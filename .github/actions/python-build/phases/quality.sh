#!/usr/bin/env bash
#
# Phase: lint, format check, and static types.
#
# ruff and mypy come from the repository's own locked test extras — the action
# never installs an ad-hoc unpinned tool. Each mode is a closed enum:
#   auto     - run when the tool is present in the locked environment, else skip
#   required - run, and fail when the tool is missing
#   off      - never run
#
# All three checks run before the phase fails so a single CI run reports every
# lint, format, and typing problem.
#
# Environment:
#   TEST_EXTRAS, SOURCE_PATHS, FORMAT_CHECK_PATHS, LINT_MODE, TYPECHECK_MODE

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

mapfile -t EXTRA_ARGS < <(spi_extra_args "${TEST_EXTRAS:-}")
mapfile -t SOURCE_ARGS < <(spi_list "${SOURCE_PATHS:-}")
mapfile -t FORMAT_ARGS < <(spi_list "${FORMAT_CHECK_PATHS:-}")

UV_RUN=(uv run --frozen "${EXTRA_ARGS[@]}")
FAILED=()

tool_available() {
  "${UV_RUN[@]}" "$1" --version >/dev/null 2>&1
}

skip_or_fail() {
  local tool="$1" input="$2" mode="$3"
  if [ "$mode" = "required" ]; then
    echo "::error::${tool} is required by ${input}=required but is not installed in the locked test environment."
    return 1
  fi
  echo "::notice::${tool} is not installed in the locked test environment; skipping (${input}=${mode})."
  return 0
}

run_ruff() {
  if [ "${LINT_MODE:-auto}" = "off" ]; then
    echo "Lint disabled (lint_mode=off)."
    return 0
  fi
  if ! tool_available ruff; then
    skip_or_fail ruff lint_mode "${LINT_MODE:-auto}" || return 1
    return 0
  fi

  local status=0
  spi_group_start "ruff check ${SOURCE_PATHS:-.}"
  if ! "${UV_RUN[@]}" ruff check "${SOURCE_ARGS[@]}"; then
    status=1
  fi
  spi_group_end

  spi_group_start "ruff format --check ${FORMAT_CHECK_PATHS:-.}"
  if ! "${UV_RUN[@]}" ruff format --check "${FORMAT_ARGS[@]}"; then
    status=1
  fi
  spi_group_end
  return "$status"
}

run_mypy() {
  if [ "${TYPECHECK_MODE:-auto}" = "off" ]; then
    echo "Type checking disabled (typecheck_mode=off)."
    return 0
  fi
  if ! tool_available mypy; then
    skip_or_fail mypy typecheck_mode "${TYPECHECK_MODE:-auto}" || return 1
    return 0
  fi

  local status=0
  spi_group_start "mypy ${SOURCE_PATHS:-.}"
  if ! "${UV_RUN[@]}" mypy "${SOURCE_ARGS[@]}"; then
    status=1
  fi
  spi_group_end
  return "$status"
}

if ! run_ruff; then
  FAILED+=("ruff")
fi

if ! run_mypy; then
  FAILED+=("mypy")
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "::error::Quality checks failed: ${FAILED[*]}"
  exit 1
fi

echo "Quality checks passed."
