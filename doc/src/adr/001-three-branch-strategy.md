# ADR-001: Three-Branch Fork Management Strategy

## Status
**Accepted** - 2025-10-01

**Amended by [ADR-038](038-upstream-filter-transform.md)** - 2026-08-27: `fork_upstream` is no longer a verbatim mirror. It is a generated tree containing only the shared upstream code the Azure SPI consumes, filtered from its first generation at initialization.

## Context
A long-lived fork has to stay current with upstream while keeping its own modifications. Merging upstream directly into the working branch mixes the two, makes conflicts land on the stable branch, and makes it hard to tell which changes came from where.

The system needs regular upstream synchronization, isolation of local changes from upstream changes, a safe place to resolve conflicts, and a stable release branch.

## Decision
Use three long-lived branches:

1. **`main`** - Stable production branch. Receives changes only through PRs.
2. **`fork_upstream`** - Tracks the upstream repository's main branch (since ADR-038, as a generated tree filtered to the shared code the fork consumes). Carries no local modifications, so diffs against it show exactly what upstream changed.
3. **`fork_integration`** - Workspace where upstream changes are merged, conflicts are resolved, and build, test, and lint run before anything reaches `main`.

Changes flow `fork_upstream` to `fork_integration` to `main`. Conflicts are resolved and validation runs on `fork_integration`; a production PR to `main` is created only after validation passes, and a human approves it.

## Alternatives Considered

### 1. Two-Branch Strategy (fork + main)
Simpler, but conflicts would land directly on `main` with no dedicated resolution space. Rejected.

### 2. Feature Branch per Upstream Sync
Each sync isolated, but branches proliferate and tracking multiple in-flight syncs gets complicated. Rejected.

### 3. Direct Upstream Merge to Main
Simplest possible approach, but no conflict isolation and a high risk of breaking `main`. Rejected.

## Consequences
Three branches cost more than one: the team has to learn the flow, and the branches only stay coherent if automated workflows manage them. In exchange, `main` stays stable, upstream and local changes are attributable, and conflicts are resolved away from production.

## Implementation Details

### Branch Protection
Protection is applied as rulesets by `settings-apply.yml` from `.github/rulesets/`:
- `default-branch.json` protects `main`: PR required with one approving review, required status checks (`CodeQL`, `🐳 Docker Build`), no deletion, no force push.
- `integration-branch.json` protects `fork_upstream` and `fork_integration` from deletion only. Automation and humans push to them directly.

### Branch Preservation
All three branches must be permanently preserved and never deleted. `fork_upstream` is needed for future syncs and `fork_integration` for future integrations.

Production PRs use temporary release branches (`release/upstream-YYYYMMDD-HHMMSS`, created by `cascade.yml`) from `fork_integration` to `main`, so the release branch can be deleted after merge while the three core branches stay.

### Integration Branch Synchronization
After a production PR merges to `main`, `fork_integration` still holds the commit history that went in through the release branch, so it appears ahead of `main` and the cascade would wrongly detect an integration in progress.

`integration-cleanup.yml` resets `fork_integration` to `main` after a merged PR to `main` that either carries the `upstream-sync` label, has head branch `fork_integration`, or has a head branch starting with `release/upstream-`. It also closes any open `upstream-held` issues, which clears the pipeline for the next upstream change.

### Workflow Integration
1. **Upstream Sync**: `sync.yml` updates `fork_upstream` on a schedule.
2. **Integration Cascade**: `cascade.yml` merges `fork_upstream` into `fork_integration`, detects conflicts, and runs build, test, and lint.
3. **Validation Gate**: A failed merge or validation blocks progression and opens an issue.
4. **Production Release**: A PR from `fork_integration` to `main` is created only after validation succeeds, and requires human approval.
5. **Integration Sync**: After the PR merges, `integration-cleanup.yml` resynchronizes `fork_integration` with `main`.

---

:material-arrow-up: [Catalog](index.md) | [ADR-002 →](002-github-actions-automation.md)
