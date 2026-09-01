# ADR-013: Reusable GitHub Actions Pattern for PR Creation

## Status

**Accepted** - 2025-10-01. **Partially superseded** 2026-09-01 by #162: the
`create-enhanced-pr` and `llm-provider-detect` actions this ADR specifies were deleted with
the AI path (see ADR-014). The reusable-composite-action pattern still stands and is used by
`upstream-filter`, `sync-state-manager`, and `acceptance-resolver`; the PR-creation worked
example below is historical.

## Context

During implementation of template synchronization (ADR-011, ADR-012), the upstream sync and template sync workflows each embedded the same PR creation logic: detect an available LLM, generate a description, fall back to a provided description on failure, create the PR, and return its URL and number. Duplicated logic drifted apart, had to be tested twice, and improvements to one copy did not reach the other.

## Decision

Extract shared workflow logic into composite actions under `.github/actions/`, each with a declared input and output interface, so that workflows call one implementation instead of carrying their own copy.

### Composite action structure

```yaml
runs:
  using: 'composite'
  steps:
    - name: <step one>
    - name: <step two>
```

Each action owns one concern, exposes inputs with defaults, and returns outputs that workflows consume through `steps.<id>.outputs`. The directory is listed in `sync-config.json` as a synced directory, so forks receive action updates through template sync.

### Historical worked example: `create-enhanced-pr`

The original action took a token, base and head branches, a title, and a fallback description; optionally an Azure Foundry key and endpoint, a maximum diff size, and a vulnerability-analysis flag. It returned the PR URL, PR number, and whether an AI description was used. It was called from the template sync workflow and was removed in #162 along with the AI path. PR bodies are now computed from git (ADR-023).

### Branch dependency limitation

GitHub Actions can only reference local actions that exist on the branch the workflow checks out. At the time, the upstream sync workflow ran from `fork_upstream`, which carries no template infrastructure, so it could not use a `main`-only action and embedded its logic instead. The general rule still applies: a workflow may use a local action only when it checks out a branch that contains it. Today `sync.yml` checks out `main`.

## Alternatives Considered

1. **Shared shell functions**: rejected; limited parameter handling and harder to test.
2. **Marketplace action**: rejected; the PR-creation requirements were specific to this template.
3. **Copy-paste with documentation**: rejected; the maintenance burden this decision set out to remove.
4. **Workflow templates**: rejected; cannot be used within the same repository.
5. **NPM package**: rejected; external dependency and Node setup in every workflow.

## Consequences

Composite actions add a layer between workflows and the GitHub API and are harder to exercise locally. In exchange, one implementation serves every workflow, and behavior changes are made in one place.

## Related ADRs

- **ADR-011**: Configuration-Driven Template Synchronization (syncs `.github/actions` to forks)
- **ADR-012**: Template Update Propagation Strategy
- **ADR-014**: AI-Enhanced Development Workflow Integration (superseded; the AI path this action carried)
- **ADR-023**: Meta-Commit Strategy (PR bodies computed from git)
- **ADR-028**: Workflow Script Extraction Pattern
---

[← ADR-012](012-template-update-propagation-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-014 →](014-ai-enhanced-development-workflow.md)
