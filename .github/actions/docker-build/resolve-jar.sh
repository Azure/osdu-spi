#!/usr/bin/env bash
#
# Resolves the Spring Boot JAR the Dockerfile COPYs (ADR-037).
#
# REQUESTED_JAR is the conventional provider/<service>-azure/target/*-spring-boot.jar
# or a SERVICE_TARGET_JAR override. A fork whose Azure module name deviates from the
# repository name (entitlements -> entitlements-v2-azure) matches nothing, so the
# script then discovers the Azure Spring Boot JAR and a fresh fork builds with no
# manual variable. SERVICE_TARGET_JAR is only needed to disambiguate a service that
# builds more than one Azure Spring Boot JAR.
#
# Paths resolve relative to BUILD_CONTEXT: the COPY is context-relative and the
# build artifacts download into the context.
#
# Env: REQUESTED_JAR (optional), IMAGE_NAME (default-path stem and tiebreaker),
#      BUILD_CONTEXT (default ".")
# Local: IMAGE_NAME=partition GITHUB_OUTPUT=/dev/stdout ./resolve-jar.sh

set -euo pipefail
shopt -s nullglob

REQUESTED_JAR="${REQUESTED_JAR:-}"
IMAGE_NAME="${IMAGE_NAME:-}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"

cd "$BUILD_CONTEXT"

if [[ -z "$REQUESTED_JAR" ]]; then
  if [[ -z "$IMAGE_NAME" ]]; then
    echo "::error::Provide jar_file or image_name so the service JAR can be resolved."
    exit 1
  fi
  REQUESTED_JAR="provider/${IMAGE_NAME}-azure/target/*-spring-boot.jar"
fi

resolved=""

# 1. The requested path, when it resolves.
# shellcheck disable=SC2206  # deliberate: glob-expand the path/override into matches
requested_matches=( $REQUESTED_JAR )
if [[ ${#requested_matches[@]} -ge 1 ]]; then
  resolved="${requested_matches[0]}"
  if [[ ${#requested_matches[@]} -gt 1 ]]; then
    echo "::warning::'$REQUESTED_JAR' matched ${#requested_matches[@]} files; using $resolved"
  fi
else
  # 2. Discover the Azure Spring Boot JAR the build produced.
  discovered=( provider/*-azure/target/*-spring-boot.jar )
  if [[ ${#discovered[@]} -eq 1 ]]; then
    resolved="${discovered[0]}"
    echo "'$REQUESTED_JAR' matched no file; discovered Azure JAR: $resolved"
  elif [[ ${#discovered[@]} -gt 1 ]]; then
    # 3. Tiebreak on the service slug, otherwise fail here rather than at COPY.
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
