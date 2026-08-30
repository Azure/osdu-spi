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
GEN_REV="$ACTION_DIR/generation-rev.sh"
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

if [[ "${1:-}" == "variable" && "${2:-}" == "set" ]]; then
  printf '%s\n' "$*" >> "$GH_VARIABLE_LOG"
  if [[ "${GH_VARIABLE_SET_FAILS:-}" == "true" ]]; then
    exit 7
  fi
  exit 0
fi

if [[ "${1:-}" == "api" && "$*" == *"/actions/variables/"* ]]; then
  case "${GH_VARIABLE_READ:-notfound}" in
    notfound)
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
      ;;
    denied)
      echo "gh: Bad credentials (HTTP 401)" >&2
      exit 1
      ;;
    *)
      printf '%s\n' "$GH_VARIABLE_READ"
      exit 0
      ;;
  esac
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

REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Only the branch listing and destructive push are faked; everything else is
# real git so scripts that hash or resolve files still work under the stub.
if [[ "\$1" == "branch" && "\${2:-}" == "-r" ]]; then
  printf '  origin/sync/upstream-20200101-000000\n'
elif [[ "\$1" == "push" ]]; then
  printf '%s\n' "\$*" >> "\$GIT_CALL_LOG"
else
  exec "$REAL_GIT" "\$@"
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

note "durable state: the generation revision reflects its inputs"
REV_NOW="$("$GEN_REV")"
[[ -n "$REV_NOW" ]] || die "generation revision is empty"
[[ "$(SYNC_MODE=mirror "$GEN_REV")" == "mirror" ]] || die "mirror mode did not short-circuit the revision"
[[ "$(SYNC_MODE=mirror "$GEN_REV")" != "$REV_NOW" ]] || die "mirror and filter share a revision"
mkdir -p "$TMP/fixture/.github/actions/upstream-filter"
printf 'service: demo\n' > "$TMP/fixture/.github/upstream-filter.yml"
printf 'ENGINE_VERSION = "1.0.0"\n' > "$TMP/fixture/.github/actions/upstream-filter/upstream_filter.py"
printf 'set -euo pipefail\n' > "$TMP/fixture/.github/actions/upstream-filter/generate-branch.sh"
REV_A="$("$GEN_REV" "$TMP/fixture")"
printf 'service: demo\ntop_level:\n  docs: keep\n' > "$TMP/fixture/.github/upstream-filter.yml"
REV_B="$("$GEN_REV" "$TMP/fixture")"
[[ "$REV_A" != "$REV_B" ]] || die "a filter config change did not change the revision"
printf 'ENGINE_VERSION = "1.1.0"\n' > "$TMP/fixture/.github/actions/upstream-filter/upstream_filter.py"
REV_C="$("$GEN_REV" "$TMP/fixture")"
[[ "$REV_B" != "$REV_C" ]] || die "an engine change did not change the revision"
printf 'set -euo pipefail\necho changed\n' > "$TMP/fixture/.github/actions/upstream-filter/generate-branch.sh"
REV_D="$("$GEN_REV" "$TMP/fixture")"
[[ "$REV_C" != "$REV_D" ]] || die "a generator change did not change the revision"
ok "revision tracks filter config, engine, generator, and sync mode"

note "durable state: malformed SHAs are never recorded"
export GH_VARIABLE_LOG="$TMP/variable.log"
: > "$GH_VARIABLE_LOG"
if PATH="$BIN:$PATH" "$RECORD" "not-a-sha" > "$TMP/record-err.out" 2>"$TMP/record-err.err"; then
  die "a malformed SHA was recorded"
fi
[[ ! -s "$GH_VARIABLE_LOG" ]] || die "a rejected SHA still reached gh variable set"
[[ ! -s "$TMP/record-err.out" ]] || die "a fatal error was written to stdout"
grep -q "Error:" "$TMP/record-err.err" || die "the fatal error never reached stderr"
ok "malformed SHA is rejected before any write, on stderr"

note "durable state: a no-op evaluation records the SHA and its revision"
PATH="$BIN:$PATH" "$RECORD" "$SHA" >/dev/null
grep -Fq "variable set SYNC_LAST_EVALUATED_SHA --body $SHA:$REV_NOW" "$GH_VARIABLE_LOG" ||
  die "evaluated state was not written as <sha>:<revision>"
ok "no-op evaluation persists SHA and generation revision"

note "durable state: a failed write degrades instead of failing the sync"
GH_VARIABLE_SET_FAILS=true PATH="$BIN:$PATH" "$RECORD" "$SHA" > "$TMP/record-fail.log" ||
  die "a failed variable write failed the sync run"
grep -q "next run will re-evaluate" "$TMP/record-fail.log" || die "failed write was not reported"
ok "unwritable state costs a repeat, not a red run"

read_durable_sha() {
  GH_REPO=owner/repo GH_VARIABLE_READ="$1" PATH="$BIN:$PATH" "$CHECK_STATE" "" |
    awk -F= '$1 == "last_upstream_sha" { print $2; exit }'
}

note "durable state: with no tracking issue the variable supplies the last SHA"
[[ "$(read_durable_sha "$SHA:$REV_NOW")" == "$SHA" ]] || die "durable variable was not consulted"
ok "no-issue runs read durable state"

note "durable state: a stale generation revision invalidates the cache"
[[ -z "$(read_durable_sha "$SHA:filter-0000000000-0000000000")" ]] ||
  die "state from a different filter revision was trusted"
ok "filter or engine changes force re-evaluation"

note "durable state: an unusable stored value degrades to empty"
[[ -z "$(read_durable_sha "deadbeef:$REV_NOW")" ]] || die "a short SHA was accepted as state"
[[ -z "$(read_durable_sha "notfound")" ]] || die "an unset variable produced a false SHA"
ok "invalid or absent durable state compares as changed"

note "durable state: an unreadable variable fails rather than reading as first sync"
if GH_REPO=owner/repo GH_VARIABLE_READ=denied PATH="$BIN:$PATH" "$CHECK_STATE" "" >/dev/null 2>&1; then
  die "an API failure was silently treated as no stored state"
fi
ok "denied variable reads fail closed"

note "durable state: an open tracking issue outranks the variable"
printf '%s\n' "Summary" "<!-- upstream-sha: $OLD_SHA -->" > "$TMP/active-cycle.md"
ACTIVE=$(GH_MODE=issue ISSUE_BODY_FILE="$TMP/active-cycle.md" GH_VARIABLE_READ="$SHA:$REV_NOW" \
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

GATE_LINE=$(grep -nF 'if [ "${{ steps.sync-state.outputs.should_create_pr }}" = "true" ]; then' "$WORKFLOW" | cut -d: -f1 || true)
[[ -n "$GATE_LINE" && "$GATE_LINE" -lt "$RECORD_LINE" ]] ||
  die "durable state is recorded while a sync PR may still be open"
grep -Fq 'sync_mode: ${{ vars.SYNC_MODE }}' "$WORKFLOW" || die "sync mode is not passed to the state manager"
ok "workflow invariants hold"

printf '\nAll sync-state-manager tests passed\n'
