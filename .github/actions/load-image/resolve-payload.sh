#!/usr/bin/env bash
#
# Decides whether the loader image can build: the checkout must carry the shared
# schemas payload, and then every loader file the Dockerfile copies must be there.
# An absent payload is a clean skip (most forks). A payload without its loader is
# an upstream rename and halts with exit 2 naming the missing file. The paths are
# the ones build/load.Dockerfile and its dockerignore hard-code.
#
# Local: GITHUB_OUTPUT=/dev/stdout ./resolve-payload.sh

set -euo pipefail

PAYLOAD_DIR="deployments/shared-schemas"
LOADER_DIR="deployments/scripts"
LOADER_FILES=(DeploySharedSchemas.py Utility.py requirements.txt)

BUILDABLE="true"
REASON=""
if [[ ! -d "$PAYLOAD_DIR" ]]; then
  BUILDABLE="false"
  REASON="payload directory '$PAYLOAD_DIR' not present"
else
  for file in "${LOADER_FILES[@]}"; do
    if [[ ! -f "$LOADER_DIR/$file" ]]; then
      echo "::error::$PAYLOAD_DIR is present but the loader file '$LOADER_DIR/$file' is missing; the shared loader moved upstream"
      exit 2
    fi
  done
fi

{
  echo "payload_dir=$PAYLOAD_DIR"
  echo "loader_dir=$LOADER_DIR"
  echo "buildable=$BUILDABLE"
  echo "reason=$REASON"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [[ "$BUILDABLE" == "true" ]]; then
  echo "✓ payload: $PAYLOAD_DIR with loader $LOADER_DIR/${LOADER_FILES[0]}"
else
  echo "ℹ load image skipped: $REASON"
fi
