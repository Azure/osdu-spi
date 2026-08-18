#!/usr/bin/env bash
#
# Select the language-appropriate Dependabot configuration for a fork.
#
# One fork-resources file cannot serve both languages: a Maven ecosystem entry in a
# Python fork (or a uv entry in a Java fork) produces a permanent "no manifests found"
# Dependabot error. Instead the template ships one config per language and this script
# picks the right one from repository markers.
#
# Detection rules (Java stays the default so existing Java forks never change behaviour):
#   pom.xml present                      -> Java/Maven configuration
#   pyproject.toml + uv.lock, no pom.xml -> Python/uv configuration
#   anything else                        -> Java/Maven configuration (with a notice)
#
# Usage:
#   select-dependabot-config.sh [--print-source|--print-language] [repository_root]
#
# Output:
#   --print-source   (default) repository-relative path of the fork-resources config
#   --print-language java | python
#
# Notices go to stderr so the selected value can be captured directly from stdout.

set -euo pipefail

JAVA_CONFIG=".github/fork-resources/dependabot.yml"
PYTHON_CONFIG=".github/fork-resources/dependabot-python.yml"

MODE="--print-source"
ROOT="."

for argument in "$@"; do
  case "$argument" in
    --print-source|--print-language)
      MODE="$argument"
      ;;
    -*)
      echo "select-dependabot-config: unknown option '$argument'" >&2
      exit 2
      ;;
    *)
      ROOT="$argument"
      ;;
  esac
done

language="java"
if [ -f "${ROOT}/pom.xml" ]; then
  if [ -f "${ROOT}/pyproject.toml" ]; then
    echo "select-dependabot-config: pom.xml and pyproject.toml both present; keeping the Java configuration" >&2
  fi
elif [ -f "${ROOT}/pyproject.toml" ] && [ -f "${ROOT}/uv.lock" ]; then
  language="python"
elif [ -f "${ROOT}/pyproject.toml" ]; then
  echo "select-dependabot-config: pyproject.toml found without uv.lock; keeping the Java configuration" >&2
else
  echo "select-dependabot-config: no build marker found; keeping the Java configuration" >&2
fi

selected="$JAVA_CONFIG"
if [ "$language" = "python" ]; then
  selected="$PYTHON_CONFIG"
fi

# Fall back to the Java configuration when the language-specific file is absent, so an
# older template checkout can never leave a fork without a Dependabot configuration.
if [ "$MODE" = "--print-source" ] && [ ! -f "${ROOT}/${selected}" ] && [ -f "${ROOT}/${JAVA_CONFIG}" ]; then
  echo "select-dependabot-config: ${selected} is missing; falling back to ${JAVA_CONFIG}" >&2
  selected="$JAVA_CONFIG"
  language="java"
fi

if [ "$MODE" = "--print-language" ]; then
  echo "$language"
else
  echo "$selected"
fi
