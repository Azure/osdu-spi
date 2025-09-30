# Merge with Theirs Resolution

Merges branches with automatic conflict resolution using theirs strategy (prefers source branch version).

## Usage

```yaml
- name: Merge to Main
  uses: ./.github/local-actions/merge-with-theirs-resolution
  with:
    source_branch: fork_integration
    target_branch: main
    commit_message: "chore: complete repository initialization"
    issue_number: ${{ github.event.issue.number }}  # optional
    github_token: ${{ secrets.GITHUB_TOKEN }}       # optional
```

## Behavior

- Checks out target branch
- Attempts merge with `--allow-unrelated-histories --no-ff -X theirs`
- If conflicts remain, uses `git status --porcelain` to detect conflict markers
- Resolves conflicts by taking source branch version (`git checkout --theirs`)
- Posts comment to issue if conflicts detected (when issue_number provided)
- Outputs: `merge_successful` (true/false), `conflicts_resolved` (count)

## Conflict Status Codes

Detects and resolves these git status codes:
- `DD` - Deleted by both
- `AU` - Added by us
- `UD` - Deleted by them
- `UA` - Added by them
- `DU` - Deleted by us
- `AA` - Added by both
- `UU` - Modified by both

## Testing

```bash
cd .github/local-actions/merge-with-theirs-resolution
git init test-repo && cd test-repo
git checkout -b main
echo "main content" > file.txt
git add . && git commit -m "main"
git checkout -b fork_integration
echo "integration content" > file.txt
git add . && git commit -m "integration"
export SOURCE_BRANCH="fork_integration"
export TARGET_BRANCH="main"
export COMMIT_MESSAGE="test merge"
../action.sh  # Should output: merge_successful=true
```