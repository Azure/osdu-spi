# ADR-021: Pull Request Target Trigger Pattern

## Status
**Accepted** - 2025-10-01

## Context

The cascade-monitor workflow needs to run when a sync pull request is merged into `fork_upstream` so the cascade can start. The original `pull_request` trigger had one defect: `pull_request` reads the workflow file from the target branch, and `fork_upstream` carries no `.github/` at all. The event fired but nothing ran.

The first workaround triggered the cascade indirectly with `gh workflow run` under a personal access token. That added a token dependency and a second failure point.

## Decision

Trigger cascade-monitor with `pull_request_target`:

```yaml
on:
  pull_request_target:
    types: [closed]
    branches: [fork_upstream]
```

`pull_request_target` always reads the workflow definition from the default branch while still exposing the pull request payload. The same job also runs on a six-hour schedule and on manual dispatch, so a merge event and a scheduled pass take the same path: compare `fork_upstream` to `fork_integration`, find the open `upstream-sync` issue, and dispatch the cascade workflow with `GITHUB_TOKEN` (`actions: write`). No personal access token is involved.

### Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **pull_request_target** | Reads from main, direct trigger, simple | Elevated permissions |
| Copy YAML to fork_upstream | Standard trigger | Duplicate files, maintenance burden |
| workflow_run | Works from main | Fires before merge, complex logic |
| Issue-close pattern | Works from main | Extra complexity, manual cleanup |
| repository_dispatch | Explicit control | Requires PAT, more moving parts |

### Security Considerations

`pull_request_target` runs with base-repository permissions. The monitor limits exposure by triggering only on closed PRs against `fork_upstream`, checking merged state, and never checking out or executing PR head content.

The same trigger is now also used by `validate.yml` (sync PRs) and `integration-cleanup.yml`. The trust rules for which jobs may run under it, and which credentials they may hold, are in [ADR-036: Workflow Trust Boundaries](036-workflow-trust-boundaries.md).

## Consequences

Team members must understand the difference between `pull_request` and `pull_request_target` before editing these workflows; the elevated context is the cost of running from `main`.

## Related Decisions

- [ADR-019: Cascade Monitor Pattern](019-cascade-monitor-pattern.md) - Original monitor pattern
- [ADR-001: Three-Branch Fork Management Strategy](001-three-branch-strategy.md) - Branch structure
- [ADR-020: Human-Required Label Strategy](020-human-required-label-strategy.md) - Label-based triggers
- [ADR-036: Workflow Trust Boundaries](036-workflow-trust-boundaries.md) - Trust rules for `pull_request_target` jobs

## References

- [GitHub Docs: pull_request_target](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request_target)
- [GitHub Security: pull_request_target](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
---

[← ADR-020](020-human-required-label-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-022 →](022-issue-lifecycle-tracking-pattern.md)
