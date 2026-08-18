#!/usr/bin/env bash
#
# Resolve the build mode, Dockerfile, platform list and --build-arg set.
#
# Two modes exist so one action can back both canonical images (ADR-037):
#
#   java-artifact (default)  the Java lane: the caller downloaded build-artifacts and
#                            resolve-jar.sh produced JAR_FILE. Nothing else is passed,
#                            so the Java build arguments are exactly what they were
#                            before source mode existed.
#   source                   the Python lane: the image is built from the checked-out
#                            source plus the committed lockfile, so no artifact is
#                            downloaded and no JAR is resolved. APP_MODULE and
#                            RUNTIME_EXTRAS come from the fork-owned service descriptor
#                            and are re-validated here (defence in depth) before they
#                            reach a build argument.
#
# Credentials are never a build argument: build arguments are recorded in image
# history. A private package index is configured through the Dockerfile's optional
# BuildKit netrc secret mount instead.
#
# Environment:
#   BUILD_MODE       java-artifact | source
#   DOCKERFILE_PATH  caller-supplied Dockerfile path (the java default is remapped to
#                    the canonical Python profile in source mode)
#   BUILD_CONTEXT    docker build context (default ".")
#   JAR_FILE         resolved JAR path (java-artifact mode only)
#   APP_MODULE       ASGI target, e.g. wdmsworker.app:app (source mode, required)
#   RUNTIME_EXTRAS   comma-separated extras, e.g. az (source mode, optional)
#   PLATFORMS        explicit platform list; empty keeps the existing defaults
#   PUSH             true | false
#   IMAGE_SOURCE     repository URL for the OCI source label (source mode)
#   IMAGE_REVISION   commit SHA for the OCI revision label (source mode)
#   IMAGE_VERSION    short SHA for the OCI version label (source mode)
#   GITHUB_OUTPUT    receives build_args, dockerfile, platforms and needs_qemu
#
# Local test:
#   BUILD_MODE=source APP_MODULE=demo.app:app GITHUB_OUTPUT=/dev/stdout \
#     ./prepare-build-args.sh

set -euo pipefail

BUILD_MODE="${BUILD_MODE:-java-artifact}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-build/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
JAR_FILE="${JAR_FILE:-}"
APP_MODULE="${APP_MODULE:-}"
RUNTIME_EXTRAS="${RUNTIME_EXTRAS:-}"
PLATFORMS="${PLATFORMS:-}"
PUSH="${PUSH:-true}"

JAVA_DEFAULT_DOCKERFILE="build/Dockerfile"
PYTHON_DOCKERFILE="build/python/Dockerfile"

fail() {
  echo "::error::$1"
  exit 1
}

# Anchored patterns reject newlines as well as shell metacharacters, so no value can
# smuggle a second build argument into the newline-separated list.
APP_MODULE_RE='^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*:[A-Za-z_][A-Za-z0-9_]*$'
EXTRAS_RE='^[A-Za-z0-9][A-Za-z0-9._,-]*$'
PLATFORMS_RE='^linux/[a-z0-9]+(/v[0-9]+)?(,linux/[a-z0-9]+(/v[0-9]+)?)*$'
SHA_RE='^[0-9a-fA-F]{7,64}$'

case "$BUILD_MODE" in
  java-artifact|source) ;;
  *) fail "Invalid build_mode '${BUILD_MODE}' (expected 'java-artifact' or 'source')." ;;
esac

if [[ -n "$PLATFORMS" ]]; then
  [[ "$PLATFORMS" =~ $PLATFORMS_RE ]] || fail "Invalid platforms '${PLATFORMS}' (expected e.g. linux/amd64 or linux/amd64,linux/arm64)."
  EFFECTIVE_PLATFORMS="$PLATFORMS"
elif [[ "$PUSH" == "true" ]]; then
  EFFECTIVE_PLATFORMS="linux/amd64,linux/arm64"
else
  EFFECTIVE_PLATFORMS="linux/amd64"
fi

# QEMU is only needed for an emulated (non-amd64) leg.
NEEDS_QEMU=false
IFS=',' read -r -a platform_list <<< "$EFFECTIVE_PLATFORMS"
for platform in "${platform_list[@]}"; do
  [[ "$platform" == "linux/amd64" ]] || NEEDS_QEMU=true
done

DOCKERFILE="$DOCKERFILE_PATH"
BUILD_ARGS=()

if [[ "$BUILD_MODE" == "source" ]]; then
  # A source-mode caller that left the Java default in place gets the canonical Python
  # profile; an explicit path always wins.
  if [[ -z "$DOCKERFILE" || "$DOCKERFILE" == "$JAVA_DEFAULT_DOCKERFILE" ]]; then
    DOCKERFILE="$PYTHON_DOCKERFILE"
  fi
  [[ -f "$DOCKERFILE" ]] || fail "Dockerfile '${DOCKERFILE}' was not found; source mode builds the canonical ${PYTHON_DOCKERFILE}."

  [[ -n "$APP_MODULE" ]] || fail "build_mode=source requires app_module (the descriptor's container.appModule, e.g. wdmsworker.app:app)."
  [[ "$APP_MODULE" =~ $APP_MODULE_RE ]] || fail "Invalid app_module '${APP_MODULE}' (expected <dotted.module>:<attribute>)."
  BUILD_ARGS+=("APP_MODULE=${APP_MODULE}")

  if [[ -n "$RUNTIME_EXTRAS" ]]; then
    [[ "$RUNTIME_EXTRAS" =~ $EXTRAS_RE ]] || fail "Invalid runtime_extras '${RUNTIME_EXTRAS}' (expected comma-separated extra names)."
    BUILD_ARGS+=("RUNTIME_EXTRAS=${RUNTIME_EXTRAS}")
  fi

  if [[ -n "${IMAGE_SOURCE:-}" ]]; then
    BUILD_ARGS+=("IMAGE_SOURCE=${IMAGE_SOURCE}")
  fi
  if [[ -n "${IMAGE_REVISION:-}" ]]; then
    [[ "${IMAGE_REVISION}" =~ $SHA_RE ]] || fail "Invalid image revision '${IMAGE_REVISION}' (expected a commit SHA)."
    BUILD_ARGS+=("IMAGE_REVISION=${IMAGE_REVISION}")
  fi
  if [[ -n "${IMAGE_VERSION:-}" ]]; then
    [[ "${IMAGE_VERSION}" =~ $SHA_RE ]] || fail "Invalid image version '${IMAGE_VERSION}' (expected a short commit SHA)."
    BUILD_ARGS+=("IMAGE_VERSION=${IMAGE_VERSION}")
  fi
else
  [[ -n "$JAR_FILE" ]] || fail "build_mode=java-artifact requires a resolved JAR (resolve-jar.sh produced none)."
  BUILD_ARGS+=("JAR_FILE=${JAR_FILE}")
fi

echo "Build mode: ${BUILD_MODE}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Build context: ${BUILD_CONTEXT}"
echo "Platforms: ${EFFECTIVE_PLATFORMS} (QEMU: ${NEEDS_QEMU})"
printf 'Build argument: %s\n' "${BUILD_ARGS[@]}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "dockerfile=${DOCKERFILE}"
    echo "platforms=${EFFECTIVE_PLATFORMS}"
    echo "needs_qemu=${NEEDS_QEMU}"
    echo "build_args<<SPI_BUILD_ARGS_EOF"
    printf '%s\n' "${BUILD_ARGS[@]}"
    echo "SPI_BUILD_ARGS_EOF"
  } >> "$GITHUB_OUTPUT"
fi
