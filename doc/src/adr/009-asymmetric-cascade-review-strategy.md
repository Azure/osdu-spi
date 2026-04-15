# ADR-009: Asymmetric Cascade Review Strategy

## Status
Accepted (revised Apr 2026 — see "Revision: Merge Method Enforcement" below)

## Context
The cascade workflow moves upstream changes through a three-branch hierarchy:
1. `fork_upstream` → `fork_integration` 
2. `fork_integration` → `main`

With the implementation of human-centric cascade triggering (ADR-019) and issue lifecycle tracking (ADR-022), we needed to balance automation efficiency with safety, ensuring that upstream changes are properly vetted before reaching production while minimizing manual intervention where safe.

Key considerations:
- Upstream changes are external and potentially breaking
- Integration branch serves as a testing ground
- Main branch is production and must remain stable
- Manual cascade triggering provides explicit human control
- Conflict resolution always requires human intervention
- Issue tracking provides visibility into review status

## Decision
We will implement an asymmetric review strategy for cascade PRs:

1. **Fork_upstream → Fork_integration**: Human-initiated with comprehensive validation
   - Triggered manually by humans after reviewing upstream sync PR
   - Issue lifecycle tracking provides visibility into integration status
   - Conflicts are most likely to occur here
   - Human judgment needed to assess upstream impact
   - **Comprehensive validation**: Build, test, and lint checks run on integration branch
   - **Validation failures**: Block cascade and create detailed failure issues

2. **Fork_integration → Main**: Always requires human review  
   - All production PRs require manual approval before merge
   - Ensures final human oversight before changes reach production
   - Changes already validated and proven stable in integration branch
   - **Quality gate**: Only validated changes that pass all checks reach production

## Consequences

### Positive
- **Safety First**: External changes get human review at entry point
- **Production Safety**: All production changes require final human approval
- **Quality Assurance**: Comprehensive build, test, and validation on integration branch
- **Early Detection**: Integration validation catches issues before production PRs
- **Clear Boundaries**: Integration branch serves its purpose as a true validation gate
- **Risk Mitigation**: Human oversight and automated validation at both critical decision points
- **Audit Trail**: Complete human review history and validation logs for all production deployments
- **Issue Tracking**: Detailed failure tracking with error logs and resolution guidance

### Negative
- **Manual Overhead**: All production PRs require human review and approval
- **Potential Delays**: Manual review may slow deployment of routine updates
- **Review Fatigue**: Teams need to review both integration and production PRs

### Neutral
- **Monitoring Required**: Need to track manual review timing and bottlenecks
- **Process Efficiency**: Teams can develop patterns for faster routine reviews
- **Flexibility**: Emergency procedures can be established for critical fixes

## Implementation Details

### Phase 1 (Human-Initiated Integration with Validation)
```yaml
# Humans manually trigger cascade after reviewing sync PR
# Cascade workflow updates issue tracking
gh issue edit "$ISSUE_NUMBER" \
  --remove-label "human-required" \
  --add-label "cascade-active"

# Integration proceeds with merge and comprehensive validation
# 1. Merge fork_upstream to fork_integration (conflict detection)
# 2. Run comprehensive validation (build, test, lint)
# 3. Report validation results to tracking issue

# If conflicts detected OR validation fails:
#   - Issue updated to cascade-blocked
#   - Detailed failure issue created with logs and resolution steps
#   - Cascade to main blocked until resolution
```

### Phase 2 (Production PR Creation - Only After Validation Passes)
```yaml
# Production PR only created if integration validation successful
# Condition: integration_success == 'true' && conflicts_found == 'false'

# Create production PR from validated fork_integration to main
RELEASE_BRANCH="release/upstream-$(date +%Y%m%d-%H%M%S)"
PR_URL=$(gh pr create \
  --base main \
  --head $RELEASE_BRANCH \
  --title "🚀 Production Release: Upstream Integration - $(date +%Y-%m-%d)" \
  --body "$PR_BODY" \
  --label "upstream-sync,human-required")

# Arm auto-merge with merge-commit method (see Revision below).
# Wrapped in if/else so a failure to arm auto-merge is logged but does
# not fail the cascade — humans can still merge manually as a fallback.
if MERGE_OUTPUT=$(gh pr merge "$PR_NUMBER" --auto --merge 2>&1); then
  echo "✅ Auto-merge armed - awaiting human approval"
else
  echo "::warning::Could not arm auto-merge on PR #$PR_NUMBER. Reason: $MERGE_OUTPUT"
fi

# Update tracking issue - production PR created
gh issue comment "$TRACKING_ISSUE" --body "🎯 **Production PR Created** - $(date -u +%Y-%m-%dT%H:%M:%SZ)

Integration completed successfully! Production PR has been created and is ready for final review."

# Human gate: approving the PR releases auto-merge
```

## Revision: Merge Method Enforcement (Apr 2026)

### Trigger
The first cascade release PR on `osdu-spi-partition` was squash-merged by a human picking the GitHub UI's default button. The squash collapsed multiple upstream commits into one new commit on `main` that didn't share git ancestry with the original upstream commits. Two cascading consequences followed:

1. `fork_upstream` was no longer a true ancestor of `main`. Cascade Monitor's `git rev-list fork_integration..fork_upstream` graph check started returning non-zero, so the monitor auto-dispatched cascade on every cron tick, creating duplicate "Upstream Integration to Main" PRs with the same upstream SHA.
2. Subsequent cascades hit phantom merge conflicts on every file the squash had collapsed. Git couldn't reconcile main's squash blob with `fork_upstream`'s individual commits because the merge-base reverted to a point before the squash.

The root vulnerability was that the human review gate and the merge-method choice were collapsed into a single click. A human reviewing a release PR could approve the changes correctly *and* misclick the merge method, with no separate gate to catch the merge-method mistake.

A contributing factor was the template's `default-branch.json` ruleset including `required_linear_history`, which forbids merge commits in the GitHub UI regardless of repo settings. With merge commits hidden from the UI, "Squash" became the sticky default. That rule was removed alongside this revision.

### Decision
Separate the human review gate from the merge-method choice:

- **Human gate becomes "approve the PR"**, expressed via the existing `required_approving_review_count: 1` rule on `main`.
- **Merge method becomes workflow-enforced**, via `gh pr merge --auto --merge` armed by the cascade workflow immediately after the release PR is created.

Auto-merge waits for both the required approval and any required status checks before firing. When it fires, it uses the merge-commit method that was armed by the workflow, not whatever sticky default the human had in the UI.

The original asymmetric strategy is preserved — humans still gate production. The mechanism for expressing that gate moves from "click the right merge button" to "approve the PR." Both are explicit human actions, but approval has no dropdown of conflicting choices, so the merge-method foot-gun is eliminated.

### Implementation

```bash
# Cascade workflow, immediately after gh pr create:
PR_NUMBER=$(basename $PR_URL)

# Arm auto-merge with merge-commit method. The human gate is preserved
# by the required approval rule on main — auto-merge waits for that
# approval before firing. Locks the merge method in code so release PRs
# cannot be squash-merged.
if gh pr merge "$PR_NUMBER" --auto --merge 2>/dev/null; then
  echo "✅ Auto-merge armed - awaiting human approval"
else
  echo "::warning::Could not arm auto-merge. Human must merge with 'Create a merge commit' (NOT squash)."
fi
```

### Prerequisites
- `allow_auto_merge=true` on the repository (set during init by `setup-fork-repo.sh`)
- `required_approving_review_count: 1` (or higher) on `main` via branch protection or ruleset
- No `required_linear_history` rule on `main` (it forbids merge commits and would block the auto-merge)

### Recovery (Reversibility)
A human can disable auto-merge from the PR UI at any time and merge manually. The escape hatch is preserved — the workflow only sets the *default* path; humans retain full control if they need to override.

### Why this is consistent with the original ADR
The original decision says "All production PRs require manual approval before merge." That remains true. The revision only changes how that approval is *expressed*: approval was previously implicit in the merge-button click, now it's explicit via the Files Changed → Approve action. The asymmetry between the two cascade phases is unchanged — fork_upstream → fork_integration is human-initiated; fork_integration → main is human-approved.

## Alternatives Considered

1. **Fully Automated**: Auto-merge at both stages when clean
   - Rejected: Too risky for external changes reaching production

2. **Conditional Auto-merge**: Auto-merge second stage based on size/changes
   - Rejected: Even clean changes benefit from human oversight before production

3. **Reversed Asymmetry**: Auto-merge first stage, manual second
   - Rejected: Backwards from a safety perspective

4. **Disable squash-merge repo-wide** (considered during Apr 2026 revision)
   - Rejected: Punishes feature-branch development for the sake of one specific PR pattern. Squash-merge is a reasonable choice for feature work.

5. **Harden cascade-monitor to detect squash-merged release PRs** (considered during Apr 2026 revision)
   - Rejected: Adds complexity to a stable safety-net workflow to defend against a failure mode that auto-merge prevents at the source. Re-evaluate only if real-world recurrence proves the prevention is insufficient.

## Related
- [ADR-001: Three-Branch Fork Management Strategy](001-three-branch-strategy.md)
- [ADR-005: Automated Conflict Management Strategy](005-conflict-management.md)
- [ADR-019: Cascade Monitor Pattern](019-cascade-monitor-pattern.md) - Human-centric cascade triggering
- [ADR-022: Issue Lifecycle Tracking Pattern](022-issue-lifecycle-tracking-pattern.md) - Integration with issue tracking
- [Cascade Workflow Specification](../cascade-workflow.md)
---

[← ADR-008](008-centralized-label-management.md) | :material-arrow-up: [Catalog](index.md) | [ADR-010 →](010-yaml-safe-shell-scripting.md)
