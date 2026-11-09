# ADR-021: No pull_request_target Triggers

## Status

Accepted (2025-10-01). Revised 2026-11-09: the trigger is removed from every workflow.

## Context

A filter-mode `fork_upstream` carries no `.github/` (ADR-038), and a sync branch carries the same tree. A `pull_request` event on a sync PR reads the workflow from that tree, so it fires and nothing runs. Three template workflows used `pull_request_target`, which reads the workflow from the default branch, to react to PRs anyway:

- `cascade-monitor.yml` on a sync PR closed into `fork_upstream`
- `validate.yml` on a sync PR opened or updated, building the PR head
- `integration-cleanup.yml` on a PR closed into `main`

GitHub blocks `pull_request_target` by default on public repositories that have no event policy allowing it. The Azure organization started enforcing on 2026-11-09, and runs of all three workflows failed at startup. An allowlist needs a repository admin for each fork, through JIT elevation, and the `validate.yml` lane needs a security review because it checks out PR code in a context that holds a write token.

## Decision

No workflow in the template or its forks declares `pull_request_target`. `dev-ci.yml` asserts this for `.github/workflows/` and `.github/template-workflows/`.

| Workflow | Before | Now |
|---|---|---|
| `cascade-monitor.yml` | Sync PR closed into `fork_upstream`, plus every 6 hours | Hourly schedule and `workflow_dispatch`. The PR trigger only cut latency: the job ignored the event and compared `fork_upstream` to `fork_integration` either way. |
| `integration-cleanup.yml` | PR closed into `main` | `push` to `main`. The job finds the merged PR with `GET /repos/{repo}/commits/{sha}/pulls` and applies the same match as before: the `upstream-sync` label, a `fork_integration` head, or a `release/upstream-*` head. `workflow_dispatch` resets `fork_integration` to `main` for recovery. |
| `validate.yml` (filter-mode sync PRs) | `pull_request_target` lane building the PR head | The `Sync Build` job in `sync.yml` builds the commit the sync job just pushed, with the `core` profile, and posts a `Sync Build` commit status on the sync PR. |

The sync build runs from a schedule or a manual dispatch, so no PR author controls what it checks out. The tree is still unreviewed upstream code, so the build job holds `contents: read` only, with no secret and no persisted checkout credential. The sync job marks the status pending and a separate `report-sync` job, which never checks out the tree, posts the result. A `statuses: write` token inside the build would let upstream build code forge any status in the repository, including the required checks on `main`.

A scheduled run also carries `main`'s Actions cache scope, and code on the runner can write that cache whatever the job's permissions, because the runner holds its own cache token. `validate.yml` restores `~/.m2` from that scope and ships the JAR it builds. So the sync build runs Maven through `sandbox-build.sh`: a `docker run` of a digest-pinned base image that mounts the workspace and the read-only JDK and Maven, with no runner environment, no host `~/.m2`, and no capabilities. `.git` is mounted read-only, so the build cannot plant config that `actions/checkout`'s post-job git commands would run. No other step runs after it, and the job saves no cache.

A mirror-mode `fork_upstream` carries the parent's workflows (ADR-039), so its sync PRs take the ordinary `pull_request` trigger of `validate.yml`. The routing that used to send same-repository `sync/` PRs away from that trigger is gone.

## Consequences

- A merged sync PR starts its cascade within the hour unless someone runs Cascade Integration first. The safety net skips tracking issues labeled `cascade-blocked` or `cascade-failed`, which wait on a human, so an hourly schedule does not repost "Auto-Cascade Initiated" on a blocked cascade.
- `fork_upstream` has no required checks, so `Sync Build` informs the merge without gating it.
- `docker-push` keeps its `pull_request_target` guard (ADR-036) as a backstop in case the trigger is ever added back.

## Alternatives Considered

- **Allowlist the three workflows by workflow file targeting.** Needs JIT admin in every fork, and again for every new fork. `validate.yml` fails the untrusted-checkout CodeQL checks the exception requires.
- **Allowlist only `cascade-monitor.yml`.** It never checks out PR code, so it would pass review, but all it buys is a faster cascade start.
- **Copy workflows onto `fork_upstream`.** Pollutes the generated tree and conflicts with `main`'s copies on every cascade.
- **Dispatch `validate.yml` from `sync.yml`.** A `workflow_dispatch` run reports its checks against `main`, not the sync PR, so it would need status posting anyway and would carry the whole validate graph for a `core` build.

## Related Decisions

- [ADR-019: Cascade Monitor Pattern](019-cascade-monitor-pattern.md)
- [ADR-036: Workflow Trust Boundaries](036-workflow-trust-boundaries.md)
- [ADR-038: Upstream Filter Transform](038-upstream-filter-transform.md)
- [ADR-039: Customer-Tier Forks and Mirror-Mode Sync](039-customer-tier-mirror-sync.md)

## References

- [Workflow execution protections in GitHub Actions generally available](https://github.blog/changelog/2026-09-17-workflow-execution-protections-in-github-actions-generally-available/)
- [pull_request_target blocked by default December 2](https://github.blog/changelog/2026-11-02-pull_request_target-blocked-by-default-december-2/)

---

[← ADR-020](020-human-required-label-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-022 →](022-issue-lifecycle-tracking-pattern.md)
