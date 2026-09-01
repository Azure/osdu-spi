# ADR-007: Initialization Workflow Bootstrap Pattern

## Status
**Accepted** - 2025-10-01

## Context
A repository created from this template runs its initialization workflow from the template's initial commit as copied at creation time, not from whatever the template contains later. Any fix made to the initialization logic after that point is invisible to the fork while it initializes.

This surfaced during testing with OSDU repositories. The final merge of `fork_integration` into `main` failed with `fatal: refusing to merge unrelated histories`; the template already carried the `--allow-unrelated-histories` fix, but the fork's copy of the workflow did not. Even with that flag, files present in both the template and upstream (`.gitignore`, `README.md`) conflicted, which needed a `-X theirs` merge strategy.

A second finding: the built-in `GITHUB_TOKEN` cannot set repository variables (`HTTP 403: Resource not accessible by integration`). Initialization needs a higher-privilege token for that step.

## Decision
Keep the initialization logic that must be correct at first run in local actions under `.github/local-actions/`, and have `init-complete.yml` call them.

The merge in question lives in `.github/local-actions/merge-with-theirs-resolution/action.sh`, which runs `git merge` with `--allow-unrelated-histories --no-ff -X theirs`. `init-complete.yml` invokes it to merge `fork_integration` into `main` with the commit message `chore: complete repository initialization`.

This works because local actions are part of the template's initial commit, so the fork has them from the moment it is created. There is no bootstrap step, no dependency on the template being reachable during initialization, and no extra commit in the fork's history. Local actions are template-only: `.github/sync-config.json` removes `.github/local-actions/` from the fork once initialization completes.

For the token, `init-complete.yml` mints a GitHub App installation token (ADR-029) and uses it for the `gh variable set` calls. If the token is unavailable, the workflow skips variable configuration with a warning and lists the manual steps in the completion comment.

## Alternatives Considered

### 1. Document Manual Workarounds
Tell users which commands to run when initialization fails. Rejected: defeats the purpose of the template.

### 2. Pre-create All Branches in Template
Include `fork_upstream` and `fork_integration` in the template. Rejected: pollutes the template with upstream-specific content and does not address stale workflow logic.

### 3. External Initialization Script
Download and run a script hosted outside the repository. Rejected: external dependency and a new security surface.

### 4. Self-Updating Workflow
A first job fetches the latest `init.yml` and `init-complete.yml` from the template, commits them, and a second job runs the updated logic. This was the original plan for this ADR. Rejected in favor of local actions: it adds a two-phase workflow, a bootstrap commit in every fork, and a runtime dependency on the template repository, while the local-actions approach gets the same result because the actions are already in the initial commit.

## Consequences
Initialization fixes still reach only repositories created after the fix. Existing forks pick up later template changes through template sync (ADR-012), which does not re-run initialization.

## Related Decisions
- [ADR-028: Workflow Script Extraction Pattern](028-workflow-script-extraction-pattern.md) - The local actions pattern in general
- [ADR-029: GitHub App Authentication Strategy](029-github-app-authentication-strategy.md) - The token used to set repository variables
- [ADR-012: Template Update Propagation Strategy](012-template-update-propagation-strategy.md) - How template improvements reach existing forks
- [ADR-006: Two-Workflow Initialization Pattern](006-two-workflow-initialization.md) - The workflows that call these actions
---

[← ADR-006](006-two-workflow-initialization.md) | :material-arrow-up: [Catalog](index.md) | [ADR-008 →](008-centralized-label-management.md)
