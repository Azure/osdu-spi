#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for the python-build phase scripts.
#
# Every value handled here has already been validated by resolve_build_plan.py
# (closed enums, PEP 508 extras, dotted module names, repository-relative paths),
# so comma splitting is safe and no value is ever passed through eval, a shell
# string, or a raw command input.

# Print "--extra <name>" pairs, one token per line, for a comma-separated list.
spi_extra_args() {
  local raw="${1:-}"
  local item
  local -a parts=()
  IFS=',' read -r -a parts <<< "$raw"
  for item in "${parts[@]}"; do
    [ -n "$item" ] || continue
    printf '%s\n%s\n' '--extra' "$item"
  done
}

# Print each entry of a comma-separated list on its own line.
spi_list() {
  local raw="${1:-}"
  local item
  local -a parts=()
  IFS=',' read -r -a parts <<< "$raw"
  for item in "${parts[@]}"; do
    [ -n "$item" ] || continue
    printf '%s\n' "$item"
  done
}

# True when the argument is the string "true".
spi_enabled() {
  [ "${1:-false}" = "true" ]
}

spi_group_start() {
  echo "::group::$1"
}

spi_group_end() {
  echo "::endgroup::"
}
