#!/usr/bin/env bash
#
# Validate the two inputs consumed before the toolchain exists.
#
# setup-python and setup-uv run before resolve_build_plan.py can execute, so the
# version strings they receive are validated here first. Values are read from the
# environment (never interpolated into the script body) and matched against the
# whole string so an embedded newline cannot smuggle in a second value.
#
# Outputs (GITHUB_OUTPUT):
#   python_version - validated Python version for actions/setup-python
#   uv_version     - validated uv version for astral-sh/setup-uv (may be empty,
#                    which makes setup-uv honour the repository required-version)

set -euo pipefail

PYTHON_VERSION="${PYTHON_VERSION:-}"
UV_VERSION="${UV_VERSION:-}"

if [ -z "$PYTHON_VERSION" ]; then
  PYTHON_VERSION="3.12"
fi

if [[ ! "$PYTHON_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "::error::Invalid python_version '${PYTHON_VERSION}' (expected MAJOR.MINOR or MAJOR.MINOR.PATCH)"
  exit 1
fi

if [ -n "$UV_VERSION" ] && [[ ! "$UV_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+|latest|latest-known)$ ]]; then
  echo "::error::Invalid uv_version '${UV_VERSION}' (expected X.Y.Z, 'latest' or 'latest-known')"
  exit 1
fi

echo "Python version: ${PYTHON_VERSION}"
echo "uv version: ${UV_VERSION:-<repository required-version>}"
echo "python_version=${PYTHON_VERSION}" >> "$GITHUB_OUTPUT"
echo "uv_version=${UV_VERSION}" >> "$GITHUB_OUTPUT"
