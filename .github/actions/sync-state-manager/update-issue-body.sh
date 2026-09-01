#!/usr/bin/env bash
#
# Refreshes the human-readable sync summary in an issue body and writes one
# canonical full-SHA marker at the end.

set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <input_file> <output_file> <upstream_version> <upstream_sha> <commit_count> <sync_branch>"
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
UPSTREAM_VERSION="$3"
UPSTREAM_SHA="$4"
COMMIT_COUNT="$5"
SYNC_BRANCH="$6"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input issue body does not exist: $INPUT_FILE"
  exit 1
fi

if [[ -z "$UPSTREAM_VERSION" ]]; then
  echo "Error: Upstream version must not be empty"
  exit 1
fi

if [[ ! "$UPSTREAM_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Error: Upstream SHA must be a 40-character lowercase hexadecimal value"
  exit 1
fi

if [[ ! "$COMMIT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Error: Commit count must be numeric"
  exit 1
fi

if [[ -z "$SYNC_BRANCH" ]]; then
  echo "Error: Sync branch must not be empty"
  exit 1
fi

awk -v upstream="$UPSTREAM_VERSION" -v sha="$UPSTREAM_SHA" -v count="$COMMIT_COUNT" -v branch="$SYNC_BRANCH" '
{
  line = $0
  sub(/\r$/, "", line)

  # Remove any prior machine marker; one canonical marker is appended below.
  if (line ~ /^<!-- upstream-sha: [^>]* -->$/) {
    next
  }

  gsub(/\*\*Upstream Version\*\*: `[^`]*`/, "**Upstream Version**: `" upstream "`", line)
  gsub(/\*\*Changes\*\*: [0-9]+ new commits from upstream/, "**Changes**: " count " new commits from upstream", line)
  gsub(/\*\*Branch\*\*: `[^`]*` → `fork_upstream`/, "**Branch**: `" branch "` → `fork_upstream`", line)

  print line
  last_was_blank = (line == "")
}
END {
  if (!last_was_blank) {
    print ""
  }
  print "<!-- upstream-sha: " sha " -->"
}
' "$INPUT_FILE" > "$OUTPUT_FILE"
