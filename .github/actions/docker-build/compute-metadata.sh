#!/usr/bin/env bash
#
# Compute Image Metadata Script
#
# Builds the GHCR repository path and short commit SHA used by the docker-build action.
#
# Arguments:
#   $1 - registry host (e.g. ghcr.io)
#   $2 - org/owner (e.g. my-org)
#   $3 - image name / short service name (e.g. partition)
#
# Outputs (via GITHUB_OUTPUT):
#   image_repository - lowercased "<registry>/<org>/<image_name>" (GHCR rejects uppercase)
#   short_sha        - first 12 chars of GITHUB_SHA
#
# Local usage:
#   GITHUB_SHA=abc123def4567 GITHUB_OUTPUT=/dev/stdout ./compute-metadata.sh ghcr.io MyOrg Partition

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <registry> <org> <image_name>"
  exit 1
fi

REGISTRY="$1"
ORG="$2"
IMAGE_NAME="$3"

# GHCR rejects uppercase repository paths
IMAGE_REPOSITORY="$(echo "${REGISTRY}/${ORG}/${IMAGE_NAME}" | tr '[:upper:]' '[:lower:]')"
SHORT_SHA="${GITHUB_SHA:0:12}"

echo "Image metadata:"
echo "  Repository: $IMAGE_REPOSITORY"
echo "  Short SHA:  $SHORT_SHA"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "image_repository=$IMAGE_REPOSITORY" >> "$GITHUB_OUTPUT"
  echo "short_sha=$SHORT_SHA" >> "$GITHUB_OUTPUT"
fi

echo "image_repository=$IMAGE_REPOSITORY"
echo "short_sha=$SHORT_SHA"
