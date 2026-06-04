#!/usr/bin/env bash
#
# Compute Image Tags Script
#
# Computes the container image tags for the docker-build action.
#
# Arguments:
#   $1 - image repository (e.g. ghcr.io/org/partition)
#   $2 - short commit SHA (12 chars)
#   $3 - git ref name (branch or tag, from github.ref_name)
#   $4 - push flag (true/false)
#
# Tagging strategy:
#   :sha-<short>        always
#   :<branch>-snapshot  only when push=true AND branch is protected (main, fork_integration, fork_upstream)
#   :<version>          NOT emitted here — release.yml (W7) owns the version retag
#
# Outputs (via GITHUB_OUTPUT):
#   image_tags  - comma-separated tag list (human/log use only)
#   docker_tags - newline-separated tag list (fed to docker/build-push-action `tags:`)
#
# Local usage:
#   GITHUB_OUTPUT=/dev/stdout ./compute-tags.sh ghcr.io/org/partition abc123def456 main true

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

# Branch-snapshot tag only on the push path for protected branches
# (matches the Maven -Drevision=<branch>-SNAPSHOT convention)
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
