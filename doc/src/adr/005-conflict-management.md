# ADR-005: Automated Conflict Management Strategy

## Status
**Accepted** - 2025-10-01

## Context
Merge conflicts between upstream and the fork's own modifications are inevitable. The system needs to detect them automatically, keep conflicted code away from `main`, make the conflict visible to the team, and let resolution happen without blocking other development.

Resolving conflicts directly on `main` destabilizes it; ignoring them lets the fork drift from upstream.

## Decision
1. **Conflict Detection**: The cascade detects merge conflicts when merging `fork_upstream` into `fork_integration`.
2. **Isolation**: Conflicts are resolved on `fork_integration`, never on `main`.
3. **Issue Creation**: Each conflict opens a GitHub issue listing the conflicted files and the steps to resolve them.
4. **Manual Resolution**: A human resolves the conflict directly on `fork_integration` and pushes. No conflict is resolved automatically.
5. **Escalation**: Conflicts open longer than 48 hours are escalated with a separate issue and label.
6. **Documentation**: The issue records when the conflict occurred and how it was resolved.

## Alternatives Considered

### 1. Automatic Conflict Resolution
No manual intervention, but risks incorrect resolutions and silent data loss. Rejected.

### 2. Conflict Resolution on Main Branch
Simpler, but destabilizes `main` and blocks other development while conflicts are open. Rejected.

### 3. Feature Branch per Conflict
Complete isolation per conflict, but branch proliferation and tracking overhead. Rejected.

### 4. Manual Conflict Detection
Human judgment in detection, but inconsistent and slow. Rejected.

## Consequences
Every conflict needs a human, so upstream integration waits on resolution. In exchange, `main` never receives conflicted code and every resolution is recorded on an issue.

## Implementation Details

### Where Detection Happens
The strategy is implemented in `cascade.yml` (job `cascade-to-integration`) together with the Cascade Monitor Pattern (ADR-019) and the Human-Required Label Strategy (ADR-020):

1. `sync.yml` opens a PR from a `sync/upstream-*` branch to `fork_upstream`.
2. After that PR merges, a human triggers `cascade.yml`. `cascade-monitor.yml` dispatches it as a safety net if nobody does.
3. The cascade merges `fork_upstream` into `fork_integration`. If git reports unmerged paths, the step lists the conflicted files, opens an issue titled `🚨 Cascade Conflicts: Manual Resolution Required` with labels `conflict,cascade-blocked,high-priority,human-required`, moves the tracking issue from `cascade-active` to `cascade-blocked`, and stops.
4. The developer resolves the conflicts on `fork_integration` locally, commits, and pushes.
5. Once the `human-required` label is removed, `cascade-monitor.yml` re-dispatches the cascade, which continues to validation and the production PR.
6. `check-stale-conflicts` in both `cascade.yml` and `cascade-monitor.yml` looks for `conflict,cascade-blocked` items older than 48 hours, opens an escalation issue labeled `escalation,high-priority,cascade-escalated,human-required`, and comments on the original.

### Labels (ADR-020)
- `human-required`: manual intervention needed
- `conflict`: the issue type
- `cascade-blocked`: the pipeline is blocked
- `high-priority`: urgency
- `cascade-escalated`: the 48-hour SLA was exceeded

---

[← ADR-004](004-release-please-versioning.md) | :material-arrow-up: [Catalog](index.md) | [ADR-006 →](006-two-workflow-initialization.md)
