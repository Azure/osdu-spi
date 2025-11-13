# ADR-031: Template Sync Duplicate Prevention Pattern

## Status
Accepted

## Context

Following the successful implementation of duplicate prevention for upstream sync workflows (ADR-024), the same problem was identified in the template sync workflow. The daily template sync workflow (`template-sync.yml`) was creating duplicate PRs when humans delayed reviewing PRs, causing:

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
- Update PR title to show "(Updated YYYY-MM-DD)"
- Regenerate PR description with all current changes
- Add comment about the update (with duplicate comment prevention)

## Rationale

### Why Not Reuse sync-state-manager Action?

**Decision: Inline Implementation**

The sync-state-manager action was designed for upstream sync's more complex state management needs (tracking upstream SHA, issue lifecycle, cascade coordination). Template sync has simpler requirements:

1. **Simpler State**: Only needs to track PR existence, not upstream versions
2. **No Issue Tracking**: Template sync doesn't create tracking issues like upstream sync
3. **Different Base Branch**: Targets `main` instead of `fork_upstream`
4. **Self-Contained**: All logic fits naturally in workflow without external scripts

**Benefits of Inline Approach:**
- **Simplicity**: Easier to understand and maintain
- **Performance**: No additional action overhead
- **Clarity**: All logic visible in single workflow file
- **Maintainability**: Changes don't affect upstream sync logic

### Consistency with ADR-024 Pattern

Despite the implementation difference, the pattern remains consistent:
- **Same decision matrix** for handling duplicates
- **Same branch reuse strategy** with force-push
- **Same PR update behavior** with comments
- **Same label-based tracking** approach

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

```yaml
- name: Create new template sync PR
  if: steps.check-updates.outputs.has_updates == 'true' &&
      env.has_changes == 'true' &&
      steps.detect-existing.outputs.has_existing_pr == 'false'
  id: create-pr
  uses: ./.github/actions/create-enhanced-pr
  # See .github/template-workflows/sync-template.yml for implementation details (PR creation and labeling)

- name: Update existing template sync PR
  if: steps.check-updates.outputs.has_updates == 'true' &&
      env.has_changes == 'true' &&
      steps.detect-existing.outputs.has_existing_pr == 'true'
  id: update-pr
  # See .github/template-workflows/sync-template.yml for implementation details (PR update logic)
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

### Positive

- ✅ **Eliminates duplicate template-sync PRs** - Core problem solved
- ✅ **Consistent with upstream sync pattern** - Same architectural approach
- ✅ **Simpler implementation** - Inline logic easier to maintain than action
- ✅ **Clean repository state** - No accumulation of stale PRs
- ✅ **Reduced notification fatigue** - Single PR per template update cycle
- ✅ **Clear PR progression** - Updated PRs show complete history
- ✅ **Preserves human workflow** - Same PR URL throughout update cycle

### Negative

- ⚠️ **Code duplication with sync-state-manager** - Detection logic duplicated (but simplified)
- ⚠️ **No shared state management** - Each workflow manages its own state
- ⚠️ **Different from upstream sync** - Uses inline approach vs action approach

### Neutral

- 📝 **Pattern reuse** - Same architectural pattern, different implementation
- 📝 **No breaking changes** - Existing forks work without modification
- 📝 **Automatic distribution** - sync-config.json handles deployment

## Comparison with ADR-024

| Aspect | Upstream Sync (ADR-024) | Template Sync (ADR-031) |
|--------|-------------------------|-------------------------|
| **Pattern** | Duplicate prevention via state management | Same pattern |
| **Implementation** | Dedicated action (`sync-state-manager`) | Inline detection logic |
| **Label** | `upstream-sync` | `template-sync` |
| **Base Branch** | `fork_upstream` | `main` |
| **State Tracking** | Git config + issue lifecycle | PR detection only |
| **Complexity** | Higher (cascade coordination) | Lower (PR-only) |
| **Reusability** | Action reusable by other workflows | Workflow-specific logic |

## Success Criteria

- ✅ **Reduction in duplicate template-sync PRs** - Primary success indicator
- ✅ **Single active template-sync PR** - Only one open at any time
- ✅ **PR updates work correctly** - Force-push and description updates succeed
- ✅ **No notification spam** - Reduced GitHub notification volume
- ✅ **Clear PR progression** - Updated PRs show complete change history
- ✅ **Automatic label management** - `template-sync` label correctly applied

## Testing Strategy

Real-world validation through production fork repositories:
- Monitor daily template-sync workflow executions
- Verify single PR creation/update behavior
- Confirm force-push updates work correctly
- Validate PR description regeneration
- Check duplicate comment prevention

## References

- [ADR-024: Sync Workflow Duplicate Prevention Architecture](024-sync-workflow-duplicate-prevention-architecture.md) - Original pattern
- [ADR-012: Template Update Propagation Strategy](012-template-update-propagation-strategy.md) - Template sync workflow
- [ADR-011: Configuration-Driven Template Synchronization](011-configuration-driven-template-sync.md) - Template sync foundation
- [Evidence: Multiple Template Sync PRs](https://github.com/danielscholl-osdu/workflow/pulls) - Production repository showing duplicate PR problem

---

[← ADR-030](030-codeql-summary-job-pattern.md) | :material-arrow-up: [Catalog](index.md)
