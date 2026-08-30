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

- **State-based duplicate detection** using active tracking issue metadata
- **Smart decision matrix** for handling all duplicate scenarios
- **Fail-closed branch cleanup** when PR state cannot be read reliably
- **Clean separation of concerns** via dedicated GitHub Action

### 2. State Persistence Pattern

**Options Considered:**

- Git notes (rejected - complexity and merge conflicts)
- Git config (rejected - GitHub-hosted runners do not preserve local config between runs)
- External storage (rejected - dependency and complexity)
- **Tracking issue metadata (chosen for the active cycle)** - durable through GitHub APIs and aligned with the sync lifecycle
- **Repository variable (chosen for what outlives the cycle)** - the only state that survives with no open issue or PR

**Implementation:**

- Store the full upstream SHA in a hidden `<!-- upstream-sha: ... -->` marker
- Keep the human-facing **Upstream Version** as a tag or short SHA
- Discover active PRs, issues, and branches by label on every run
- Treat legacy issues without a marker as changed, then backfill the marker on update
- Record `<sha>:<generation-rev>` in `SYNC_LAST_EVALUATED_SHA` when filtering yields no fork-visible change and no sync PR is open

Repository variables were originally rejected here as requiring additional
tokens. The GitHub App authentication of ADR-029 removed that cost, and the
same App already writes `UPSTREAM_REPO_URL` and `SYNC_MODE` during
initialization and adoption.

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
| Yes         | No               | Keep existing artifacts unchanged |
| Yes         | Yes              | Update existing branch    |
| No          | No               | No action needed          |
```

The historical `add_reminder` decision value is retained for compatibility,
but it produces only workflow logging. It does not mutate the PR or issue.

### State Management

**Storage:** Two tiers, read in that order.

*Active cycle* - GitHub issue and pull request metadata:

- `<!-- upstream-sha: <40-character SHA> -->`: Last upstream source commit represented by the active tracking issue
- `upstream-sync` label: Identifies the active tracking issue and sync PR
- PR head branch: Identifies the reusable sync branch
- Issue `updatedAt`: Records the latest issue mutation

*Between cycles* - repository variable:

- `SYNC_LAST_EVALUATED_SHA`: `<upstream sha>:<generation revision>` for the last upstream commit whose generated tree matched `fork_upstream` exactly

An open tracking issue always wins. Reading the variable while a cycle is
active would report an advanced upstream as already handled and leave the open
sync PR stranded at an older tree.

The variable is written only when all three hold:

- the generated tree matched `fork_upstream`, so the run is already complete
- no sync PR is open, because an open PR carries a tree the comparison never
  saw; an upstream commit that reverts it generates a no-op while the stale
  branch is still queued for merge
- the SHA is a full 40-character lowercase hash

Recording alongside a generated branch would instead let a later failure in PR
creation leave state claiming the SHA was handled with nothing to show for it,
and the next run would take no action.

The generation revision is what makes the cached result safe to reuse. The
cached fact is `filter(upstream_sha) == tree(fork_upstream)`, so the key has to
cover every input to that comparison. `generation-rev.sh` hashes
`.github/upstream-filter.yml`, the filter engine, and `generate-branch.sh` —
which decides how the tree is extracted, serialized, and compared — and
short-circuits to the sentinel `mirror` when `SYNC_MODE` selects the customer
tier. Without this, editing a filter rule after a no-op was recorded would
leave `fork_upstream` unable to receive the new tree until upstream happened to
advance.

The `fork_upstream` tip is deliberately *not* part of the key. Only a sync PR
merge advances it, and a sync PR can only exist once upstream has moved past the
stored SHA, so the merge always arrives with an upstream commit that already
invalidates the cache. The residual case is a manual force-push to
`fork_upstream`, whose recovery is deleting one repository variable — cheaper
than resolving the branch on every state read.

**Persistence:** The marker lasts as long as the tracking issue; the variable persists indefinitely

**Cleanup:** Issue and PR state clears when they close or merge; the variable is overwritten in place

### Integration Points

**Pre-Sync Validation Step:** Uses sync-state-manager action after "Configure Git"

**Conditional Sync Step:** Modified to handle branch updates vs new creation

**Smart PR Management:** Skip/update/create based on action outputs

**Intelligent Issue Management:** Skip/update/create based on action outputs

## Implementation Benefits

### Technical Benefits

- **Eliminates duplicate PRs/issues** throughout an active sync cycle
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
- **State persistence** stores the full SHA in the active tracking issue, and in `SYNC_LAST_EVALUATED_SHA` once neither an issue nor a PR is open
- **Unchanged path** leaves the existing PR and issue untouched while retaining the historical `add_reminder` output value
- **Cleanup logic** removes abandoned sync branches

### Error Handling

- **GitHub API Failures:** State reads fail the workflow rather than guessing
- **Cleanup Lookup Failures:** Skip destructive branch deletion when PR state or JSON cannot be read
- **State Corruption:** Missing or malformed markers and variable values compare as changed and are repaired on the next write
- **Durable State Writes:** A failed variable write costs one repeated evaluation, never a failed sync run
- **Durable State Reads:** Only an absent variable degrades to empty; an authentication, rate-limit, or transient failure fails the run rather than reading as first sync
- **Backwards Compatibility:** Legacy issue bodies require no migration step

## Consequences

### Positive

- ✅ **Eliminates duplicate PRs/issues during active sync cycles** - Core problem solved
- ✅ **Maintains clean repository state** - Automatic cleanup
- ✅ **Preserves human workflow continuity** - Same URLs to track
- ✅ **Better maintainability** - Action pattern follows best practices
- ✅ **Reusable by other workflows** - State management available elsewhere
- ✅ **Fail-closed cleanup** - Uncertain PR state cannot trigger branch deletion
- ✅ **No repeated no-op work** - An upstream commit that only touches filtered paths is evaluated once

### Negative

- ⚠️ **State lives in two places** - The issue marker and the repository variable must agree on precedence
- ⚠️ **The durable cache key spans several files** - Filter config, engine, and sync mode all invalidate it
- ⚠️ **Added complexity** in sync workflow - More decision logic
- ⚠️ **Potential edge cases** in decision logic - Requires thorough testing

### Neutral

- 📝 **No breaking changes** - Existing forks continue working
- 📝 **Automatic distribution** - sync-config.json handles deployment
- 📝 **No external dependencies** - Uses existing GitHub tokens and permissions

## Testing Strategy

The template CI runs `.github/local-actions/sync-state-manager-tests/run-tests.sh` to validate:

- Failed and malformed PR lookups never delete branches
- Successful empty lookups still delete abandoned branches
- Active PR branches are retained
- Legacy, current, and CRLF issue bodies round-trip the canonical SHA marker
- Empty SHA values cannot overwrite stored state
- Equal full SHAs select the reminder path
- Malformed SHAs never reach the durable variable
- A no-change evaluation records the evaluated SHA, and an unwritable variable does not fail the run
- A run with no tracking issue reads the variable, and unusable values compare as changed
- An open tracking issue outranks the variable
- A stale generation revision invalidates the cache, and the revision tracks config, engine, and sync mode
- An unreadable variable fails the run instead of reading as first sync
- Durable state is not recorded while a sync PR is open
- A re-evaluated no-op SHA reaches `no_action` before branch generation
- Workflow ordering keeps state exports before the filtered no-change exit

Production monitoring remains responsible for validating end-to-end PR, issue, and cascade behavior.

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
- [Issue #127: Fail closed when cleanup cannot read PR state](https://github.com/Azure/osdu-spi/issues/127)
- [Issue #128: Persist the full upstream SHA](https://github.com/Azure/osdu-spi/issues/128)
- [Issue #147: Persist filtered no-op sync state](https://github.com/Azure/osdu-spi/issues/147)
- [ADR-001: Three-Branch Strategy](001-three-branch-strategy.md)
- [ADR-020: Human-Required Labels](020-human-required-label-strategy.md)
- [ADR-023: Meta Commit Strategy](023-meta-commit-strategy-for-release-please.md)

---

[← ADR-023](023-meta-commit-strategy-for-release-please.md) | :material-arrow-up: [Catalog](index.md) | [ADR-025 →](025-java-maven-build-architecture.md)
