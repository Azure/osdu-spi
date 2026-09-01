# ADR-011: Configuration-Driven Template Synchronization

## Status
**Accepted** - 2025-10-01

## Context

The template repository pattern (ADR-003) created a bootstrap problem: once repositories were created from the template, there was no systematic way to propagate template improvements (workflow updates, security patches, new features) to existing forks without manual intervention or repository recreation.

Problems with the static template approach:

- Forks became outdated as the template improved, with no automated way to receive workflow or security fixes
- Repositories diverged from the template over time
- Teams had to track and apply template changes by hand

The sync system needed to define exactly which files are synchronized, distinguish template-management files from project-essential files, handle cleanup of template-specific content during initialization, and make the rules visible.

## Decision

Implement configuration-driven template synchronization using `.github/sync-config.json` as the single source of truth for what is synced, what is removed at initialization, and what is never touched.

### 1. Sync configuration file

`.github/sync-config.json` has three top-level sections:

- `sync_rules.directories`: directories synced whole (currently `.github/actions`, `.github/fork-resources`, `build`, `.github/rulesets`, `.github/scripts/settings-apply`)
- `sync_rules.files`: individual files synced (release-please config, `labels.json`, `branch-protection.json`, `security-on.json`, `security-patterns.txt`)
- `sync_rules.workflows.template_workflows`: fork workflows stored under `.github/template-workflows/` and copied to `.github/workflows/` at initialization (ADR-015); `template_only` and `development_only` list the template's own workflows that never reach forks
- `sync_rules.tracking_files`: `.github/.template-sync-commit`, the last synced template commit, auto-created when missing
- `exclusions`: paths never synced (`.github/copilot-instructions.md`, `.github/local-actions`, `.spi`, `CODEOWNERS`)
- `cleanup_rules`: directories, files, and workflows removed during initialization, each with a `reason`

The file itself is authoritative; this ADR does not restate its contents.

### 2. Selective file synchronization

Only infrastructure defined in the configuration is synchronized. Project code, upstream content, and fork-owned files are never touched. Template-only content (initialization workflows, template documentation, local actions) stays in the template and is removed from forks by the cleanup rules.

### 3. Configuration-aware workflows

- `init-complete.yml` applies the configuration through the `sync-config-applier` local action and `init-helpers/deploy-fork-resources.sh`, which copies synced content and executes the cleanup rules
- `sync-template.yml` (the fork workflow, ADR-012) reads the configuration from the template's `main` branch to decide which paths to diff and copy
- `.github/.template-sync-commit` records the template commit each fork is synchronized to

## Alternatives Considered

1. **Manual sync documentation**: rejected; rarely followed and error-prone.
2. **Git subtree or submodule for the template**: rejected; does not handle selective syncing and adds user-facing complexity.
3. **Hardcoded sync lists in workflows**: rejected; no single place to document why a path is synced.
4. **External sync service**: rejected; extra infrastructure and an external dependency.

## Consequences

The configuration is one more file to maintain, and it must exist before sync can work. Because the configuration is itself synced, forks pick up rule changes automatically. Changes to sync behavior are reviewable in version control.

## Related ADRs

- **ADR-003**: Template Repository Pattern for Self-Configuration (updated by this decision)
- **ADR-006**: Two-Workflow Initialization Pattern (enhanced by sync configuration)
- **ADR-012**: Template Update Propagation Strategy (depends on this configuration system)
- **ADR-015**: Template-Workflows Separation Pattern (defines the `template_workflows` list)
- **ADR-018**: Fork-Resources Staging Pattern (defines the `fork-resources` directory)
---

[← ADR-010](010-yaml-safe-shell-scripting.md) | :material-arrow-up: [Catalog](index.md) | [ADR-012 →](012-template-update-propagation-strategy.md)
