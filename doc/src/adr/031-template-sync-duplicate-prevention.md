# ADR-031: Template Sync Duplicate Prevention Pattern

## Status
Accepted

## Context

Following the successful implementation of duplicate prevention for upstream sync workflows (ADR-024), the same problem was identified in the template sync workflow. The daily template sync workflow (`sync-template.yml`) was creating duplicate PRs when humans delayed reviewing PRs, causing:

1. **Duplicate template-sync PRs** - Multiple open PRs for the same template updates
2. **Repository clutter** - Accumulation of stale template-sync branches
3. **Notification fatigue** - Redundant GitHub notifications for template updates
4. **Confusion** - Unclear which PR contains the latest template changes

**Evidence of the Problem:**

In production fork repositories, template-sync was creating a new PR every day when changes existed, even if a previous PR was still open. This resulted in 6+ open template-sync PRs simultaneously (e.g., PRs #12-18 in danielscholl-osdu/workflow).

**Relationship to ADR-024:**

ADR-024 solved this problem for upstream sync using the `sync-state-manager` action. Template sync needed the same duplicate prevention pattern, but with a simpler inline implementation.

## Decision

Implement **Template Sync Duplicate Prevention** following the same architectural pattern as upstream sync (ADR-024), but with inline detection logic instead of using the sync-state-manager action:

### 1. PR Detection and Label-Based Tracking

- **New Label**: `template-sync` added to `.github/labels.json`
- **Detection Logic**: Query GitHub API for open PRs with `template-sync` label targeting `main` branch
- **Inline Implementation**: Detection logic embedded directly in workflow (not extracted to action)

### 2. Decision Matrix (Identical to Upstream Sync)

```
| Existing PR | Template Changed | Action                    |
|-------------|------------------|---------------------------|
| No          | Yes              | Create new PR             |
| Yes         | No               | No action needed          |
| Yes         | Yes              | Update existing branch/PR |
| No          | No               | No action needed          |
```

### 3. Branch Reuse Strategy

- **Existing PR Found**: Reuse existing branch, reset to `main`, force-push updates
- **No PR Found**: Create new timestamped branch (`template-sync/YYYYMMDD-HHMMSS`)
- **Single Active PR**: Only one template-sync PR open at any time

### 4. PR Update Behavior

When updating an existing PR:
- Force-push new commits to existing branch
- Update the PR title to `chore(template-sync): sync template updates (updated YYYY-MM-DD)`; the conventional prefix stays first because the semantic PR check reads the type from it
- Regenerate PR description with all current changes
- Post a comment recording the new template commit and update time

## Rationale

### Why Not Reuse sync-state-manager Action?

**Decision: Inline Implementation**

The sync-state-manager action was designed for upstream sync's more complex state management needs (tracking upstream SHA, issue lifecycle, cascade coordination). Template sync has simpler requirements:

1. **Simpler State**: Only needs to track PR existence, not upstream versions
2. **No Issue Tracking**: Template sync doesn't create tracking issues like upstream sync
3. **Different Base Branch**: Targets `main` instead of `fork_upstream`
4. **Self-Contained**: All logic fits naturally in workflow without external scripts

## Implementation Details

### Detection Step (New)

```yaml
- name: Detect existing template sync PRs
  id: detect-existing
  if: steps.check-updates.outputs.has_updates == 'true'
  env:
    GITHUB_TOKEN: ${{ steps.app-token.outputs.token }}
  run: |
    echo "Detecting existing template sync PRs..."

    # Query for open PRs with template-sync label targeting main branch
    EXISTING_PR=$(gh pr list \
      --state open \
      --label "template-sync" \
      --base main \
      --json number,headRefName \
      --jq '.[0]')

    if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
      PR_NUMBER=$(echo "$EXISTING_PR" | jq -r '.number')
      PR_BRANCH=$(echo "$EXISTING_PR" | jq -r '.headRefName')
      echo "has_existing_pr=true" >> $GITHUB_OUTPUT
      echo "existing_pr_number=$PR_NUMBER" >> $GITHUB_OUTPUT
      echo "existing_pr_branch=$PR_BRANCH" >> $GITHUB_OUTPUT
    else
      echo "has_existing_pr=false" >> $GITHUB_OUTPUT
    fi
```

### Branch Management (Modified)

```yaml
- name: Create or update template sync branch
  if: steps.check-updates.outputs.has_updates == 'true'
  run: |
    if [ "${{ steps.detect-existing.outputs.has_existing_pr }}" = "true" ]; then
      # Reuse existing branch
      SYNC_BRANCH="${{ steps.detect-existing.outputs.existing_pr_branch }}"
      git fetch origin $SYNC_BRANCH
      git checkout -b $SYNC_BRANCH origin/$SYNC_BRANCH
      git reset --hard refs/heads/main
    else
      # Create new sync branch with timestamp
      DATE_SUFFIX=$(date +%Y%m%d-%H%M%S)
      SYNC_BRANCH="template-sync/${DATE_SUFFIX}"
      git checkout -b $SYNC_BRANCH refs/heads/main
    fi

    echo "SYNC_BRANCH=$SYNC_BRANCH" >> $GITHUB_ENV
```

### Split PR Creation (New)

PR creation originally went through a `create-enhanced-pr` action that also produced an AI-written description; #162 removed that action (ADR-014) and both paths now call `gh` directly with a body computed from the diff.

```yaml
- name: Create new template sync PR
  if: steps.check-updates.outputs.has_updates == 'true' &&
      env.has_changes == 'true' &&
      steps.detect-existing.outputs.has_existing_pr == 'false'
  id: create-pr
  # gh pr create --body-file with the template-sync label; see sync-template.yml

- name: Update existing template sync PR
  if: steps.check-updates.outputs.has_updates == 'true' &&
      env.has_changes == 'true' &&
      steps.detect-existing.outputs.has_existing_pr == 'true'
  id: update-pr
  # gh pr edit --title/--body-file, then gh pr comment; see sync-template.yml
```

### Label Definition

```json
{
  "name": "template-sync",
  "description": "Template repository synchronization",
  "color": "0e8a16"
}
```

## Consequences

Detection logic is a simplified copy of what `sync-state-manager` does for upstream sync, so the two implementations can drift apart and each workflow manages its own state.

## Comparison with ADR-024

| Aspect | Upstream Sync (ADR-024) | Template Sync (ADR-031) |
|--------|-------------------------|-------------------------|
| **Pattern** | Duplicate prevention via state management | Same pattern |
| **Implementation** | Dedicated action (`sync-state-manager`) | Inline detection logic |
| **Label** | `upstream-sync` | `template-sync` |
| **Base Branch** | `fork_upstream` | `main` |
| **State Tracking** | Full-SHA issue marker + PR/issue labels | PR detection only |
| **Complexity** | Higher (cascade coordination) | Lower (PR-only) |
| **Reusability** | Action reusable by other workflows | Workflow-specific logic |

## References

- [ADR-024: Sync Workflow Duplicate Prevention Architecture](024-sync-workflow-duplicate-prevention-architecture.md) - Original pattern
- [ADR-012: Template Update Propagation Strategy](012-template-update-propagation-strategy.md) - Template sync workflow
- [ADR-011: Configuration-Driven Template Synchronization](011-configuration-driven-template-sync.md) - Template sync foundation

---

[← ADR-030](030-codeql-summary-job-pattern.md) | :material-arrow-up: [Catalog](index.md)
