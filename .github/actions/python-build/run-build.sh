#!/usr/bin/env bash
#
# Python build driver.
#
# Runs the validated phases in a fixed order and aggregates their results into a
# single step summary and one exit code. Phase scripts are separate processes, so
# each one keeps its own `set -e` semantics and the driver only inspects exit
# codes — no `$?` inspection after an aborted command, and no eval anywhere.
#
# Order matters:
#   1. sync-test-env  fatal; nothing downstream is meaningful without it
#   2. lock-drift     lockfile currency and (optional) export drift
#   3. quality        ruff / ruff format / mypy
#   4. tests          unit + service suites, distinct JUnit/Cobertura reports
#   5. package        optional `uv build` validation
#   6. runtime-extras locked runtime install + provider import smoke (replaces
#                     the test environment, so it always runs last)
#
# Private index credentials, when supplied, are exported as uv's documented
# UV_INDEX_<NAME>_USERNAME/PASSWORD variables and masked in the log. They are
# never written to a file, a build argument, or the environment of a later job.

set -uo pipefail

ACTION_PATH="${GITHUB_ACTION_PATH:-$(cd "$(dirname "$0")" && pwd)}"
PHASES_DIR="${ACTION_PATH}/phases"
REPORTS_DIR="${REPORTS_DIR:-.spi-build-reports}"
export REPORTS_DIR

mkdir -p "${REPORTS_DIR}/junit" "${REPORTS_DIR}/coverage"

if [ -n "${INDEX_NAME:-}" ] && [ -n "${INDEX_TOKEN:-}" ]; then
  echo "::add-mask::${INDEX_TOKEN}"
  # uv resolves credentials from UV_INDEX_<NAME>_USERNAME/PASSWORD where <NAME> is
  # the index name uppercased with non-alphanumeric characters replaced by "_".
  INDEX_ENV_NAME="${INDEX_NAME^^}"
  INDEX_ENV_NAME="${INDEX_ENV_NAME//[^A-Z0-9]/_}"
  export "UV_INDEX_${INDEX_ENV_NAME}_USERNAME=${INDEX_USERNAME:-__token__}"
  export "UV_INDEX_${INDEX_ENV_NAME}_PASSWORD=${INDEX_TOKEN}"
  echo "Configured credentials for uv index '${INDEX_NAME}'."
fi

PHASE_NAMES=()
PHASE_RESULTS=()
FAILED_PHASES=()

record_phase() {
  PHASE_NAMES+=("$1")
  PHASE_RESULTS+=("$2")
}

run_phase() {
  local name="$1" script="$2"
  echo "▶️  Phase: ${name}"
  if bash "${PHASES_DIR}/${script}"; then
    record_phase "$name" "success"
    return 0
  fi
  record_phase "$name" "failure"
  FAILED_PHASES+=("$name")
  return 1
}

if ! run_phase "sync-test-env" "sync-test-env.sh"; then
  echo "::error::The locked test environment could not be created; skipping the remaining phases."
  SYNC_FAILED=true
else
  SYNC_FAILED=false
fi

if [ "$SYNC_FAILED" = "false" ]; then
  run_phase "lock-drift" "lock-drift.sh" || true
  run_phase "quality" "quality.sh" || true
  run_phase "tests" "tests.sh" || true
  run_phase "package" "package.sh" || true
  run_phase "runtime-extras" "runtime-extras.sh" || true
fi

# Phase failures are intentionally aggregated above. Everything below creates
# required provenance/report artifacts and must fail the action immediately.
set -e

# Build manifest: the Python image is built from source plus lockfile, so the
# build-artifacts artifact carries provenance metadata instead of a JAR.
python - <<'PYTHON'
import hashlib
import json
import os
import pathlib

reports = pathlib.Path(os.environ.get("REPORTS_DIR", ".spi-build-reports"))
reports.mkdir(parents=True, exist_ok=True)

lock = pathlib.Path("uv.lock")
lock_digest = ""
if lock.is_file():
    lock_digest = "sha256:" + hashlib.sha256(lock.read_bytes()).hexdigest()


def listed(name: str) -> list[str]:
    return [item for item in os.environ.get(name, "").split(",") if item]


manifest = {
    "schemaVersion": 1,
    "archetype": "python-uv-fastapi",
    "repository": os.environ.get("GITHUB_REPOSITORY", ""),
    "commit": os.environ.get("GITHUB_SHA", ""),
    "ref": os.environ.get("GITHUB_REF_NAME", ""),
    "pythonVersion": os.environ.get("PYTHON_VERSION", ""),
    "uvVersion": os.environ.get("UV_VERSION", ""),
    "distribution": os.environ.get("DISTRIBUTION_NAME", ""),
    "importPackage": os.environ.get("PACKAGE_NAME", ""),
    "testExtras": listed("TEST_EXTRAS"),
    "runtimeExtras": listed("RUNTIME_EXTRAS"),
    "lockfile": {"path": "uv.lock", "digest": lock_digest},
}

(reports / "build-manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
print(json.dumps(manifest, indent=2, sort_keys=True))
PYTHON

{
  echo "### 🐍 Python Build Phases"
  echo ""
  echo "| Phase | Result |"
  echo "| --- | --- |"
  for index in "${!PHASE_NAMES[@]}"; do
    if [ "${PHASE_RESULTS[$index]}" = "success" ]; then
      echo "| \`${PHASE_NAMES[$index]}\` | ✅ success |"
    else
      echo "| \`${PHASE_NAMES[$index]}\` | ❌ failure |"
    fi
  done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

python "${ACTION_PATH}/render_reports_summary.py" --reports-dir "${REPORTS_DIR}" \
  | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "${#FAILED_PHASES[@]}" -gt 0 ]; then
  echo "::error::Python build failed in phase(s): ${FAILED_PHASES[*]}"
  exit 1
fi

echo "✅ Python build completed successfully."
