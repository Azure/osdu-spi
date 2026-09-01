# ADR-019: Cascade Monitor Pattern

## Status
**Accepted** - 2025-10-01  

## Context

The cascade workflow needs to run after upstream changes are merged into `fork_upstream`. Automatic triggering created reliability and usability problems:

1. **Event trigger limitations**: `pull_request_target` events require workflows to exist on the target branch (`fork_upstream`), but that branch is a generated upstream tree without workflow files (ADR-038)
2. **Human control**: teams want to decide when integration happens, and may want to batch changes
3. **Visibility**: the cascade lifecycle needs an audit trail and progress tracking
4. **Error recovery**: failed or missed triggers need reliable detection and recovery

## Decision

Make manual triggering the primary path and add a scheduled monitor as the safety net:

1. **Primary path**: humans trigger `Cascade Integration` (`cascade.yml`, `workflow_dispatch` with an `issue_number` input) after reviewing and merging the sync PR
2. **Safety net**: `cascade-monitor.yml` runs every 6 hours (`cron: '0 */6 * * *'`) and on `workflow_dispatch`, detects missed triggers, and starts the cascade itself
3. **Issue lifecycle tracking**: cascade state is carried by labels on the upstream-sync tracking issue and by comments the workflows post (ADR-022)
4. **Automated failure recovery**: the monitor retries cascades whose failure a human has cleared

### Sync workflow instructions

The tracking issue created by `sync.yml` (labeled `upstream-sync,human-required`) tells the reviewer to merge the sync PR, then run the Cascade Integration workflow with the issue number, and notes that the monitor will start the cascade within 6 hours if nobody does. See the "Upstream Sync Ready for Review" body in `sync.yml`.

### Monitor jobs

`cascade-monitor.yml` has four jobs:

- **detect-missed-cascade**: if `fork_upstream` has commits that `fork_integration` lacks and an open `upstream-sync` issue exists, comment on the issue and run `gh workflow run "Cascade Integration" -f issue_number=<n>`. If the trigger call fails, the job comments "Auto-trigger Failed" on the issue and exits non-zero; no label is applied.
- **check-stale-conflicts**: find open PRs labeled `conflict,cascade-blocked` older than 48 hours, open an escalation issue labeled `escalation,high-priority,cascade-escalated,human-required`, comment on the PR, and add `cascade-escalated` to it (skipped when already escalated).
- **check-cascade-health**: count `cascade-active`, `cascade-blocked`, and `cascade-escalated` items and write a status summary.
- **detect-recovery-ready**: find open issues labeled `cascade-failed` but not `human-required`, relabel them `cascade-active`, comment, and re-run the cascade. If the retry trigger fails the issue is relabeled `cascade-failed,human-required` again.

### Issue lifecycle

```
# Normal progression (labels on the tracking issue)
upstream-sync + human-required → cascade-active → validated

# Blocked
cascade-active → cascade-blocked            (conflicts or validation failure)

# Failed
cascade-active → cascade-failed + human-required
```

The cascade removes `human-required` and adds `cascade-active` when it starts, swaps `cascade-active` for `cascade-blocked` on conflicts or validation failures, and ends by removing the active, blocked, and failed labels and adding `validated`. Label changes are made in `cascade.yml`.

### Human recovery workflow

1. The cascade fails; the tracking issue gets `cascade-failed + human-required`, and a separate issue labeled `high-priority,human-required` carries the technical details
2. A developer investigates and fixes the cause
3. The developer removes `human-required` from the tracking issue
4. On its next run the monitor detects the cleared failure and retries the cascade
5. The retry either completes or creates a new failure issue

## Alternatives Considered

### 1. Direct push triggers

```yaml
on:
  push:
    branches: [fork_upstream]
```
Rejected: fires on every push, with no way to distinguish sync merges from other pushes.

### 2. Combined PR and push triggers

```yaml
on:
  push:
    branches: [fork_upstream, fork_integration]
  pull_request:
    types: [closed]
    branches: [fork_upstream, fork_integration]
```
Rejected: complex conditional logic, hard to debug, and workflow files are not present on `fork_upstream`.

### 3. External webhook system

Rejected: extra infrastructure for minimal benefit.

### 4. Frequent scheduled polling (every 5 minutes)

Rejected as the primary approach; a 6-hour schedule is kept as the backup in the monitor.

## Consequences

Humans must remember to trigger cascades; a forgotten trigger is delayed by up to 6 hours until the monitor runs. Label-based state tracking adds steps to the cascade workflow, and the safety net depends on the monitor itself running. In exchange, integration timing is under team control and the process does not depend on GitHub event delivery to a branch without workflows.

## Related Decisions

- [ADR-001: Three-Branch Fork Management Strategy](001-three-branch-strategy.md) - Defines the cascade target branches
- [ADR-005: Automated Conflict Management Strategy](005-conflict-management.md) - Conflict handling within cascades
- [ADR-008: Centralized Label Management Strategy](008-centralized-label-management.md) - Label-based state management
- [ADR-009: Asymmetric Cascade Review Strategy](009-asymmetric-cascade-review-strategy.md) - Review requirements for cascades
- [ADR-020: Human-Required Label Strategy](020-human-required-label-strategy.md) - Label instead of assignee
- [ADR-022: Issue Lifecycle Tracking Pattern](022-issue-lifecycle-tracking-pattern.md) - Lifecycle labels

---

[← ADR-018](018-fork-resources-staging-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-020 →](020-human-required-label-strategy.md)
