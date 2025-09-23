# PR Status Comment Action

A composite action that standardizes how status comments are added to pull requests across our workflows.

## Features

- Consistent formatting of status comments
- Flexible status items via JSON array input
- Uses GitHub CLI for comment creation
- Maintains comment history for audit trail

## Usage

```yaml
- uses: ./.github/actions/pr-status
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    pr_number: ${{ github.event.pull_request.number }}
    status_items: '["✅ Tests Passed", "⚠️ Coverage Decreased"]'
```

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `token` | GitHub token for authentication | Yes | - |
| `pr_number` | Pull request number | Yes | - |
| `status_items` | JSON array of status items to display | Yes | - |

## Output Format

Comments are formatted as:
```markdown
## Validation Status
- First status item
- Second status item
- etc...
```

## Examples

### Basic Usage
```yaml
- uses: ./.github/actions/pr-status
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    pr_number: ${{ github.event.pull_request.number }}
    status_items: '["✅ All checks passed"]'
```

### Dynamic Status Items
```yaml
- name: Prepare Status Items
  id: status
  run: |
    ITEMS=[]
    ITEMS=$(echo $ITEMS | jq '. + ["✓ No Conflict Markers"]')
    if [[ "${{ needs.tests.result }}" == "success" ]]; then
      ITEMS=$(echo $ITEMS | jq '. + ["✅ Tests Passed"]')
    else
      ITEMS=$(echo $ITEMS | jq '. + ["❌ Tests Failed"]')
    fi
    echo "items=$ITEMS" >> $GITHUB_OUTPUT

- uses: ./.github/actions/pr-status
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    pr_number: ${{ github.event.pull_request.number }}
    status_items: ${{ steps.status.outputs.items }}
```

## Requirements

- GitHub CLI (`gh`) must be available in the runner
- Requires `write` permission for pull-requests
- JSON-formatted status items array

## Error Handling

The action will fail if:
- Invalid JSON in status_items
- Missing required inputs
- GitHub token lacks necessary permissions
- PR number is invalid

## Contributing

When modifying this action:
1. Update documentation for any changes
2. Test with various input formats
3. Consider backward compatibility
4. Update examples if behavior changes 