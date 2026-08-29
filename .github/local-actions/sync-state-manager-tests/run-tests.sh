#!/usr/bin/env bash
#
# Regression harness for sync-state-manager safety and persistence behavior.
#
# Usage:
#   ./run-tests.sh

# shellcheck disable=SC2016  # Assertions intentionally match literal workflow expressions.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="$HERE/../../actions/sync-state-manager"
WORKFLOW="$HERE/../../template-workflows/sync.yml"
CLEANUP="$ACTION_DIR/cleanup-abandoned-branches.sh"
CHECK_STATE="$ACTION_DIR/check-stored-state.sh"
DECIDE="$ACTION_DIR/make-sync-decision.sh"
UPDATE_BODY="$ACTION_DIR/update-issue-body.sh"
RECORD="$ACTION_DIR/record-evaluated-sha.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note() { printf '\n== %s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "variable" ]]; then
  case "${2:-}" in
    set)
      printf '%s\n' "$*" >> "$GH_VARIABLE_LOG"
      if [[ "${GH_VARIABLE_SET_FAILS:-}" == "true" ]]; then
        exit 7
      fi
      exit 0
      ;;
    get)
      if [[ -z "${GH_STORED_VARIABLE:-}" ]]; then
        exit 1
      fi
      printf '%s\n' "$GH_STORED_VARIABLE"
      exit 0
      ;;
  esac
  exit 64
fi

case "${GH_MODE:-}" in
  cleanup-fail)
    exit 42
    ;;
  cleanup-malformed)
    printf 'not-json\n'
    ;;
  cleanup-empty)
    printf '[]\n'
    ;;
  cleanup-active)
    printf '[{"number":123}]\n'
    ;;
  issue)
    case " $* " in
      *" --json body "*)
        cat "$ISSUE_BODY_FILE"
        ;;
      *" --json updatedAt "*)
        printf '2026-08-29T00:00:00Z\n'
        ;;
      *)
        exit 64
        ;;
    esac
    ;;
  *)
    exit 64
    ;;
esac
EOF

cat > "$BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "branch" && "${2:-}" == "-r" ]]; then
  printf '  origin/sync/upstream-20200101-000000\n'
elif [[ "$1" == "push" ]]; then
  printf '%s\n' "$*" >> "$GIT_CALL_LOG"
else
  exit 64
fi
EOF

cat > "$BIN/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  +%s)
    printf '2000000000\n'
    ;;
  --version)
    printf 'test date\n'
    ;;
  -d)
    printf '1000000000\n'
    ;;
  *)
    exit 64
    ;;
esac
EOF

chmod +x "$BIN/gh" "$BIN/git" "$BIN/date"

run_cleanup() {
  GH_MODE="$1" GIT_CALL_LOG="$TMP/git-calls" PATH="$BIN:$PATH" "$CLEANUP"
}

note "cleanup: failed PR reads never delete branches"
: > "$TMP/git-calls"
OUTPUT=$(run_cleanup cleanup-fail)
grep -q "exit code: 42" <<< "$OUTPUT" || die "gh exit code was not preserved"
[[ ! -s "$TMP/git-calls" ]] || die "gh failure attempted branch deletion"
ok "gh failure skips deletion"

note "cleanup: malformed PR responses never delete branches"
: > "$TMP/git-calls"
OUTPUT=$(run_cleanup cleanup-malformed)
grep -q "failed to parse PR lookup response" <<< "$OUTPUT" || die "parse failure was not reported"
[[ ! -s "$TMP/git-calls" ]] || die "parse failure attempted branch deletion"
ok "parse failure skips deletion"

note "cleanup: old branches without PRs are deleted"
: > "$TMP/git-calls"
run_cleanup cleanup-empty > /dev/null
grep -q "push origin --delete sync/upstream-20200101-000000" "$TMP/git-calls" || die "abandoned branch was not deleted"
ok "empty PR result deletes the abandoned branch"

note "cleanup: branches with active PRs are retained"
: > "$TMP/git-calls"
OUTPUT=$(run_cleanup cleanup-active)
grep -q "associated PR #123" <<< "$OUTPUT" || die "active PR was not detected"
[[ ! -s "$TMP/git-calls" ]] || die "active PR branch was deleted"
ok "active PR keeps the branch"

SHA="0123456789abcdef0123456789abcdef01234567"
OLD_SHA="0000000000000000000000000000000000000000"

note "issue body: legacy bodies gain one marker at the end"
cat > "$TMP/legacy.md" <<'EOF'
**Sync Summary**
- **Upstream Version**: `old`
- **Changes**: 3 new commits from upstream
- **Branch**: `sync/upstream-old` → `fork_upstream`

**Timeline**
- **Current status**: Awaiting PR review and merge
EOF

"$UPDATE_BODY" "$TMP/legacy.md" "$TMP/legacy-updated.md" "v2.0.0" "$SHA" "7" "sync/upstream-new"
[[ "$(tail -n 1 "$TMP/legacy-updated.md")" == "<!-- upstream-sha: $SHA -->" ]] || die "marker was not appended"
[[ -z "$(tail -n 2 "$TMP/legacy-updated.md" | head -n 1)" ]] || die "marker is not separated by a blank line"
[[ "$(grep -c '<!-- upstream-sha:' "$TMP/legacy-updated.md")" -eq 1 ]] || die "legacy body has multiple markers"
grep -Fq -- '- **Upstream Version**: `v2.0.0`' "$TMP/legacy-updated.md" || die "upstream version was not updated"
grep -Fq -- '- **Changes**: 7 new commits from upstream' "$TMP/legacy-updated.md" || die "commit count was not updated"
ok "legacy body upgraded without splitting summary lists"

note "issue body: current and CRLF bodies normalize and refresh"
printf '%s\r\n' \
  '**Sync Summary**' \
  '- **Upstream Version**: `old`' \
  '- **Changes**: 3 new commits from upstream' \
  '- **Branch**: `sync/upstream-old` → `fork_upstream`' \
  '' \
  '<!-- upstream-sha: 0000000000000000000000000000000000000000 -->' > "$TMP/current-crlf.md"

"$UPDATE_BODY" "$TMP/current-crlf.md" "$TMP/current-updated.md" "v2.0.0" "$SHA" "7" "sync/upstream-new"
[[ "$(grep -c '<!-- upstream-sha:' "$TMP/current-updated.md")" -eq 1 ]] || die "current body has multiple markers"
grep -Fq "<!-- upstream-sha: $SHA -->" "$TMP/current-updated.md" || die "current marker was not refreshed"
! grep -q "$OLD_SHA" "$TMP/current-updated.md" || die "old marker survived"
! grep -q $'\r' "$TMP/current-updated.md" || die "CRLF input was not normalized"
ok "current marker refreshed and CRLF normalized"

note "issue body: incomplete state is rejected"
if "$UPDATE_BODY" "$TMP/legacy.md" "$TMP/invalid.md" "v2.0.0" "" "7" "sync/upstream-new" >/dev/null 2>&1; then
  die "empty upstream SHA was accepted"
fi
[[ ! -e "$TMP/invalid.md" ]] || die "invalid update wrote an output body"
ok "empty SHA cannot wipe the marker"

read_stored_sha() {
  local body_file="$1"
  GH_MODE=issue ISSUE_BODY_FILE="$body_file" PATH="$BIN:$PATH" "$CHECK_STATE" 42 |
    awk -F= '$1 == "last_upstream_sha" { print $2; exit }'
}

note "stored state: marker round-trips through the parser"
[[ "$(read_stored_sha "$TMP/current-updated.md")" == "$SHA" ]] || die "full SHA did not round-trip"
ok "full SHA round-trips"

note "stored state: CRLF marker bodies parse"
printf '%s\r\n' "Summary" "<!-- upstream-sha: $SHA -->" > "$TMP/parser-crlf.md"
[[ "$(read_stored_sha "$TMP/parser-crlf.md")" == "$SHA" ]] || die "CRLF marker did not parse"
ok "CRLF marker parses"

note "stored state: legacy bodies degrade to empty"
[[ -z "$(read_stored_sha "$TMP/legacy.md")" ]] || die "legacy body produced a false SHA"
ok "missing marker remains backward compatible"

note "decision: equal full SHAs keep the existing PR unchanged"
DECISION=$("$DECIDE" "$SHA" "$SHA" true true 10 20 sync/upstream-test)
grep -q "Upstream changed: false" <<< "$DECISION" || die "equal SHAs were treated as changed"
grep -q "sync_decision=add_reminder" <<< "$DECISION" || die "equal SHAs did not select add_reminder"
grep -q "Existing PR remains current" <<< "$DECISION" || die "unchanged decision message is inaccurate"
ok "duplicate state keeps existing artifacts unchanged"

note "decision: an existing PR without an open issue remains non-mutating"
DECISION=$("$DECIDE" "$SHA" "$SHA" true false 10 "" sync/upstream-test)
grep -q "sync_decision=add_reminder" <<< "$DECISION" || die "existing PR without issue changed compatibility decision"
ok "missing tracking issue does not require a reminder side effect"

note "durable state: malformed SHAs are never recorded"
export GH_VARIABLE_LOG="$TMP/variable.log"
: > "$GH_VARIABLE_LOG"
if PATH="$BIN:$PATH" "$RECORD" "not-a-sha" >/dev/null 2>&1; then
  die "a malformed SHA was recorded"
fi
[[ ! -s "$GH_VARIABLE_LOG" ]] || die "a rejected SHA still reached gh variable set"
ok "malformed SHA is rejected before any write"

note "durable state: a no-op evaluation records the full SHA"
PATH="$BIN:$PATH" "$RECORD" "$SHA" >/dev/null
grep -Fq "variable set SYNC_LAST_EVALUATED_SHA --body $SHA" "$GH_VARIABLE_LOG" ||
  die "evaluated SHA was not written to the durable variable"
ok "no-op evaluation persists the evaluated SHA"

note "durable state: a failed write degrades instead of failing the sync"
GH_VARIABLE_SET_FAILS=true PATH="$BIN:$PATH" "$RECORD" "$SHA" > "$TMP/record-fail.log" ||
  die "a failed variable write failed the sync run"
grep -q "next run will re-evaluate" "$TMP/record-fail.log" || die "failed write was not reported"
ok "unwritable state costs a repeat, not a red run"

read_durable_sha() {
  GH_STORED_VARIABLE="$1" PATH="$BIN:$PATH" "$CHECK_STATE" "" |
    awk -F= '$1 == "last_upstream_sha" { print $2; exit }'
}

note "durable state: with no tracking issue the variable supplies the last SHA"
[[ "$(read_durable_sha "$SHA")" == "$SHA" ]] || die "durable variable was not consulted"
ok "no-issue runs read durable state"

note "durable state: an unusable stored value degrades to empty"
[[ -z "$(read_durable_sha "deadbeef")" ]] || die "a short SHA was accepted as state"
[[ -z "$(read_durable_sha "")" ]] || die "an unset variable produced a false SHA"
ok "invalid durable state compares as changed"

note "durable state: an open tracking issue outranks the variable"
printf '%s\n' "Summary" "<!-- upstream-sha: $OLD_SHA -->" > "$TMP/active-cycle.md"
ACTIVE=$(GH_MODE=issue ISSUE_BODY_FILE="$TMP/active-cycle.md" GH_STORED_VARIABLE="$SHA" \
  PATH="$BIN:$PATH" "$CHECK_STATE" 42 | awk -F= '$1 == "last_upstream_sha" { print $2; exit }')
[[ "$ACTIVE" == "$OLD_SHA" ]] || die "durable state hijacked an active sync cycle"
ok "active cycle keeps driving from the issue marker"

note "decision: a re-evaluated no-op SHA takes no action at all"
DECISION=$("$DECIDE" "$SHA" "$SHA" false false "" "" "")
grep -q "sync_decision=no_action" <<< "$DECISION" || die "repeat no-op SHA did not select no_action"
grep -q "should_create_pr=false" <<< "$DECISION" || die "repeat no-op SHA would regenerate a branch"
ok "repeat no-op SHA skips generation"

note "workflow: order-dependent state exports and marker placement stay pinned"
EXPORT_LINE=$(grep -nF 'echo "UPSTREAM_SHA=$UPSTREAM_SHA" >> "$GITHUB_ENV"' "$WORKFLOW" | cut -d: -f1)
EARLY_EXIT_LINE=$(grep -nF 'if [ "$has_changes" = "false" ]; then' "$WORKFLOW" | cut -d: -f1)
[[ "$EXPORT_LINE" -lt "$EARLY_EXIT_LINE" ]] || die "upstream SHA export moved after the no-change exit"

MARKER_LINE=$(grep -nF '<!-- upstream-sha: $UPSTREAM_SHA -->' "$WORKFLOW" | cut -d: -f1)
STATUS_LINE=$(grep -nF -- '"- **Current status**: Awaiting PR review and merge"' "$WORKFLOW" | cut -d: -f1)
[[ "$MARKER_LINE" == "$STATUS_LINE" ]] || die "new issue marker is not appended after the timeline"

grep -Fq "if: steps.sync-state.outputs.sync_decision == 'update_existing'" "$WORKFLOW" || die "issue update is not limited to update_existing"
if grep -Fq -- '- name: Add reminder to existing sync issue' "$WORKFLOW"; then
  die "add_reminder posts recurring issue notifications"
fi
grep -Fq '"add_reminder")' "$WORKFLOW" || die "compatibility decision is not logged"

RECORD_LINE=$(grep -nF 'record-evaluated-sha.sh "$UPSTREAM_SHA"' "$WORKFLOW" | cut -d: -f1)
WORKTREE_LINE=$(grep -nF 'SYNC_WORKTREE="$RUNNER_TEMP/sync-worktree"' "$WORKFLOW" | cut -d: -f1)
[[ "$RECORD_LINE" -gt "$EARLY_EXIT_LINE" && "$RECORD_LINE" -lt "$WORKTREE_LINE" ]] ||
  die "evaluated SHA is not recorded inside the no-change exit"
ok "workflow invariants hold"

printf '\nAll sync-state-manager tests passed\n'
