# ADR-015: Template-Workflows Separation Pattern

## Status

**Accepted** - 2025-10-01

## Context

GitHub template repositories need two distinct kinds of workflows:

1. **Template development workflows**: for managing the template itself (initialization, CI, releases, docs)
2. **Fork production workflows**: for the repositories created from the template (sync, build, validate, release)

When every workflow lived in `.github/workflows/`, forks inherited template development workflows such as `init.yml` that serve no purpose there, and there was no clear boundary between template infrastructure and fork functionality.

Initialization also hit a permission constraint: a token without the `workflows` permission cannot push workflow files. The error is `refusing to allow a GitHub App to create or update workflow .github/workflows/build.yml without workflows permission`. Writing fork workflows therefore needs a token that carries that permission.

The bootstrap pattern (ADR-007) addressed workflow version updates but not workflow distribution.

## Decision

Keep the template's own workflows in `.github/workflows/` and store the workflows destined for forks in `.github/template-workflows/`. Initialization copies the latter into the fork's `.github/workflows/`.

### Directory structure

```
.github/
├── workflows/                    # Template development workflows (never copied)
│   ├── init.yml                  # Repository initialization trigger
│   ├── init-complete.yml         # Repository setup
│   ├── dev-ci.yml                # Template CI
│   ├── dev-release.yml           # Template releases
│   ├── docs.yml                  # Template documentation site
│   ├── codeql.yml                # Template CodeQL scan
│   └── scorecard.yml             # OpenSSF Scorecard
└── template-workflows/           # Fork production workflows (copied at init)
    ├── sync.yml                  # Upstream synchronization
    ├── sync-template.yml         # Template updates
    ├── cascade.yml               # Cascade integration
    ├── cascade-monitor.yml       # Cascade safety net and health
    ├── integration-cleanup.yml   # fork_integration cleanup after main merges
    ├── validate.yml              # PR validation
    ├── build.yml                 # Project builds
    ├── release.yml               # Semantic releases
    ├── codeql.yml                # Fork CodeQL scan
    ├── dependabot-validation.yml # Dependabot PR automation
    ├── ghcr-retention.yml        # GHCR image-tag retention
    ├── settings-apply.yml        # Per-fork settings reconciliation
    ├── adopt-fork.yml            # Customer-tier adoption (ADR-039)
    └── copilot-setup-steps.yml   # Copilot agent environment
```

The authoritative list is `sync_rules.workflows.template_workflows` in `.github/sync-config.json` (ADR-011); `template_only` and `development_only` name the workflows that stay behind.

### Initialization copy process

`init-complete.yml` runs in the fork's own checkout of the template contents. It copies `.github/template-workflows/*.yml` into `.github/workflows/`, then `init-helpers/deploy-fork-resources.sh` removes `dev-*.yml`, deletes the `template-workflows/` directory, and applies the cleanup rules from `sync-config.json`. No template remote is added at this stage; the fork already contains the template files.

### Authentication

The push that delivers workflow files uses a GitHub App installation token minted in the workflow with `actions/create-github-app-token` (ADR-029). The App is granted the `workflows` permission, so the push succeeds without a personal access token. `GITHUB_TOKEN` is used for everything that does not write workflow files.

### Ongoing updates

`sync-template.yml` (ADR-012) diffs the `template_workflows` list against the fork's last synced template commit and writes changed files to `.github/workflows/`, so forks keep receiving workflow updates after initialization.

## Alternatives Considered

1. **Git submodules for workflow distribution**: rejected; external dependency and submodule knowledge required.
2. **Workflow generation scripts**: rejected; harder to test and less transparent.
3. **Multiple template repositories**: rejected; breaks the single-template model.
4. **Conditional logic inside one set of workflows**: rejected; complex conditions and poor separation.

## Consequences

Forks contain only production workflows. Template maintainers must remember that a workflow intended for forks belongs in `template-workflows/`, not `workflows/`, and must add it to `sync-config.json`. Initialization depends on the GitHub App being installed with the `workflows` permission.

## Related Decisions

- **ADR-006**: Two-Workflow Initialization Pattern (this pattern builds on the initialization architecture)
- **ADR-007**: Initialization Workflow Bootstrap Pattern (versioning; this ADR addresses distribution)
- **ADR-011**: Configuration-Driven Template Synchronization (owns the `template_workflows` list)
- **ADR-013**: Reusable GitHub Actions Pattern (shared action components)
- **ADR-029**: GitHub App Authentication Strategy (the token that pushes workflow files)

## References

- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [GitHub App Permissions](https://docs.github.com/en/developers/apps/building-github-apps/setting-permissions-for-github-apps)
- [Template Repository Documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository)
---

[← ADR-014](014-ai-enhanced-development-workflow.md) | :material-arrow-up: [Catalog](index.md) | [ADR-016 →](016-initialization-security-handling.md)
