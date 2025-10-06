# ADR-024: Sync Workflow Duplicate Prevention Architecture

## Status
Accepted

## Context
The daily upstream sync workflow in the Fork Management Template creates duplicate PRs and issues when humans delay reviewing PRs, causing notification fatigue and repository clutter. This problem manifests in multiple scenarios:

1. **Same upstream state triggers multiple syncs** - Human delays reviewing PR, next day's sync creates identical duplicate PR/issue
2. **Upstream advances while previous sync PR is open** - Creates new PR with 4 commits while old PR with 3 commits still exists  
3. **Failed syncs leave abandoned branches** - Stale sync branches accumulate from failed workflow runs

## Problem Statement

The existing sync workflow lacks state management between runs, resulting in:

- **Duplicate PRs/issues** for identical upstream states
- **Notification fatigue** from redundant GitHub notifications
- **Repository clutter** from abandoned sync branches
- **Broken workflow continuity** when humans track multiple sync artifacts
- **Confusion about which PR is current** when upstream advances

## Decision

We implement a comprehensive duplicate prevention system for sync workflows with these components:

### 1. Overall Strategy

- **State-based duplicate detection** using git config persistence
- **Smart decision matrix** for handling all duplicate scenarios
- **Graceful degradation** to existing behavior when detection fails
- **Clean separation of concerns** via dedicated GitHub Action

### 2. State Persistence Pattern

**Options Considered:**

- GitHub variables (rejected - limited and requires additional tokens)
- Git notes (rejected - complexity and merge conflicts)
- External storage (rejected - dependency and complexity)
- **Git config (chosen)** - simple, reliable, scoped to repository

**Implementation:**

- Track upstream SHA, PR/issue numbers, timestamps
- Persist state between workflow runs
- Automatic cleanup when PRs/issues are closed

### 3. Branch Management Strategy

**Options Considered:**

- Close old PRs and create new ones (rejected - breaks human workflow continuity)
- Leave both PRs open (rejected - confusing and cluttered)
- **Update existing sync branches (chosen)** - maintains continuity

**Implementation:**

- Force-push to existing branches when upstream advances
- Update PR metadata and titles
- Maintain same PR/issue URLs for human tracking

### 4. Implementation Pattern

**Options Considered:**

- Inline implementation in sync.yml (rejected - poor maintainability)
- **Dedicated action (chosen)** - better separation of concerns

**Implementation:**

- `sync-state-manager` action following GitHub best practices
- Reusable by other workflows
- Comprehensive error handling and logging

## Architecture Components

### sync-state-manager Action

**Purpose:** Encapsulate duplicate detection and state management logic
**Location:** `.github/actions/sync-state-manager/action.yml`

**Key Functions:**

- Detect existing open sync PRs using `upstream-sync` label
- Compare current upstream SHA with stored last-synced SHA
- Clean up abandoned sync branches (>24h old, no associated PR)
- Make intelligent decisions based on current state

**Decision Matrix:**

```
| Existing PR | Upstream Changed | Action                    |
|-------------|------------------|---------------------------|
| No          | Yes              | Create new PR and issue   |
| Yes         | No               | Add reminder comment      |
| Yes         | Yes              | Update existing branch    |
| No          | No               | No action needed          |
```

### State Management

**Storage:** Git config variables scoped to repository

- `sync.last-upstream-sha`: Last successfully processed upstream SHA
- `sync.current-pr-number`: Active sync PR number (if any)
- `sync.current-issue-number`: Active tracking issue number (if any)
- `sync.last-sync-timestamp`: Timestamp of last sync attempt

**Persistence:** Automatic across workflow runs

**Cleanup:** Automatic when PRs/issues are closed or merged

### Integration Points

**Pre-Sync Validation Step:** Uses sync-state-manager action after "Configure Git"

**Conditional Sync Step:** Modified to handle branch updates vs new creation

**Smart PR Management:** Skip/update/create based on action outputs

**Intelligent Issue Management:** Skip/comment/create based on action outputs

## Implementation Benefits

### Technical Benefits

- **Eliminates duplicate PRs/issues** across all scenarios
- **Maintains clean repository state** with automatic cleanup
- **Preserves human workflow continuity** with consistent URLs
- **Better maintainability** with action pattern separation
- **Reusable by other workflows** for similar state management needs

### User Experience Benefits

- **Single tracking issue** throughout entire sync cycle
- **No duplicate notifications** reducing noise
- **Always current upstream state** in active PR
- **Clear progression history** in issue comments
- **Reduced cognitive load** - same URLs to track

## Implementation Details

### Files Modified/Created

1. **`.github/actions/sync-state-manager/action.yml`** - New action for state management
2. **`.github/template-workflows/sync.yml`** - Modified sync workflow using new action
3. **`doc/src/adr/024-sync-workflow-duplicate-prevention-architecture.md`** - This ADR

### Key Changes

- **Pre-sync validation step** checks for existing sync PRs/issues
- **Upstream SHA comparison** tracks last synced state
- **Branch update logic** updates existing branches instead of creating new ones
- **State persistence** stores sync state between runs via git config
- **Cleanup logic** removes abandoned sync branches

### Error Handling

- **GitHub API Failures:** Graceful degradation to create new PR/issue
- **State Corruption:** Automatic state reset and fallback to normal workflow
- **Branch Access Issues:** Skip branch cleanup if git operations fail
- **Backwards Compatibility:** No changes to existing sync behavior if detection disabled

## Consequences

### Positive

- ✅ **Eliminates duplicate PRs/issues** - Core problem solved
- ✅ **Maintains clean repository state** - Automatic cleanup
- ✅ **Preserves human workflow continuity** - Same URLs to track
- ✅ **Better maintainability** - Action pattern follows best practices
- ✅ **Reusable by other workflows** - State management available elsewhere
- ✅ **Graceful degradation** - Fallback to existing behavior on failure

### Negative

- ⚠️ **Requires state persistence** between runs - Added complexity
- ⚠️ **Added complexity** in sync workflow - More decision logic
- ⚠️ **Potential edge cases** in decision logic - Requires thorough testing

### Neutral

- 📝 **No breaking changes** - Existing forks continue working
- 📝 **Automatic distribution** - sync-config.json handles deployment
- 📝 **No external dependencies** - Uses existing GitHub tokens and permissions

## Testing Strategy

Testing will be conducted through real-world scenarios by monitoring the behavior of daily sync workflows in production environments. The duplicate prevention logic will be validated by observing:

- Proper detection of duplicate sync scenarios
- Correct branch update behavior when upstream advances
- State persistence across multiple sync runs
- Cleanup of abandoned sync branches
- Action reliability and graceful degradation

## Rollout Plan

1. **Implementation Phase**: Create action and update workflow in single PR
2. **Deployment Phase**: Automatic sync-template workflow distributes changes
3. **Monitoring Phase**: Validate duplicate prevention in production forks
4. **Success Assessment**: Confirm reduction in duplicate PRs/issues

## Success Metrics

- **Reduction in duplicate PRs/issues** - Primary success indicator
- **Human workflow continuity maintained** - Same URLs tracked throughout
- **State persistence reliability** - Consistent state across sync runs
- **Cleanup effectiveness** - Abandoned branches automatically removed
- **User satisfaction** - Reduced notification fatigue and confusion

## References

- [Issue #121: Fix: Prevent duplicate sync PRs and issues](https://github.com/azure/osdu-spi/issues/121)
- [ADR-001: Three-Branch Strategy](001-three-branch-strategy.md)
- [ADR-020: Human-Required Labels](020-human-required-label-strategy.md)
- [ADR-023: Meta Commit Strategy](023-meta-commit-strategy-for-release-please.md)

---

[← ADR-023](023-meta-commit-strategy-for-release-please.md) | :material-arrow-up: [Catalog](index.md) | [ADR-025 →](025-java-maven-build-architecture.md)
