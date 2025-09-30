# Sync State Manager Action

Manages upstream sync state to prevent duplicate PRs and issues through intelligent decision-making.

## Purpose

This action implements a state machine for sync operations that:
- Detects existing sync PRs and issues
- Determines if upstream has changed
- Makes intelligent decisions about creating/updating/skipping sync operations
- Cleans up abandoned sync branches automatically

## How It Works

The action orchestrates 6 scripts in sequence:

1. **get-upstream-sha.sh** - Gets current upstream commit SHA
2. **detect-existing-issues.sh** - Finds open sync issues
3. **check-stored-state.sh** - Parses last sync SHA from issue description
4. **detect-existing-prs.sh** - Finds open sync PRs
5. **cleanup-abandoned-branches.sh** - Removes old sync branches without PRs
6. **make-sync-decision.sh** - Applies decision matrix to determine action

## Decision Matrix

| Existing PR | Upstream Changed | Decision |
|-------------|------------------|----------|
| No | Yes | **Create new PR and issue** |
| Yes | No | **Add reminder comment** |
| Yes | Yes | **Update existing branch/PR** |
| No | No | **No action needed** |

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `github_token` | GitHub token for API access | Yes |
| `upstream_repo_url` | Upstream repository URL | Yes |
| `default_branch` | Default branch name (main/master) | Yes |

## Outputs

| Output | Description |
|--------|-------------|
| `should_create_pr` | Whether to create a new PR (true/false) |
| `should_create_issue` | Whether to create a new issue (true/false) |
| `should_update_branch` | Whether to update existing branch (true/false) |
| `existing_pr_number` | Existing PR number if found |
| `existing_issue_number` | Existing issue number if found |
| `existing_branch_name` | Existing sync branch name if found |
| `sync_decision` | Decision reason (create_new, add_reminder, update_existing, no_action) |

## Usage in Workflows

```yaml
- name: Check sync state
  uses: ./.github/actions/sync-state-manager
  id: sync_state
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    upstream_repo_url: ${{ vars.UPSTREAM_REPO_URL }}
    default_branch: main

- name: Create new sync PR
  if: steps.sync_state.outputs.should_create_pr == 'true'
  run: |
    echo "Creating new sync PR..."
    gh pr create --title "Sync upstream changes"

- name: Update existing PR
  if: steps.sync_state.outputs.should_update_branch == 'true'
  run: |
    echo "Updating existing PR #${{ steps.sync_state.outputs.existing_pr_number }}"
    git push origin ${{ steps.sync_state.outputs.existing_branch_name }} --force
```

## Local Testing

### Prerequisites

```bash
# Install gh CLI and authenticate
gh auth login
export GITHUB_TOKEN=$(gh auth token)

# Set up git repository with upstream remote
git remote add upstream https://github.com/upstream/repo.git
git fetch upstream
```

### Test Individual Scripts

#### Test get-upstream-sha.sh

```bash
cd .github/actions/sync-state-manager
./get-upstream-sha.sh "main"

# Expected output:
# Current upstream SHA: abc1234567890
# upstream_sha=abc1234567890
```

#### Test detect-existing-issues.sh

```bash
./detect-existing-issues.sh

# Expected output:
# Detecting existing sync issues...
# Open sync issues found:
# Issue #123: Upstream Sync Ready for Review
# existing_issue_number=123
# has_existing_issue=true
```

#### Test check-stored-state.sh

```bash
./check-stored-state.sh "123"

# Expected output:
# Reading sync state from existing issue description...
# Found existing issue #123, parsing state from description...
# Parsed from issue:
#   Last upstream SHA: def4567890123
#   Issue number: 123
#   Last sync: 2025-01-29T10:00:00Z
```

#### Test detect-existing-prs.sh

```bash
./detect-existing-prs.sh

# Expected output:
# Detecting existing sync PRs...
# Open sync PRs found:
# PR #45: Sync upstream changes (sync/upstream-20250129-100000)
# existing_pr_number=45
# existing_pr_branch=sync/upstream-20250129-100000
# has_existing_pr=true
```

#### Test cleanup-abandoned-branches.sh

```bash
./cleanup-abandoned-branches.sh

# Expected output:
# Cleaning up abandoned sync branches...
# Found sync branches:
# sync/upstream-20250128-120000
#    Checking for associated PR for branch: sync/upstream-20250128-120000
#    ⚠️ Found abandoned branch: sync/upstream-20250128-120000 (age: 86400 seconds)
#    Deleting abandoned branch...
#    ✅ Deleted branch: sync/upstream-20250128-120000
# Cleanup complete
```

#### Test make-sync-decision.sh

```bash
# Scenario 1: No PR, upstream changed -> create new
./make-sync-decision.sh \
  "abc123" \    # current_sha
  "def456" \    # last_sha (different)
  "false" \     # has_pr
  "false" \     # has_issue
  "" \          # pr_number
  "" \          # issue_number
  ""            # pr_branch

# Expected output:
# Decision inputs:
#   Upstream changed: true (abc123 vs def456)
#   Has existing PR: false
#   Has existing issue: false
# 🆕 Decision: Create new PR and issue (upstream changed, no existing PR)
# should_create_pr=true
# should_create_issue=true
# sync_decision=create_new

# Scenario 2: Existing PR, no change -> add reminder
./make-sync-decision.sh \
  "abc123" \    # current_sha
  "abc123" \    # last_sha (same)
  "true" \      # has_pr
  "true" \      # has_issue
  "45" \        # pr_number
  "123" \       # issue_number
  "sync/upstream-20250129-100000"

# Expected output:
# 📝 Decision: Add reminder comment (upstream unchanged, existing PR)
# should_create_pr=false
# should_update_branch=false
# sync_decision=add_reminder

# Scenario 3: Existing PR, upstream changed -> update
./make-sync-decision.sh \
  "abc123" \    # current_sha
  "def456" \    # last_sha (different)
  "true" \      # has_pr
  "true" \      # has_issue
  "45" \        # pr_number
  "123" \       # issue_number
  "sync/upstream-20250129-100000"

# Expected output:
# 🔄 Decision: Update existing branch and PR (upstream changed, existing PR)
# should_create_pr=false
# should_update_branch=true
# sync_decision=update_existing

# Scenario 4: No PR, no change -> no action
./make-sync-decision.sh \
  "abc123" \
  "abc123" \
  "false" \
  "false" \
  "" \
  "" \
  ""

# Expected output:
# ✅ Decision: No action needed (upstream unchanged, no existing PR)
# should_create_pr=false
# sync_decision=no_action
```

## Implementation Details

### Script Organization

```
sync-state-manager/
├── action.yml                      # Orchestrates 6 steps (85 lines)
├── get-upstream-sha.sh             # Simple SHA retrieval (35 lines)
├── detect-existing-issues.sh       # gh issue list queries (50 lines)
├── check-stored-state.sh           # Awk parsing from issue (66 lines)
├── detect-existing-prs.sh          # gh pr list queries (56 lines)
├── cleanup-abandoned-branches.sh   # Complex cleanup logic (78 lines)
├── make-sync-decision.sh           # Decision matrix (132 lines)
└── README.md                       # This file
```

**Total**: 501 lines (vs 270 lines in original monolithic action.yml)
**Reduction**: action.yml went from 270 → 85 lines (**68% reduction**)

### Key Features

**Testability:**
- Each script independently testable
- Decision matrix can be validated with all scenarios
- Cleanup logic testable with mock branches

**Debuggability:**
- Run scripts locally with actual repository state
- No workflow execution required
- Clear output messages for each decision

**Maintainability:**
- Each script has single responsibility
- Decision logic isolated and documented
- Easy to update individual components

### Error Handling

All scripts use `set -euo pipefail` for strict error handling:
- `-e`: Exit on error
- `-u`: Exit on undefined variable
- `-o pipefail`: Exit on pipe failure

### Platform Compatibility

**cleanup-abandoned-branches.sh** handles both GNU and BSD date:
- GNU date (Linux): `date -d "2025-01-29 10:00:00" +%s`
- BSD date (macOS): `date -j -f "%Y%m%d-%H%M%S" "20250129-100000" +%s`

## Used By

- `sync.yml` - Upstream synchronization workflow

## Troubleshooting

### Issue: "Error: Missing required argument"

**Cause**: Script called with wrong number of arguments

**Solution**: Check script documentation for required arguments:
```bash
./get-upstream-sha.sh                    # Wrong: missing branch name
./get-upstream-sha.sh "main"             # Correct
```

### Issue: Cleanup doesn't delete old branches

**Cause**: Branches have associated PRs or are less than 24 hours old

**Solution**: Check branch age and associated PRs:
```bash
# List sync branches
git branch -r | grep sync/upstream-

# Check for PRs on a branch
gh pr list --head "sync/upstream-20250129-100000"
```

### Issue: Decision matrix not matching expected outcome

**Cause**: State inputs don't match assumptions

**Solution**: Test decision matrix locally with actual values:
```bash
# Extract actual values from workflow run
UPSTREAM_SHA=$(git rev-parse upstream/main)
LAST_SHA="..." # from issue description
HAS_PR="..."   # from PR list

./make-sync-decision.sh "$UPSTREAM_SHA" "$LAST_SHA" "$HAS_PR" "false" "" "" ""
```

## Related

- **ADR-024**: Sync Workflow Duplicate Prevention Architecture
- **ADR-028**: Workflow Script Extraction Pattern