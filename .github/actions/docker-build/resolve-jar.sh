#!/usr/bin/env bash
#
# Resolve the service Spring Boot JAR to COPY into the image (ADR-037).
#
# The caller passes REQUESTED_JAR — the conventional path
# provider/<service>-azure/target/*-spring-boot.jar (or a SERVICE_TARGET_JAR override).
# Most forks match it directly. A fork whose Azure module name deviates from the repo
# name (e.g. entitlements -> entitlements-v2-azure) matches nothing; rather than fail the
# build — and, post-W10, the required check — we discover the Azure Spring Boot JAR so a
# fresh fork builds with no manual variable and no first failure. SERVICE_TARGET_JAR is
# needed only to disambiguate a service that builds more than one Azure Spring Boot JAR.
#
# Paths resolve relative to BUILD_CONTEXT: the Dockerfile COPY is context-relative and the
# build artifacts download into the context, so the emitted path must be context-relative too.
#
# Environment:
#   REQUESTED_JAR  path/override glob relative to the build context; when empty, defaults to
#                  the conventional provider/<IMAGE_NAME>-azure/target/*-spring-boot.jar
#   IMAGE_NAME     service slug — the default-path stem and the multi-match tiebreaker
#   BUILD_CONTEXT  Docker build context directory (default ".")
#   GITHUB_OUTPUT  receives jar_file=<resolved path> when set
#
# Local test (from a dir containing provider/<svc>-azure/target/*-spring-boot.jar):
#   IMAGE_NAME=partition GITHUB_OUTPUT=/dev/stdout ./resolve-jar.sh

set -euo pipefail
shopt -s nullglob

REQUESTED_JAR="${REQUESTED_JAR:-}"
IMAGE_NAME="${IMAGE_NAME:-}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"

# COPY is build-context-relative and artifacts download into the context: resolve there.
cd "$BUILD_CONTEXT"

# Fall back to the conventional path when the caller passes no jar_file.
if [[ -z "$REQUESTED_JAR" ]]; then
  if [[ -z "$IMAGE_NAME" ]]; then
    echo "::error::Provide jar_file or image_name so the service JAR can be resolved."
    exit 1
  fi
  REQUESTED_JAR="provider/${IMAGE_NAME}-azure/target/*-spring-boot.jar"
fi

resolved=""

# 1. Honour the requested path when it resolves (common <name>-azure case + explicit override).
# shellcheck disable=SC2206  # deliberate: glob-expand the path/override into matches
requested_matches=( $REQUESTED_JAR )
if [[ ${#requested_matches[@]} -ge 1 ]]; then
  resolved="${requested_matches[0]}"
  if [[ ${#requested_matches[@]} -gt 1 ]]; then
    echo "::warning::'$REQUESTED_JAR' matched ${#requested_matches[@]} files; using $resolved"
  fi
else
  # 2. Deviant module path: discover the Azure Spring Boot JAR the build produced.
  discovered=( provider/*-azure/target/*-spring-boot.jar )
  if [[ ${#discovered[@]} -eq 1 ]]; then
    resolved="${discovered[0]}"
    echo "'$REQUESTED_JAR' matched no file; discovered Azure JAR: $resolved"
  elif [[ ${#discovered[@]} -gt 1 ]]; then
    # 3. Tiebreak on the service slug; otherwise fail loud (never a cryptic COPY error).
    preferred=()
    for d in "${discovered[@]}"; do
      [[ "$d" == provider/*"${IMAGE_NAME}"*-azure/* ]] && preferred+=("$d")
    done
    if [[ ${#preferred[@]} -eq 1 ]]; then
      resolved="${preferred[0]}"
      echo "Disambiguated ${#discovered[@]} Azure JARs by service name '${IMAGE_NAME}': $resolved"
    else
      echo "::error::Found ${#discovered[@]} Azure Spring Boot JARs and could not disambiguate (${discovered[*]}). Set the SERVICE_TARGET_JAR repository variable to the correct path."
      exit 1
    fi
  else
    echo "::error::No Spring Boot JAR matched '$REQUESTED_JAR' or provider/*-azure/target/*-spring-boot.jar. Confirm the java-build artifact downloaded, or set SERVICE_TARGET_JAR."
    exit 1
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "jar_file=$resolved" >> "$GITHUB_OUTPUT"
fi
echo "Resolved service JAR: $resolved"
