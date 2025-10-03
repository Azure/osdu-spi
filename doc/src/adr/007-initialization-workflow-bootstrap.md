# ADR-007: Initialization Workflow Bootstrap Pattern

## Status
**Accepted** - 2025-10-01

## Context
During testing with OSDU repositories, we discovered a critical bootstrap problem in the template initialization process:

**The Bootstrap Problem:**
When a new repository is created from this template, it runs the initialization workflow from the template's initial commit, not the current/updated version. This means any fixes or improvements to the initialization workflow (like adding `--allow-unrelated-histories` to handle merge conflicts) are not available during the actual initialization.

**Discovery Timeline:**
1. User creates repository from template
2. Initialization workflow runs from commit `b40474835cd53d4e78bf20108e18ac6178af6842`
3. Workflow fails at: `git merge fork_integration --no-ff -m "chore: complete repository initialization"`
4. Error: `fatal: refusing to merge unrelated histories`
5. Current template already has the fix: `--allow-unrelated-histories` flag
6. But the fix isn't available to the running workflow

**Additional Discovery:**
Even with `--allow-unrelated-histories`, merge conflicts occur in common files:
- `.gitignore` - Template version vs upstream version
- `README.md` - Template documentation vs upstream documentation
- Solution requires `-X theirs` merge strategy to automatically resolve conflicts

**Permission Discovery:**
The built-in GITHUB_TOKEN lacks permissions to create repository secrets:
- Error: `HTTP 403: Resource not accessible by integration`
- Solution: Use Personal Access Token (PAT) stored as `GH_TOKEN` secret
- Fallback: Skip secret creation with warning if PAT not available

**Root Cause:**
GitHub Actions runs workflows from the commit that triggered the event. For template-created repositories, this is the initial commit containing the old workflow version, creating a chicken-and-egg problem.

## Decision
Implement a self-updating initialization workflow pattern:

1. **Phase 1: Bootstrap Update** - The initialization workflow first updates itself from the template repository
2. **Phase 2: Execute Initialization** - Run the updated workflow logic

This ensures that any fixes or improvements to the initialization process are immediately available to new repositories.

## Rationale

### Why This Matters
1. **Fix Propagation**: Critical fixes reach new repositories immediately
   - `--allow-unrelated-histories` for unrelated history errors
   - `-X theirs` for automatic merge conflict resolution
2. **Continuous Improvement**: Template improvements benefit all future users
3. **Reduced Support**: Users don't encounter already-fixed issues
4. **Maintainability**: Single source of truth for initialization logic

### Alternative Approaches Considered

#### 1. Document Manual Workarounds
- **Approach**: Tell users to manually run missing commands when initialization fails
- **Pros**: Simple, no code changes needed
- **Cons**: Poor user experience, requires technical knowledge, defeats automation purpose
- **Decision**: Rejected - Goes against the template's goal of automation

#### 2. Pre-create All Branches in Template
- **Approach**: Include fork_upstream and fork_integration branches in template
- **Pros**: Might avoid unrelated histories issue
- **Cons**: Pollutes template with upstream-specific content, still doesn't solve workflow updates
- **Decision**: Rejected - Doesn't address root cause

#### 3. External Initialization Script
- **Approach**: Use a separate script hosted externally that gets downloaded and run
- **Pros**: Always runs latest version
- **Cons**: External dependency, security concerns, complexity
- **Decision**: Rejected - Adds unnecessary external dependencies

#### 4. Two-Stage Workflow with Self-Update
- **Approach**: Workflow updates itself before running initialization
- **Pros**: Self-contained, automatic, always uses latest fixes
- **Cons**: Slightly more complex workflow logic
- **Decision**: **Accepted** - Best balance of automation and reliability

## Implementation Details

### Proposed Workflow Structure
```yaml
name: Initialize Fork

on:
  issue_comment:
    types: [created]

jobs:
  update-workflow:
    name: Update initialization workflow
    runs-on: ubuntu-latest
    steps:
      - name: Checkout current repository
        uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Fetch latest workflow from template
        run: |
          # Add template as remote
          git remote add template https://github.com/azure/osdu-spi.git
          git fetch template main
          
          # Update workflows to latest version
          git checkout template/main -- .github/workflows/init.yml
          git checkout template/main -- .github/workflows/init-complete.yml
          
          # Commit if changes exist
          if git diff --staged --quiet; then
            echo "Workflows are already up to date"
          else
            git config user.name "github-actions[bot]"
            git config user.email "github-actions[bot]@users.noreply.github.com"
            git commit -m "chore: update initialization workflows to latest version"
            git push
          fi
          
  initialize:
    name: Initialize repository
    needs: update-workflow
    uses: ./.github/workflows/init-complete.yml
    # Now runs with updated workflow
```

### Key Design Elements

1. **Self-Updating**: Workflow fetches its own latest version before executing
2. **Idempotent**: Safe to run multiple times, only updates if changes exist  
3. **Transparent**: Users see workflow update commit in history
4. **Secure**: Uses same permissions, no external dependencies

## Consequences

### Positive
- **Automatic Fix Distribution**: All template improvements immediately available
- **Reduced User Friction**: Initialization "just works" with latest fixes
- **Simplified Support**: No need to maintain fix instructions for old versions
- **Better User Experience**: Users always get the best version of initialization
- **Traceable Updates**: Git history shows when workflows were updated

### Negative
- **Additional Complexity**: Two-phase initialization adds complexity
- **Extra Commit**: Creates an additional commit in repository history
- **Potential Conflicts**: If user modifies workflows before initialization completes
- **Dependency on Template**: Requires template repository to remain accessible

### Mitigation Strategies
1. **Clear Documentation**: Explain the self-update process in initialization issue
2. **Error Handling**: Graceful fallback if template fetch fails
3. **Version Checking**: Only update if template version is newer
4. **Conflict Prevention**: Check for local modifications before updating

## Success Criteria
- ✅ New repositories always use latest initialization workflow
- ✅ Critical fixes are immediately available:
  - `--allow-unrelated-histories` for unrelated history errors
  - `-X theirs` for automatic merge conflict resolution
  - PAT token usage for secret creation operations
  - Template file cleanup and repository-specific README generation
- ✅ Users don't encounter previously-fixed initialization issues
- ✅ Workflow updates are transparent in git history
- ✅ Process handles edge cases gracefully (template unavailable, etc.)
- ✅ Template documentation is cleaned up after initialization

## Actual Implementation

The bootstrap problem was solved using **Local Actions Pattern** instead of the workflow self-update approach described above:

### Solution: Extracted Local Actions

Critical initialization logic was extracted to `.github/local-actions/merge-with-theirs-resolution/`:

```bash
# .github/local-actions/merge-with-theirs-resolution/action.sh
git merge "$SOURCE_BRANCH" --allow-unrelated-histories --no-ff -X theirs -m "$COMMIT_MESSAGE"
```

### Why This Works

1. **Always Available**: Local actions are part of the template repository and copied during initialization
2. **No Bootstrap Problem**: Since the action exists in the initial commit, fixes are automatically available
3. **Cleaner Architecture**: Reusable action provides better separation than embedded workflow code
4. **No External Dependencies**: Self-contained within the repository

### Usage in init-complete.yml

```yaml
- name: Complete initialization
  uses: ./.github/local-actions/merge-with-theirs-resolution
  with:
    source_branch: fork_integration
    target_branch: main
    commit_message: "chore: complete repository initialization"
```

### Benefits Over Self-Update Approach

- ✅ **Simpler**: No two-phase initialization complexity
- ✅ **Reliable**: No dependency on template repository accessibility
- ✅ **Clean History**: No bootstrap commits
- ✅ **Testable**: Local actions can be tested independently
- ✅ **Maintainable**: Single source of truth in `.github/local-actions/`

## Related Decisions
- **ADR-028**: Workflow Script Extraction Pattern - Documents the local actions pattern used
- **ADR-012**: Template Update Propagation Strategy - How template improvements reach existing forks
- **ADR-006**: Two-Workflow Initialization Pattern - This ADR builds upon the two-workflow pattern
- **ADR-003**: Template Repository Pattern - Aligns with template-based architecture
---

[← ADR-006](006-two-workflow-initialization.md) | :material-arrow-up: [Catalog](index.md) | [ADR-008 →](008-centralized-label-management.md)
