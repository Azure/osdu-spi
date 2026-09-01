# ADR-012: Template Update Propagation Strategy

## Status
**Accepted** - 2025-10-01  

## Context

Following the configuration-driven sync (ADR-011), we needed a strategy for propagating template updates to existing forks. The sync configuration defined *what* should be synchronized; this decision defines *how* and *when* template updates reach forks.

Requirements:

- Template improvements reach forks without manual intervention
- Only template infrastructure is updated, never project-specific content
- Teams see exactly which files changed and which template commits produced them
- Updates go through pull request review before being applied
- Each fork records which template commit it is synchronized to

Challenges: how forks acquire the sync capability initially (bootstrap), how relevant template changes are detected, and how updates are scheduled.

## Decision

Implement template update propagation through a dedicated `sync-template.yml` workflow shipped to every fork from `.github/template-workflows/`.

### 1. Template sync workflow

- **Triggers**: daily at 08:00 UTC (`cron: '0 8 * * *'`) plus `workflow_dispatch`
- **Function**: detects template changes in configured paths and opens or updates a pull request against `main`
- **Scope**: only paths defined in the template's `.github/sync-config.json` (ADR-011)
- **Output**: a PR titled `chore(template-sync): sync template updates <date>` labeled `template-sync`. The conventional prefix is required because the validation workflow gates PR titles. The body is computed from git: the changed files and the template commit range (ADR-023 removed generated descriptions).

The workflow opens no tracking issue for template updates. The only issues it creates are a `human-required,template-sync` issue when `labels.json` changed (labels are not synced automatically, ADR-008) and a `template-sync-failed` issue when the run fails.

### 2. Two-repository architecture

- **Template repository**: source of truth for infrastructure improvements
- **Fork repositories**: receive updates via `sync-template.yml`
- **Separation**: template management stays in the template; production automation goes to forks

### 3. Change detection and propagation

The workflow fetches the template's `main`, reads `.github/.template-sync-commit` for the last synced commit, loads the template's `sync-config.json`, and diffs the configured directories, files, and `template_workflows` between the two commits. Changed directories are replaced from the template, changed files are copied, and changed `template-workflows/*.yml` are written to `.github/workflows/`. Fork-resources are redeployed to their final locations (ADR-018). The tracking file is updated to the new template commit in the same commit.

### 4. Bootstrap strategy

The sync workflow is itself in `template_workflows`, so it is copied during initialization and can update itself.

For repositories that predate the tracking file, the workflow auto-bootstraps: when `.github/.template-sync-commit` is missing or empty it uses the earliest template commit touching `.github/` as the baseline (falling back to the first template commit), writes the tracking file immediately, and produces a first PR covering every template change since that baseline. See the "Check for template updates" step in `sync-template.yml`.

### 5. Duplicate prevention

Following the upstream sync pattern (ADR-024), the workflow keeps at most one open template-sync PR. It looks for an open PR labeled `template-sync` targeting `main`; if one exists and the template has advanced, it force-pushes the existing branch, retitles the PR with `(updated <date>)`, and comments with the new commit range. Details are in ADR-031.

| Existing PR | Template changed | Action                    |
|-------------|------------------|---------------------------|
| No          | Yes              | Create new PR             |
| Yes         | No               | No action                 |
| Yes         | Yes              | Update existing branch/PR |
| No          | No               | No action                 |

## Alternatives Considered

1. **Push-based updates from the template**: rejected; requires write access to every fork.
2. **Manual update process**: rejected; relies on teams remembering to update.
3. **Webhook-based real-time updates**: rejected; complex setup and risk of PR spam. A scheduled check is predictable.
4. **Git submodule for template infrastructure**: rejected; does not handle selective syncing.

## Consequences

Forks receive a PR whenever configured template paths change, which requires review attention. Template changes can conflict with local modifications to synced paths; the PR surfaces the conflict before merge. Forks depend on the template repository being reachable. The daily schedule means an update takes up to a day to reach forks unless triggered manually.

## Related ADRs

- **ADR-011**: Configuration-Driven Template Synchronization (provides the foundation for this strategy)
- **ADR-015**: Template-Workflows Separation Pattern (defines where fork workflows live)
- **ADR-018**: Fork-Resources Staging Pattern (specialized deployment during sync)
- **ADR-023**: Meta-Commit Strategy (PR bodies computed from git)
- **ADR-031**: Template Sync Duplicate Prevention Pattern (prevents duplicate template-sync PRs)
- **ADR-024**: Sync Workflow Duplicate Prevention Architecture (upstream sync pattern that inspired ADR-031)
- **ADR-003**: Template Repository Pattern (original template architecture, extended by this decision)

---

[← ADR-011](011-configuration-driven-template-sync.md) | :material-arrow-up: [Catalog](index.md) | [ADR-013 →](013-reusable-github-actions-pattern.md)
