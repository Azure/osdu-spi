# ADR-006: Two-Workflow Initialization Pattern

## Status
**Accepted** - 2025-10-01

## Context
The original initialization was a single workflow (`init.yml`) that handled issue creation, input validation, branch creation, security scanning, and cleanup. One file carrying every concern was hard to debug, produced technical error messages where users needed guidance, and had overlapping initialization checks with a complicated cleanup phase.

The process divides naturally into two phases: user interaction (issue creation, validation, communication) and repository setup (branches, configuration, finalization).

## Decision
Split initialization into two workflows:

1. **`init.yml`** - User interface and issue management
   - Triggered on push to `main` (fires when a repository is created from the template)
   - Detects whether it is running on the template itself and stops if so
   - Creates the system labels and the initialization issue with instructions

2. **`init-complete.yml`** - Repository setup and configuration
   - Triggered on `issue_comment` (the user replying with the upstream repository)
   - Validates the input and replies with clear error messages
   - Sets repository variables, creates branches, installs workflows, applies protection and security settings
   - Posts a completion summary and removes the initialization workflows from the fork

Initialization state is the repository variable `INITIALIZATION_COMPLETE`. Both workflows and the fork workflows check it, and `init-complete.yml` sets it as its final mutation.

`init-complete.yml` uses a concurrency group keyed on the issue number so a second comment cannot start a parallel setup.

## Alternatives Considered

### 1. Maintain Single Workflow with Refactoring
Fewer files, but the concerns would still be tangled in one file. Rejected.

### 2. Three-Workflow Pattern (Init + Validate + Setup)
More granular, but more moving parts than the process needs. Rejected.

### 3. Composite Actions for Reusable Components
Useful for code reuse, but does not by itself separate the two phases. Adopted later alongside the split (ADR-013, ADR-028), not as a replacement for it.

## Consequences
`init-complete.yml` depends on the issue that `init.yml` creates, so the two files must agree on the issue's shape. In exchange, each workflow has one job and a failure can be traced to one phase.

## Related Decisions

- [ADR-007: Initialization Workflow Bootstrap Pattern](007-initialization-workflow-bootstrap.md) - Why the setup logic lives in local actions
- [ADR-029: GitHub App Authentication Strategy](029-github-app-authentication-strategy.md) - Authentication mechanism for initialization workflows

---

[← ADR-005](005-conflict-management.md) | :material-arrow-up: [Catalog](index.md) | [ADR-007 →](007-initialization-workflow-bootstrap.md)
