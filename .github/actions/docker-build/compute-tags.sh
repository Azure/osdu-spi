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
# Computes the image tags for the docker-build action:
#   :sha-<short>        always
#   :<branch>-snapshot  only when push=true and the branch is protected
#   :<version>          never here; release.yml owns the version retag
#
# docker_tags (newline-separated) feeds docker/build-push-action; image_tags
# (comma-separated) is for logs only.
#
# Local: GITHUB_OUTPUT=/dev/stdout ./compute-tags.sh ghcr.io/org/partition abc123def456 main true

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <image_repository> <short_sha> <ref_name> <push>"
  exit 1
fi

IMAGE_REPOSITORY="$1"
SHORT_SHA="$2"
REF_NAME="$3"
PUSH="$4"

TAGS=("${IMAGE_REPOSITORY}:sha-${SHORT_SHA}")

# Snapshot tags mirror the Maven -Drevision=<branch>-SNAPSHOT convention.
if [[ "$PUSH" == "true" ]]; then
  case "$REF_NAME" in
    main|fork_integration|fork_upstream)
      TAGS+=("${IMAGE_REPOSITORY}:${REF_NAME}-snapshot")
      ;;
  esac
fi

IMAGE_TAGS="$(IFS=,; echo "${TAGS[*]}")"

echo "Computed tags:"
printf '  %s\n' "${TAGS[@]}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "image_tags=$IMAGE_TAGS" >> "$GITHUB_OUTPUT"
  {
    echo "docker_tags<<EOF"
    printf '%s\n' "${TAGS[@]}"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
fi

echo "image_tags=$IMAGE_TAGS"
