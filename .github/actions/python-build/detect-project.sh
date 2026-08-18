#!/usr/bin/env bash
#
# Detect whether the repository is a uv-managed Python project.
#
# Mirrors the java-build "Check for pom.xml" step: absence of the marker is not an
# error, it simply skips the lane. A pyproject.toml without uv.lock fails closed —
# the python-uv archetype is lock based and an unlocked build would ship untested
# dependency resolution.
#
# Outputs (GITHUB_OUTPUT):
#   has_python_project - true when pyproject.toml and uv.lock are both present
#   lockfile           - the detected lockfile name (empty when not a Python project)

set -euo pipefail

if [ ! -f "pyproject.toml" ]; then
  echo "No pyproject.toml found; skipping the Python build lane."
  echo "has_python_project=false" >> "$GITHUB_OUTPUT"
  echo "lockfile=" >> "$GITHUB_OUTPUT"
  exit 0
fi

if [ ! -f "uv.lock" ]; then
  echo "::error::pyproject.toml was found without uv.lock. The python-uv archetype requires a committed uv.lock (run 'uv lock')."
  exit 1
fi

echo "Detected uv-managed Python project (pyproject.toml + uv.lock)."
echo "has_python_project=true" >> "$GITHUB_OUTPUT"
echo "lockfile=uv.lock" >> "$GITHUB_OUTPUT"
