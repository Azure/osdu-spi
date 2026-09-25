#!/usr/bin/env bash
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Builds the GHCR repository path and short commit SHA for the docker-build action.
#
# Local: GITHUB_SHA=abc123def4567 GITHUB_OUTPUT=/dev/stdout ./compute-metadata.sh ghcr.io MyOrg Partition

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
