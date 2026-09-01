# ADR-010: YAML-Safe Shell Scripting in GitHub Actions

## Status
**Accepted** - 2025-10-01

## Context

GitHub Actions workflows embed shell scripts in YAML, so shell text containing YAML-meaningful characters can break the workflow file. While building the initialization completion message we hit parser errors from a multi-line shell variable assignment that contained colons, apostrophes, and backticks:

```yaml
run: |
  MANUAL_STEPS="## Manual Configuration Required

  Since no GH_TOKEN was provided, please complete these steps:

  ### 1. Branch Protection
  - Go to Settings → Branches
  - For each branch (`main`, `fork_upstream`, `fork_integration`):
    - Require pull request reviews before merging
  "
```

```
line 351: could not find expected ':'
line 353: mapping values are not allowed in this context
```

## Decision

1. **Keep long or formatted content out of workflow YAML.** Store it in files and read it at runtime. The initialization completion message and its manual-steps sections live in `.github/local-actions/templates/`, and `init-complete.yml` assembles the comment from those files.
2. **Keep inline shell strings short.** A shell variable assigned inside a `run:` block should be a single line or a small number of concatenated lines with no colons at the start of a line, no unbalanced quotes, and no heredoc-in-subshell constructs.
3. **Validate workflow YAML before committing.** Every workflow change must parse:

```bash
yq e '.' .github/workflows/<workflow-name>.yml >/dev/null && echo "YAML is valid"
```

## Alternatives Considered

### 1. Inline strings only
Keep everything in the workflow and simplify the wording until it parses. Rejected as the sole rule: it limits what messages can say and every edit risks a new parse error.

### 2. JSON-encoded strings
Guaranteed YAML compatibility, but unreadable and hard to edit. Rejected.

### 3. GitHub Actions expressions
Native syntax, but limited formatting and the expressions become their own source of complexity. Rejected.

## Consequences
Formatted messages need a separate file, which is one more thing to keep in sync with the workflow that reads it. In exchange the workflow file stays parseable and the message content can be edited without touching YAML.

## References

- **GitHub Actions Documentation**: [Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- **YAML Specification**: [YAML Ain't Markup Language (YAML™) 1.2](https://yaml.org/spec/1.2.2/)
- **Related ADR**: [ADR-006: Two-Workflow Initialization Pattern](006-two-workflow-initialization.md)
---

[← ADR-009](009-asymmetric-cascade-review-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-011 →](011-configuration-driven-template-sync.md)
