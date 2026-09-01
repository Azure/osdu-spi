# ADR-018: Fork-Resources Staging Pattern for Specialized Template Deployment

## Status

Accepted

## Context

Some template resources need deployment handling beyond copying a file to the same path:

1. **Issue templates**: should exist in forks but not be overwritten by every template sync
2. **Copilot configuration**: instructions and firewall settings deployed to `.github/`, with a repository variable set from the firewall file
3. **Prompt files**: copied into `.github/prompts/`
4. **Service-specific configuration**: `dependabot.yml` and `upstream-filter.yml` carry a `<service>` placeholder substituted at deployment

The existing sync mechanisms (ADR-011, ADR-012) handle direct sync (same path in template and fork) and workflow templates (`template-workflows/` to `.github/workflows/`). They do not cover multi-target deployment, conditional processing, substitution, or staging directories that must not exist in forks.

## Decision

Establish `.github/fork-resources/` as a staging area for template resources that require specialized deployment.

### Architecture

```
Template Repository:
├── .github/
│   ├── fork-resources/              # Staging area (template only)
│   │   ├── ISSUE_TEMPLATE/          # → copied to .github/ISSUE_TEMPLATE/
│   │   ├── copilot-instructions.md  # → copied to .github/copilot-instructions.md
│   │   ├── copilot-firewall-config.json # → copied to .github/ + repository variable
│   │   ├── dependabot.yml           # → substituted to .github/dependabot.yml
│   │   ├── triage.prompt.md         # → copied to .github/prompts/
│   │   └── upstream-filter.yml      # → substituted to .github/upstream-filter.yml
│   └── sync-config.json             # Includes fork-resources in sync rules

Fork Repository (after deployment):
├── .github/
│   ├── ISSUE_TEMPLATE/              # Final location
│   ├── copilot-instructions.md     # Final location
│   ├── prompts/                     # Final location
│   └── (no fork-resources/)        # Staging area removed
```

### Deployment mechanisms

1. **Initialization** (`init-complete.yml`): `init-helpers/deploy-fork-resources.sh` copies each resource to its final location, sets the Copilot firewall repository variable from `copilot-firewall-config.json`, and removes `fork-resources/`
2. **Update** (`sync-template.yml`): when `fork-resources` changes in the template, the sync re-copies the resources to their final locations and removes the staging directory again
3. **Sync configuration**: `.github/fork-resources` is listed in `sync_rules.directories` with `sync_all: true`, so changes are detected by template sync

### Pattern rules

1. **Staging only**: `fork-resources/` exists only in the template repository, never in forks
2. **Specialized logic**: each resource type can have its own deployment step
3. **Cleanup required**: deployment must remove `fork-resources/` after processing
4. **Sync integration**: changes to `fork-resources` flow through the normal template sync
5. **Service substitution**: a resource may carry a `<service>` placeholder, replaced at deployment with the service slug derived from `UPSTREAM_REPO_URL` (the URL basename). `dependabot.yml` and `upstream-filter.yml` use this today.
6. **Fork-owned after planting**: `upstream-filter.yml` deploys create-if-missing only. Once planted it belongs to the fork, and template sync never overwrites it.

## Alternatives Considered

1. **Direct sync**: rejected; issue templates would be overwritten on every sync, and there is no way to deploy one source to a different path or to substitute values.
2. **Hardcoded deployment in workflows**: rejected; every new resource type would require a workflow change.

## Consequences

Resources are maintained in the staging directory rather than at their final path, and each resource type needs its own deployment step. Deployment logic for similar resources can diverge, and a missed cleanup would leave the staging directory in a fork.

## Related ADRs

- **ADR-011**: Configuration-Driven Template Synchronization (adds `fork-resources` to the sync rules)
- **ADR-012**: Template Update Propagation Strategy (redeploys resources during template sync)
- **ADR-038**: Upstream Filter Transform (consumer of `upstream-filter.yml`)

---

[← ADR-016](016-initialization-security-handling.md) | :material-arrow-up: [Catalog](index.md) | [ADR-019 →](019-cascade-monitor-pattern.md)
