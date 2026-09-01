# ADR-002: GitHub Actions-Based Automation Architecture

## Status
**Accepted** - 2025-10-01

## Context
The fork management system needs automation for repository initialization, scheduled upstream synchronization, conflict detection, build validation, security scanning, and release management. That automation has to integrate with GitHub's own repository features (issues, PRs, labels, branch protection) because those are where humans interact with the pipeline.

## Decision
Implement all automation as GitHub Actions workflows, one workflow per concern, with shared logic extracted into composite actions.

The authoritative list of workflows lives in `.github/sync-config.json`: `template_workflows` are the workflows every fork receives (stored under `.github/template-workflows/`), and `template_only` and `development_only` are the workflows that exist only in the template repository. The main fork workflows are:

- **sync.yml** - Scheduled upstream synchronization with issue lifecycle tracking and duplicate prevention
- **cascade.yml** - Human-triggered integration from `fork_upstream` through `fork_integration` to `main`
- **cascade-monitor.yml** - Scheduled safety net that detects missed or stuck cascades
- **validate.yml** - PR validation and status checks
- **build.yml** - Build, test, and coverage on feature branches
- **release.yml** - Release Please versioning and upstream-correlated tags
- **codeql.yml** - Security scanning

Template-only workflows (`init.yml`, `init-complete.yml`) handle initialization and are removed from forks.

### Why GitHub Actions
- Native integration with the repository events, issues, and PRs the pipeline is built around
- No external CI service, secrets stay in GitHub's secrets management
- Included with the repository, no additional cost
- Event-driven, so workflows react to pushes, PR merges, and comments directly

### Why one workflow per concern
Each workflow has a single responsibility and runs only when relevant, which keeps individual files debuggable and lets independent workflows run in parallel. Common patterns are extracted to composite actions in `.github/actions/`.

## Alternatives Considered

### 1. External CI/CD Platform (Jenkins, GitLab CI, etc.)
More powerful build environments, but adds an external dependency, cost, and a second place to manage secrets. Rejected.

### 2. Monolithic Single Workflow
All logic in one place, but hard to maintain and runs unrelated tasks on every trigger. Rejected.

### 3. Serverless Functions (AWS Lambda, Azure Functions)
Event-driven and scalable, but platform lock-in and extra infrastructure to operate. Rejected.

## Consequences
The system is tied to GitHub and subject to Actions usage limits, timeouts, and the hosted runner environment. Complex workflows are still YAML, which gets hard to read at scale; ADR-028 addresses this by extracting scripts.

## Implementation Details

### Workflow Triggers
- **init.yml**: push to `main` (fires on template creation; blocked on the template repository itself)
- **init-complete.yml**: `issue_comment` on the initialization issue
- **sync.yml**: daily schedule plus `workflow_dispatch`
- **cascade.yml**: `workflow_dispatch` only (human-triggered, or dispatched by the monitor)
- **cascade-monitor.yml**: every 6 hours, `pull_request_target` closed on `fork_upstream`, plus `workflow_dispatch`
- **validate.yml**: `pull_request` and `pull_request_target` against the three branches, push to the three branches, plus `workflow_dispatch`
- **build.yml**: push to feature branches only; PR events are covered by validate.yml and dependabot-validation.yml so a commit is not built twice
- **release.yml**: push to `main`

### Security
- Secrets stay in GitHub secrets; workflows request minimal token permissions
- Rulesets enforce branch protection (see ADR-001)
- CodeQL scans code and workflows (`codeql.yml`)

### Composite Actions
Reusable actions live in `.github/actions/`, for example `pr-status` (PR status reporting), `java-build` (Maven build), and `java-build-status` (build status with coverage). See ADR-013.

### Error Handling
- Failed workflows create issues labeled `human-required` (ADR-020)
- Cascade state is tracked on issues through their lifecycle (ADR-022)
- `cascade-monitor.yml` re-dispatches a cascade when a trigger was missed or after a human clears the `human-required` label from a failed cascade issue (ADR-019)

## Related Decisions

- [ADR-029: GitHub App Authentication Strategy](029-github-app-authentication-strategy.md) - Authentication mechanism for workflow automation

---

[← ADR-001](001-three-branch-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-003 →](003-template-repository-pattern.md)
