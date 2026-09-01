# ADR-009: Asymmetric Cascade Review Strategy

## Status
Accepted (revised Apr 2026, see "Revision: Merge Method Enforcement" below)

## Context
The cascade workflow moves upstream changes through a three-branch hierarchy:
1. `fork_upstream` → `fork_integration`
2. `fork_integration` → `main`

With human-centric cascade triggering (ADR-019) and issue lifecycle tracking (ADR-022), we needed to balance automation with safety: upstream changes must be vetted before reaching production, with manual intervention only where it adds something.

Key considerations:
- Upstream changes are external and potentially breaking
- Integration branch serves as a testing ground
- Main branch is production and must remain stable
- Manual cascade triggering provides explicit human control
- Conflict resolution always requires human intervention
- Issue tracking provides visibility into review status

## Decision
We will implement an asymmetric review strategy for cascade PRs:

1. **Fork_upstream → Fork_integration**: Human-initiated, then validated
   - Triggered manually by humans after reviewing the upstream sync PR
   - Conflicts are most likely to occur here and need human judgment
   - Build, test, and lint run on the integration branch
   - Validation failures block the cascade and open a failure issue with logs

2. **Fork_integration → Main**: Always requires human review
   - The production PR is created only for changes that passed integration validation
   - A human approves it before merge

## Consequences
Every production change waits on a human approval, so routine upstream updates are slower than they could be and teams review both the sync PR and the production PR. In exchange, external changes get human review at the entry point and again before production, with validation logs and issue history for each.

## Implementation Details

### Phase 1 (Human-Initiated Integration with Validation)
In `cascade.yml`, job `cascade-to-integration`:
1. Moves the tracking issue from `human-required` to `cascade-active`
2. Merges `fork_upstream` into `fork_integration` with conflict detection (ADR-005)
3. Runs build, test, and lint on `fork_integration`
4. On conflicts or validation failure, moves the issue to `cascade-blocked`, opens a failure issue, and stops

### Phase 2 (Production PR Creation, only after validation passes)
Job `cascade-to-main` runs only when integration succeeded with no conflicts. It creates a `release/upstream-<timestamp>` branch from `fork_integration`, opens a PR to `main` titled `⬆️ Upstream Integration to Main <sha>` with labels `upstream-sync,human-required`, arms auto-merge with the merge-commit method (see Revision below), and comments on the tracking issue with the PR link. If arming auto-merge fails, the failure is logged as a warning and the cascade continues; a human can still merge manually.

Approving the PR is the human gate that releases auto-merge.

## Revision: Merge Method Enforcement (Apr 2026)

### Trigger
The first cascade release PR on `osdu-spi-partition` was squash-merged by a human picking the GitHub UI's default button. The squash collapsed multiple upstream commits into one new commit on `main` that didn't share git ancestry with the original upstream commits. Two cascading consequences followed:

1. `fork_upstream` was no longer a true ancestor of `main`. Cascade Monitor's `git rev-list fork_integration..fork_upstream` graph check started returning non-zero, so the monitor auto-dispatched cascade on every cron tick, creating duplicate "Upstream Integration to Main" PRs with the same upstream SHA.
2. Subsequent cascades hit phantom merge conflicts on every file the squash had collapsed. Git couldn't reconcile main's squash blob with `fork_upstream`'s individual commits because the merge-base reverted to a point before the squash.

The root vulnerability was that the human review gate and the merge-method choice were collapsed into a single click. A human reviewing a release PR could approve the changes correctly *and* misclick the merge method, with no separate gate to catch the merge-method mistake.

A contributing factor was the template's `default-branch.json` ruleset including `required_linear_history`, which forbids merge commits in the GitHub UI regardless of repo settings. With merge commits hidden from the UI, "Squash" became the sticky default. That rule was removed from the ruleset alongside this revision. (`.github/branch-protection.json` still lists `required_linear_history: true`; no workflow or script reads that file.)

### Decision
Separate the human review gate from the merge-method choice:

- **Human gate becomes "approve the PR"**, expressed via the existing `required_approving_review_count: 1` rule on `main`.
- **Merge method becomes workflow-enforced**, via `gh pr merge --auto --merge` armed by the cascade workflow immediately after the release PR is created.

Auto-merge waits for both the required approval and any required status checks before firing. When it fires, it uses the merge-commit method that was armed by the workflow, not whatever sticky default the human had in the UI.

The original asymmetric strategy is preserved: humans still gate production. The mechanism for expressing that gate moves from "click the right merge button" to "approve the PR." Both are explicit human actions, but approval has no dropdown of conflicting choices, so the merge-method foot-gun is eliminated.

### Prerequisites
- `allow_auto_merge=true` on the repository (set during init by `setup-fork-repo.sh`, and by `adopt-fork.yml` for adopted repositories)
- `required_approving_review_count: 1` (or higher) on `main` via ruleset (`.github/rulesets/default-branch.json`)
- No `required_linear_history` rule on `main` (it forbids merge commits and would block the auto-merge)

### Recovery (Reversibility)
A human can disable auto-merge from the PR UI at any time and merge manually. The workflow only sets the default path; humans retain full control if they need to override.

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
- [Cascade Workflow](../workflows/cascade.md)
---

[← ADR-008](008-centralized-label-management.md) | :material-arrow-up: [Catalog](index.md) | [ADR-010 →](010-yaml-safe-shell-scripting.md)
