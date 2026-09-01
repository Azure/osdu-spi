# ADR-028: Workflow Script Extraction Pattern

## Status

> The `llm-provider-detect` action that originally served as this ADR's worked example was
> deleted in #162 along with the AI path (ADR-014). The extraction pattern is unchanged;
> `sync-state-manager` is now the example.

**Accepted** - 2025-10-01

## Context

The template's workflows carried several thousand lines of bash embedded in YAML `run:` blocks. Embedded scripts cannot be run locally without triggering the workflow, cannot be unit tested, and mix logic changes with workflow structure in every diff. The same provider-detection block was duplicated in two places.

Extraction had to answer four questions:

1. Where do scripts live so template sync (ADR-011, ADR-012) carries them to forks?
2. How do init-only scripts stay out of forks?
3. How do workflows call them without a GitHub App needing the `workflows` permission (ADR-015)?
4. Which scripts are worth extracting and which should stay inline?

## Decision

Extract embedded bash into shell scripts wrapped by composite actions, placed by lifecycle.

### 1. Placement by lifecycle

| Directory | Synced to forks | Used by | Removed after init |
|-----------|-----------------|---------|--------------------|
| `.github/actions/` | Yes (`sync-config.json` `sync_rules.directories`) | Fork workflows: sync, cascade, validate, build, dependabot-validation | No |
| `.github/local-actions/` | No (listed under `exclusions`) | `init.yml`, `init-complete.yml`, and the template's own test suites | Yes (`cleanup_rules`) |
| `.github/scripts/` | Only `settings-apply/` | `settings-apply.yml` and `init-complete.yml` (rulesets, required variables, GHCR visibility); `rotate-app-key.sh` is operator tooling for the template | No |

Two directories keep init-only logic out of forks. Fork instances receive only the actions their ongoing workflows call, and the split makes one-time versus ongoing intent explicit, following the template-workflows separation in ADR-015. `.github/scripts/` was added later for helpers that are plain scripts rather than actions and that both init and a durable workflow need.

### 2. Composite action wrapper

Each script group is wrapped in a composite action so workflows call it with `uses:`. `sync-state-manager` is the live example:

```
.github/actions/sync-state-manager/
├── action.yml                     # inputs, outputs, one step per script
├── get-upstream-sha.sh
├── check-stored-state.sh
├── detect-existing-prs.sh
├── detect-existing-issues.sh
├── cleanup-abandoned-branches.sh
├── make-sync-decision.sh
├── generation-rev.sh
├── record-evaluated-sha.sh
├── update-issue-body.sh
└── README.md                      # local testing instructions
```

`action.yml` runs each script as `"$GITHUB_ACTION_PATH/<script>.sh"` and maps script output to action outputs. `sync.yml` calls it as `uses: ./.github/actions/sync-state-manager` and reads `should_create_pr`, `sync_decision`, and the rest from the step outputs (ADR-024).

Scripts follow one shape: shebang, `set -euo pipefail`, a short header comment, input validation, and dual output (`$GITHUB_OUTPUT` when set, stdout otherwise) so the same script runs unchanged under Actions and on a developer machine.

### 3. Local testing

Each action's README shows how to run its scripts directly. Where the logic warrants it, a test suite lives under `.github/local-actions/<name>-tests/run-tests.sh` and the template's `dev-ci.yml` runs it; `sync-state-manager`, `upstream-filter`, `acceptance-resolver`, and `acceptance-image` have suites.

### 4. Extraction decision matrix

| Criterion | Extract | Keep inline | Weight |
|-----------|---------|-------------|--------|
| Size | Large multi-step blocks | Short blocks | High |
| Complexity | Decision matrices, state machines, platform-compatibility logic | Simple conditionals, straightforward commands | Critical |
| Reusability | Used in two or more places, or planned reuse | Single-use workflow logic | High |
| Testability value | Needs local validation (date parsing, complex conditionals) | Obvious behaviour | High |
| Type | Composite action logic | Workflow orchestration | Medium |
| Duplication | Duplicated code exists | Unique implementation | Critical |

Extract when two or more criteria favour it and the block is either large or of critical complexity. Keep inline when the criteria are mostly low-weight or the block is orchestration.

### 5. Orchestration stays inline

End-to-end flows in `cascade.yml`, `validate.yml`, and `sync-template.yml` remain inline. They are workflow-specific, read well in context, and extracting them would add a layer without a reuse benefit. A piece of orchestration is extracted only when a second workflow needs the same logic.

## Alternatives Considered

**External script repository**: separate versioning, but an external dependency that breaks the self-contained template. Rejected.

**Keep scripts embedded**: no structural change, but no local testing and continued duplication. Rejected.

**Git submodules**: version pinning, but poor developer experience and harder sync propagation. Rejected.

**A `.github/scripts/` directory instead of actions**: originally rejected to avoid touching `sync-config.json`. Later adopted in a limited form for `settings-apply/` (synced) and `rotate-app-key.sh` (template only), because those helpers are called by `bash` from more than one workflow and do not need action inputs or outputs.

## Consequences

Workflows call actions which call scripts, so a reader follows one more hop; the README in each action directory is the map. Extraction is uneven by design: init helpers and state management are extracted, orchestration is not, and the boundary for medium-complexity blocks is a judgement call against the matrix above. `issue-state-manager` under `.github/actions/` was extracted under this pattern but currently has no workflow caller.

## Related ADRs

- **ADR-010**: YAML-Safe Shell Scripting - Addresses YAML syntax safety
- **ADR-011**: Configuration-Driven Template Sync - Provides sync mechanism
- **ADR-012**: Template Update Propagation - Describes how scripts propagate
- **ADR-013**: Reusable GitHub Actions Pattern - Establishes composite action patterns
- **ADR-015**: Template-Workflows Separation - Explains workflow permission constraints and template/fork separation pattern
- **ADR-018**: Fork-Resources Staging Pattern - Similar two-stage deployment pattern for specialized resources
- **ADR-024**: Sync Workflow Duplicate Prevention - The `sync-state-manager` action used as the example here

## References

- [GitHub Actions: Creating a composite action](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action)
- [GitHub Actions: Workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- Template repository: `.github/sync-config.json`

---

[← ADR-027](027-documentation-generation-strategy.md) | :material-arrow-up: [Catalog](index.md)
