# Issue State Manager Action

Updates GitHub issue descriptions with current sync state information.

## Purpose

This action provides a reliable way to update issue descriptions with current sync status. It uses `awk` for field replacement, which handles backticks and special characters better than `sed`.

## Key Features

- **Reliable Updates**: Uses awk for robust text replacement
- **Safe Character Handling**: Handles backticks, special markdown characters
- **Atomic Updates**: Updates all fields in single operation
- **Error Handling**: Validates inputs and GITHUB_TOKEN

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `github_token` | GitHub token for API access | Yes |
| `issue_number` | Issue number to update | Yes |
| `upstream_version` | Upstream commit SHA | Yes |
| `sync_branch` | Sync branch name | Yes |
| `commit_count` | Number of commits in sync | Yes |

## Usage in Workflows

```yaml
- name: Update sync issue state
  uses: ./.github/actions/issue-state-manager
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    issue_number: ${{ steps.issue.outputs.number }}
    upstream_version: ${{ steps.upstream.outputs.sha }}
    sync_branch: ${{ env.SYNC_BRANCH }}
    commit_count: ${{ steps.count.outputs.commits }}
```

## What It Updates

The action updates three fields in the issue description's "Sync Summary" section:

1. **Upstream Version**: `` **Upstream Version**: `<commit-sha>` ``
2. **Changes**: `**Changes**: <count> new commits from upstream`
3. **Branch**: `` **Branch**: `<branch-name>` → `fork_upstream` ``

### Example Issue Body Before:

```markdown
## 🔄 Upstream Sync Ready for Review

### Sync Summary
- **Upstream Version**: `abc1234`
- **Changes**: 5 new commits from upstream
- **Branch**: `sync/upstream-20250128` → `fork_upstream`
```

### After Running Action:

```markdown
## 🔄 Upstream Sync Ready for Review

### Sync Summary
- **Upstream Version**: `def5678`
- **Changes**: 8 new commits from upstream
- **Branch**: `sync/upstream-20250129` → `fork_upstream`
```

## Local Testing

### Prerequisites

```bash
# Install gh CLI if not already installed
# https://cli.github.com/

# Authenticate
gh auth login

# Set environment variable
export GITHUB_TOKEN=$(gh auth token)
```

### Test Script

```bash
cd .github/actions/issue-state-manager

# Test with mock data (replace with actual issue number)
./update-issue-state.sh \
  123 \
  "abc1234567890" \
  "sync/upstream-20250129-120000" \
  10

# Expected output:
# Updating issue #123 with current sync state...
#   - Upstream Version: abc1234567890
#   - Sync Branch: sync/upstream-20250129-120000
#   - Commit Count: 10
# ✅ Successfully updated issue #123 description
```

### Testing with Real Issue

To test with a real issue, create a test issue first:

```bash
# Create test issue
gh issue create \
  --title "Test: Issue State Manager" \
  --body "$(cat <<'EOF'
## Test Issue

### Sync Summary
- **Upstream Version**: `old_sha`
- **Changes**: 0 new commits from upstream
- **Branch**: `old_branch` → `fork_upstream`
EOF
)"

# Note the issue number from output, then test
./update-issue-state.sh <issue-number> "new_sha" "new_branch" 5

# Verify the update
gh issue view <issue-number>

# Clean up
gh issue close <issue-number>
```

## Implementation Details

### Why awk Instead of sed?

The script uses `awk` instead of `sed` for several reasons:

1. **Backtick Handling**: Better at handling backticks in markdown code blocks
2. **Special Characters**: More reliable with special markdown characters
3. **Multiline Safety**: Processes line-by-line without multiline confusion
4. **Predictable Behavior**: Consistent across different platforms

### Temporary File Strategy

The script uses temporary files to ensure atomic updates:

1. Fetch current issue body with `gh issue view`
2. Write to temporary file
3. Process with awk (safe text transformation)
4. Update issue with `gh issue edit --body-file`
5. Clean up temporary files

This approach is more reliable than in-memory string manipulation for large issue bodies.

## Error Handling

The script validates:

- ✅ Required arguments (4 arguments expected)
- ✅ GITHUB_TOKEN environment variable
- ✅ gh CLI command success
- ✅ File operations (mktemp, awk, rm)

Uses `set -euo pipefail` for strict error handling.

## Used By

- `sync.yml` - Upstream synchronization workflow (to be updated)
- Future workflows that manage sync state via issues

## Troubleshooting

### Issue: "Error: GITHUB_TOKEN environment variable is required"

**Solution**: Set GITHUB_TOKEN before running:
```bash
export GITHUB_TOKEN=$(gh auth token)
```

### Issue: "gh: command not found"

**Solution**: Install GitHub CLI:
```bash
# macOS
brew install gh

# Linux
sudo apt install gh  # or yum, dnf, etc.
```

### Issue: awk pattern doesn't match

**Cause**: Issue body format doesn't match expected pattern

**Solution**: Ensure issue body contains exact markdown format:
- `**Upstream Version**: `...``
- `**Changes**: N new commits from upstream`
- `**Branch**: `...` → `fork_upstream``

## Related

- **ADR-022**: Issue Lifecycle Tracking Pattern
- **ADR-028**: Workflow Script Extraction Pattern
- Used in conjunction with sync-state-manager action