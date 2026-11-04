#!/usr/bin/env bash
# Adds <dst> as an alias of <src> in the registry. Waits for <src> to appear, and refuses to move
# an existing <dst> that points at a different digest.
set -euo pipefail

SRC="$1"
DST="$2"
ATTEMPTS="${RETAG_ATTEMPTS:-60}"
INTERVAL="${RETAG_INTERVAL:-20}"

# Prints the digest, or nothing when the registry answers "not found". Any other error fails,
# so a registry hiccup can never be mistaken for a missing tag.
digest() {
  local out
  if out=$(docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>&1); then
    jq -r '.digest // empty' <<< "$out"
  elif grep -q ': not found' <<< "$out"; then
    return 0
  else
    echo "$out" >&2
    return 1
  fi
}

lookup() {
  local attempt
  for attempt in 1 2 3; do
    digest "$1" && return 0
    sleep 5
  done
  return 1
}

src_digest=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  src_digest=$(lookup "$SRC") || { echo "::error::could not inspect ${SRC}"; exit 1; }
  [ -n "$src_digest" ] && break
  echo "Source ${SRC} not present yet (attempt ${attempt}/${ATTEMPTS}); waiting for its push…"
  sleep "$INTERVAL"
done
if [ -z "$src_digest" ]; then
  echo "::error::${SRC} did not appear within $((ATTEMPTS * INTERVAL / 60)) min; the push for the release commit may have failed."
  exit 1
fi

dst_digest=$(lookup "$DST") || { echo "::error::could not inspect ${DST}; refusing to tag without knowing what it points at"; exit 1; }
if [ -n "$dst_digest" ]; then
  if [ "$dst_digest" = "$src_digest" ]; then
    echo "\`${DST}\` already points at \`${src_digest}\`" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
    exit 0
  fi
  echo "::error::${DST} already points at ${dst_digest}, not ${src_digest} from ${SRC}; a version tag is never moved."
  exit 1
fi

# --prefer-index=false copies a single-platform manifest as is, so the tag keeps the source digest.
docker buildx imagetools create --prefer-index=false --tag "$DST" "$SRC"
echo "Tagged \`${DST}\` from \`${SRC}\` (\`${src_digest}\`)" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
