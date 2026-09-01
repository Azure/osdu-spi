# ADR-030: CodeQL Summary Job Pattern for Required Status Checks

## Status
**Accepted** - 2025-10-29

## Context

Fork repositories experienced PR blocking issues when using the CodeQL workflow with GitHub repository rulesets. Two related problems emerged:

### Problem 1: Required Status Check Mismatch

Repository rulesets configured during initialization require a status check named `"CodeQL"`:

```json
{
  "type": "required_status_checks",
  "parameters": {
    "required_status_checks": [
      {"context": "CodeQL"}
    ]
  }
}
```

However, the CodeQL workflow provided different job names:
- `"Check if Code Changes Present"` (always runs)
- `"Detect Project Languages"` (conditional)
- `"Analyze Code"` (conditional)

When PRs contained only configuration changes (e.g., dependabot.yml, workflows), the CodeQL workflow correctly skipped analysis to save resources. However, no check named `"CodeQL"` ever reported, leaving PRs in a **BLOCKED** state indefinitely.

### Problem 2: Code Scanning Rule Blocking Config-Only PRs

The default branch protection ruleset included a `code_scanning` rule:

```json
{
  "type": "code_scanning",
  "parameters": {
    "code_scanning_tools": [{
      "tool": "CodeQL",
      "security_alerts_threshold": "high_or_higher",
      "alerts_threshold": "errors"
    }]
  }
}
```

This rule **requires** CodeQL to upload SARIF results (security scan analysis). For config-only PRs where analysis is appropriately skipped, no SARIF is uploaded, permanently blocking the PR. Even admin override (`gh pr merge --admin`) failed with:

```
Code scanning is waiting for results from CodeQL for the commits...
```

### Impact

- **Template sync PRs blocked**: Config-only changes (dependabot, workflow updates) couldn't merge
- **Dependabot PRs blocked**: Dependency updates for `.github/` files couldn't merge
- **Manual intervention required**: Every config-only PR needed manual ruleset modification
- **Inconsistent security posture**: Some forks removed the rule manually, creating inconsistency

## Decision

Implement a two-part solution:

### 1. Add CodeQL Summary Job

Add a summary job to the CodeQL workflow that:
- **Named `"CodeQL"`**: Matches the required status check context exactly
- **Always executes**: Uses `if: always()` to run regardless of previous job outcomes
- **Smart validation**: Reports success for Markdown-only changes, validates analysis results for everything else
- **Proper failure handling**: Fails if analysis fails, is cancelled, or did not run despite non-Markdown changes

```yaml
CodeQL:
  name: CodeQL  # Job name becomes the check context
  runs-on: ubuntu-latest
  needs: [check-paths, detect-languages, analyze]
  if: always()  # Executes even when analysis skips
  steps:
    - name: Report CodeQL Status
      run: |
        # Validate check-paths succeeded
        if [ "${{ needs.check-paths.result }}" != "success" ]; then
          exit 1
        fi

        # Markdown-only changes: Report success
        if [ "${{ needs.check-paths.outputs.should-run }}" = "false" ]; then
          echo "✅ CodeQL skipped - only Markdown files changed"
          exit 0
        fi

        # Code changes: Validate analysis completed
        if [ "${{ needs.analyze.result }}" = "failure" ] ||
           [ "${{ needs.analyze.result }}" = "cancelled" ]; then
          exit 1
        fi

        echo "✅ CodeQL checks completed successfully"
```

### 2. Remove Code Scanning Rule from Template

Remove the `code_scanning` rule from `.github/rulesets/default-branch.json`:

**Rationale**:
- The rule requires SARIF upload for every PR
- Markdown-only PRs appropriately skip analysis (Markdown is not an analyzed language)
- No SARIF uploaded → PR permanently blocked
- Status checks provide sufficient validation
- CodeQL still runs on every non-Markdown change and reports findings

## Rationale

### Why Summary Job Pattern

1. **Workflow Composability**: GitHub Actions doesn't support renaming jobs dynamically
2. **Single Source of Truth**: One job consolidates the status of multiple conditional jobs
3. **Standard Pattern**: Widely used in GitHub Actions for exactly this use case
4. **Flexibility**: Can add more checks in the future without changing ruleset

This summary-job pattern is the engineering system's general mechanism for any required status check whose workflow is path-filtered or has conditional jobs. It is reused by the `🐳 Docker Build` required check in `validate.yml` (the `docker-build-required` summary job), where `check-initialization` routes each PR to one of the two PR triggers and the other stands down. The summary job repeats that routing because `always()` would otherwise let the standing-down lane report a green that stands for no build. Neither trigger carries `paths-ignore`, so the owning lane always starts and always reports.

The template's own CodeQL workflow feeds a second job into the same summary. The actions extractor only reads `.github/workflows/`, so the template never analyzed what it ships until a fork did (#164). The `template-workflows` job stages `.github/template-workflows/*.yml` where a fork keeps them, runs the forks' `security-extended` suite without uploading, and fails on any finding, so a template regression fails here before it reaches a fork's required `CodeQL` check. Diff-informed analysis is off for that job: the staged paths never appear in a PR diff, and PR runs would otherwise keep only the non-dataflow findings.

### Why Remove Code Scanning Rule

1. **SARIF Upload Requirement**: The rule fundamentally requires results upload
2. **No Conditional SARIF**: Can't conditionally satisfy the rule (it either has results or doesn't)
3. **Analysis Already Validated**: The status check validates that analysis ran when needed
4. **Security Findings Still Visible**: Results still appear in Security tab when analysis runs
5. **Most Teams Prefer Triage**: Blocking on alert thresholds is often too strict; teams prefer to triage findings

## Alternatives Considered

### 1. Always Upload Empty SARIF for Skipped Analysis

**Approach**: Generate and upload a minimal valid SARIF file when analysis is skipped

```yaml
- name: Upload empty SARIF for skipped analysis
  if: needs.check-paths.outputs.should-run == 'false'
  uses: github/codeql-action/upload-sarif@v4
  with:
    sarif_file: empty.sarif
```

**Pros**:
- Satisfies the `code_scanning` rule
- Maintains alert threshold blocking capability

**Cons**:
- Adds complexity and maintenance burden
- Generates misleading data (empty scan results)
- Violates principle of least surprise
- No real security benefit over status checks

**Decision**: Rejected due to complexity without meaningful security benefit

### 2. Rename Existing Jobs to "CodeQL"

**Approach**: Change `check-paths` job name to "CodeQL"

**Pros**:
- Simple, no new jobs

**Cons**:
- Loses semantic meaning ("CodeQL" doesn't describe what check-paths does)
- Doesn't solve code_scanning rule problem
- Confusing when check-paths succeeds but analysis never ran

**Decision**: Rejected due to loss of clarity

### 3. Use Workflow-Level Required Checks Only

**Approach**: Remove job-level requirements, require entire workflow success

**Pros**:
- Simpler configuration

**Cons**:
- GitHub rulesets don't support workflow-level checks (only job names)
- Not technically feasible with current GitHub features

**Decision**: Rejected as not possible

### 4. Keep Code Scanning Rule, Block Config PRs

**Approach**: Accept that config-only PRs will block and require manual override

**Pros**:
- Maintains strict security enforcement

**Cons**:
- Blocks legitimate PRs
- Breaks automation (Dependabot, template sync)
- Manual intervention doesn't scale
- Config files are not analyzed languages, so nothing is gained

**Decision**: Rejected due to operational impact

## Consequences

Config-only and Markdown-only PRs merge without manual intervention while CodeQL still runs on code changes and reports to the Security tab. What is lost is threshold blocking: a fork cannot require zero high-severity alerts before merge, so findings are triaged by review rather than enforced by the ruleset. The summary job could check alert severity later if that becomes necessary.

## Implementation

### Files Changed

1. **`.github/template-workflows/codeql.yml`**
   - Added `CodeQL` summary job
   - Validates previous jobs and reports consolidated status
   - Added build artifact exclusion patterns

2. **`.github/rulesets/default-branch.json`**
   - Removed `code_scanning` rule
   - Kept `required_status_checks` with "CodeQL" context

### Build Artifact Exclusion Pattern

**Problem**: CodeQL language detection was finding generated Python files in build directories (e.g., `build-aws/build-info.py`), attempting to analyze them, and failing because they're malformed or auto-generated code.

**Error Example**:
```
[ERROR] Failed to extract file /home/runner/work/partition/partition/provider/partition-aws/build-aws/build-info.py: 'name'
CodeQL detected code written in Python but could not process any of it.
```

**Solution**: Exclude build and generated code directories from both language detection and CodeQL analysis:

**Language detection** (the `detect-languages` job):
```yaml
# Check for Python (exclude build directories and common generated code paths)
if [ -f "setup.py" ] || [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || \
   find . -name "*.py" \
     -not -path "./.*" \
     -not -path "*/build/*" \
     -not -path "*/build-*/*" \
     -not -path "*/target/*" \
     -not -path "*/dist/*" \
     -not -path "*/__pycache__/*" \
     -not -path "*/.venv/*" \
     -not -path "*/venv/*" \
     -not -path "*/node_modules/*" | grep -q .; then
  LANGUAGES=$(echo "$LANGUAGES" | jq -c '. + ["python"]')
fi
```

**CodeQL configuration** (the `analyze` job):
```yaml
- name: Initialize CodeQL
  uses: github/codeql-action/init@v4
  with:
    languages: ${{ matrix.language }}
    queries: security-extended
    build-mode: none
    config: |
      paths-ignore:
        - '**/build/**'
        - '**/build-*/**'
        - '**/target/**'
        - '**/dist/**'
        - '**/__pycache__/**'
        - '**/.venv/**'
        - '**/venv/**'
        - '**/node_modules/**'
        - '**/.pytest_cache/**'
        - '**/.mypy_cache/**'
```

### Migration Path for Existing Forks

Rulesets are no longer edited by hand. `.github/rulesets/default-branch.json` and `integration-branch.json` are synced to every fork, and `settings-apply.yml` reconciles the live rulesets against them on a schedule and on dispatch, so a fork created with the `code_scanning` rule loses it on the next reconciliation. Template sync delivers the updated CodeQL workflow at the same time.

## Related Decisions

- **ADR-010**: YAML-safe shell scripting pattern (used in summary job)
- **ADR-028**: Workflow script extraction pattern (influenced job structure)

## References

- GitHub Issue: PR blocking on template sync (2025-10-29)
- Production Testing: danielscholl-osdu/partition, danielscholl-osdu/entitlements
- GitHub Docs: [Repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- GitHub Docs: [CodeQL code scanning](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning-with-codeql)

---

[← ADR-029](029-github-app-authentication-strategy.md) | :material-arrow-up: [Catalog](index.md)
