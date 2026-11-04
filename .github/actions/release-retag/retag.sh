#!/usr/bin/env bash
# Adds <dst> as an alias of <src> in the registry. Waits for <src> to appear, and refuses to move
# an existing <dst> that points at a different digest.
set -euo pipefail

SRC="$1"
DST="$2"
ATTEMPTS="${RETAG_ATTEMPTS:-60}"
INTERVAL="${RETAG_INTERVAL:-20}"

digest() {
  docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>/dev/null | jq -r '.digest // empty'
}

src_digest=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  src_digest=$(digest "$SRC" || true)
  [ -n "$src_digest" ] && break
  echo "Source ${SRC} not present yet (attempt ${attempt}/${ATTEMPTS}); waiting for its push…"
  sleep "$INTERVAL"
done
if [ -z "$src_digest" ]; then
  echo "::error::${SRC} did not appear within $((ATTEMPTS * INTERVAL / 60)) min; the push for the release commit may have failed."
  exit 1
fi

dst_digest=$(digest "$DST" || true)
if [ -n "$dst_digest" ]; then
  if [ "$dst_digest" = "$src_digest" ]; then
    echo "\`${DST}\` already points at \`${src_digest}\`" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
    exit 0
  fi
  echo "::error::${DST} already points at ${dst_digest}, not ${src_digest} from ${SRC}; a version tag is never moved."
  exit 1
fi

docker buildx imagetools create --tag "$DST" "$SRC"
echo "Tagged \`${DST}\` from \`${SRC}\` (\`${src_digest}\`)" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
