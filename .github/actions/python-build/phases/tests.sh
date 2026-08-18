#!/usr/bin/env bash
#
# Phase: pytest suites.
#
# Each suite writes its own JUnit (and, where meaningful, Cobertura) report so no
# suite overwrites another's results:
#
#   unit-junit.xml                / unit-coverage.xml
#   service-inprocess-junit.xml   / service-inprocess-coverage.xml
#   service-subprocess-junit.xml  (packaging/process proof; coverage from a
#                                  separate process is not meaningful here)
#
# Every enabled suite runs even when an earlier one fails, so one CI run reports
# all failures. The pytest command is assembled from validated plan values only —
# no caller-supplied command string is ever executed.
#
# Environment:
#   TEST_EXTRAS, REPORTS_DIR, GENERATE_COVERAGE, COVERAGE_TARGET,
#   RUN_UNIT_TESTS, UNIT_TEST_PATH,
#   RUN_SERVICE_IN_PROCESS, RUN_SERVICE_SUBPROCESS, SERVICE_TEST_PATH,
#   SERVICE_IN_PROCESS_FLAG

set -euo pipefail

# shellcheck source=./common.sh
source "$(dirname "$0")/common.sh"

REPORTS_DIR="${REPORTS_DIR:-.spi-build-reports}"
JUNIT_DIR="${REPORTS_DIR}/junit"
COVERAGE_DIR="${REPORTS_DIR}/coverage"
mkdir -p "$JUNIT_DIR" "$COVERAGE_DIR"

mapfile -t EXTRA_ARGS < <(spi_extra_args "${TEST_EXTRAS:-}")
UV_RUN=(uv run --frozen "${EXTRA_ARGS[@]}")
FAILED=()

if ! spi_enabled "${RUN_UNIT_TESTS:-false}" &&
   ! spi_enabled "${RUN_SERVICE_IN_PROCESS:-false}" &&
   ! spi_enabled "${RUN_SERVICE_SUBPROCESS:-false}"; then
  echo "::warning::No pytest suites are enabled for this repository; nothing to run."
  exit 0
fi

if ! "${UV_RUN[@]}" pytest --version >/dev/null 2>&1; then
  echo "::error::pytest is not installed in the locked test environment. Add it to the test extras (or set the suite inputs to 'none')."
  exit 1
fi

if spi_enabled "${GENERATE_COVERAGE:-false}" &&
   ! "${UV_RUN[@]}" python -c "import pytest_cov" >/dev/null 2>&1; then
  echo "::error::generate_coverage=true but pytest-cov is not installed in the locked test environment."
  exit 1
fi

# run_suite <label> <junit-name> <coverage-name|none> <test-path> [extra pytest flag...]
run_suite() {
  local label="$1" junit_name="$2" coverage_name="$3" test_path="$4"
  shift 4

  local -a command=("${UV_RUN[@]}" pytest "$test_path" "--junitxml=${JUNIT_DIR}/${junit_name}")
  if spi_enabled "${GENERATE_COVERAGE:-false}" && [ "$coverage_name" != "none" ]; then
    command+=(
      "--cov=${COVERAGE_TARGET}"
      "--cov-report=xml:${COVERAGE_DIR}/${coverage_name}"
      "--cov-report=term-missing:skip-covered"
    )
  fi
  local flag
  for flag in "$@"; do
    [ -n "$flag" ] || continue
    command+=("$flag")
  done

  spi_group_start "pytest ${label} (${test_path})"
  local status=0
  set +e
  "${command[@]}"
  status=$?
  set -e
  spi_group_end

  if [ "$status" -eq 5 ]; then
    echo "::error::pytest collected no tests for the ${label} suite (${test_path})."
    FAILED+=("$label")
    return
  fi
  if [ "$status" -ne 0 ]; then
    echo "::error::pytest failed for the ${label} suite (${test_path}); exit code ${status}."
    FAILED+=("$label")
  fi
}

if spi_enabled "${RUN_UNIT_TESTS:-false}"; then
  run_suite "unit" "unit-junit.xml" "unit-coverage.xml" "${UNIT_TEST_PATH}"
fi

if spi_enabled "${RUN_SERVICE_IN_PROCESS:-false}"; then
  run_suite \
    "service-inprocess" \
    "service-inprocess-junit.xml" \
    "service-inprocess-coverage.xml" \
    "${SERVICE_TEST_PATH}" \
    "${SERVICE_IN_PROCESS_FLAG:-}"
fi

if spi_enabled "${RUN_SERVICE_SUBPROCESS:-false}"; then
  run_suite \
    "service-subprocess" \
    "service-subprocess-junit.xml" \
    "none" \
    "${SERVICE_TEST_PATH}"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "::error::pytest suites failed: ${FAILED[*]}"
  exit 1
fi

echo "All enabled pytest suites passed."
