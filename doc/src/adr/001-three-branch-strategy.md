# ADR-001: Three-Branch Fork Management Strategy

## Status
**Accepted** - 2025-10-01

## Context
When maintaining a long-lived fork of an upstream repository, teams need to balance staying current with upstream changes while preserving their own modifications. Traditional forking approaches often lead to complex merge conflicts, difficulty tracking upstream changes, and challenges in maintaining a stable release branch.

The system needs to support:
- Regular synchronization with upstream repositories
- Isolation of local modifications from upstream changes
- Safe conflict resolution workflow
- Stable release management
- Clear separation of concerns between different types of changes

## Decision
Implement a three-branch strategy for fork management:

1. **`main`** - Stable production branch containing successfully integrated changes
2. **`fork_upstream`** - Tracks the upstream repository's main branch exactly
3. **`fork_integration`** - Validation workspace for conflict resolution and comprehensive testing of upstream changes

## Rationale

### Branch Purposes
- **`main`**: Protected branch that only receives changes through PRs, ensuring stability
- **`fork_upstream`**: Clean tracking of upstream without local modifications, enabling clear diff analysis
- **`fork_integration`**: Dedicated space for conflict resolution and comprehensive validation (build, test, lint) without affecting stable branches

### Workflow Benefits
1. **Clear Change Attribution**: Easy to identify what comes from upstream vs local modifications
2. **Conflict Isolation**: Merge conflicts are resolved in a dedicated branch before affecting main
3. **Quality Validation**: Comprehensive build, test, and lint validation in integration branch
4. **Upstream Tracking**: Pure upstream branch enables accurate diff analysis and change detection
5. **Safe Integration**: Multiple review and validation points before changes reach the stable main branch
6. **Early Issue Detection**: Integration validation catches problems before they reach production PRs
7. **Rollback Capability**: Easy to revert problematic integrations without losing upstream sync

## Alternatives Considered

### 1. Two-Branch Strategy (fork + main)
- **Pros**: Simpler branch structure
- **Cons**: Conflicts would occur directly on main branch, no dedicated conflict resolution space
- **Decision**: Rejected due to safety concerns

### 2. Feature Branch per Upstream Sync
- **Pros**: Each sync is isolated
- **Cons**: Branch proliferation, complex tracking of multiple upstream syncs
- **Decision**: Rejected due to complexity

### 3. Direct Upstream Merge to Main
- **Pros**: Simplest possible approach
- **Cons**: No conflict isolation, high risk of breaking main branch
- **Decision**: Rejected due to lack of safety controls

## Consequences

### Positive
- **Stability**: Main branch remains stable through protected PR workflow
- **Clarity**: Clear separation between upstream changes and local modifications
- **Safety**: Multiple integration points prevent problematic changes from reaching production
- **Traceability**: Easy to track source of changes and resolve conflicts systematically
- **Flexibility**: Can handle complex upstream changes without disrupting ongoing development

### Negative
- **Complexity**: Three branches require more management overhead
- **Learning Curve**: Team needs to understand the branch strategy and workflows
- **Automation Dependency**: Requires automated workflows to manage branch synchronization effectively

## Implementation Details

### Branch Protection Rules
- `main`: Require PR reviews, status checks, and up-to-date branches
- `fork_upstream`: Allow direct pushes from automation only
- `fork_integration`: Allow direct pushes for conflict resolution

### Branch Preservation Strategy
**Critical Requirement**: All three branches must be permanently preserved and never deleted.

- **`main`**: Production branch - never delete
- **`fork_upstream`**: Upstream tracking branch - never delete (needed for future syncs)
- **`fork_integration`**: Conflict resolution branch - never delete (needed for future integrations)

**Implementation**: When creating production PRs, use temporary release branches (e.g., `release/upstream-YYYYMMDD-HHMMSS`) from `fork_integration` to `main`. This allows safe deletion of release branches while preserving the core three-branch structure.

### Integration Branch Synchronization
**Problem**: After a production PR merges to `main`, `fork_integration` contains the old commit history that was integrated via the release branch. This causes the cascade workflow to incorrectly detect an "integration in progress" because `fork_integration` appears to be ahead of `main`.

**Solution**: The `integration-cleanup.yml` workflow automatically synchronizes `fork_integration` with `main` after any upstream-sync PR is merged to `main`. This:
- Prevents false "integration in progress" detections
- Clears the pipeline for processing new upstream changes
- Automatically closes any "upstream-held" issues
- Maintains the three-branch strategy integrity

**Trigger**: Runs automatically on PR merge to `main` when PR has `upstream-sync` label

### Workflow Integration
1. **Upstream Sync**: `fork_upstream` tracks upstream automatically
2. **Change Detection**: Compare `fork_upstream` with `main` to identify new upstream changes
3. **Integration Cascade**: Merge `fork_upstream` to `fork_integration` with comprehensive validation
4. **Validation Gate**: Run build, test, and lint checks on `fork_integration` branch
5. **Quality Assurance**: Block progression if validation fails, create detailed failure issues
6. **Production Release**: Create PR from validated `fork_integration` to `main` only after successful validation
7. **Manual Review**: All production PRs require human approval before final merge
8. **Integration Sync**: After PR merge to `main`, automatically synchronize `fork_integration` with `main` to clear pipeline state

### Automation Requirements
- Scheduled upstream synchronization to `fork_upstream`
- Automated conflict detection and PR creation
- Comprehensive integration validation (build, test, lint)
- Validation failure detection and issue creation
- Branch protection enforcement
- Status checks and validation workflows
- Issue lifecycle tracking and status reporting
- Automatic `fork_integration` synchronization after main merges (integration-cleanup workflow)

## Success Criteria
- Teams can safely integrate upstream changes without breaking main branch
- Conflicts are resolved in isolated environment before affecting production
- Integration validation catches build/test issues before production PRs
- Validation failures are tracked and resolved systematically
- Clear audit trail of all changes, validation results, and their sources
- Reduced time to resolve upstream integration issues
- Maintained stability of main branch throughout integration process
- Quality gate ensures only validated, tested changes reach production

---

:material-arrow-up: [Catalog](index.md) | [ADR-002 →](002-github-actions-automation.md)