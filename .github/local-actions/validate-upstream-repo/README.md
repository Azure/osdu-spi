# Validate Upstream Repository

Safely validates untrusted user input for upstream repository format. Prevents code injection by handling user comments securely.

## Usage

```yaml
- name: Validate upstream repository
  id: validate
  uses: ./.github/local-actions/validate-upstream-repo
  with:
    comment_body: ${{ github.event.comment.body }}  # Safe - passed as input
    issue_number: ${{ github.event.issue.number }}
    github_token: ${{ secrets.GITHUB_TOKEN }}

- name: Continue if valid
  if: steps.validate.outputs.should_proceed == 'true'
  run: echo "Validated repo: ${{ steps.validate.outputs.upstream_repo }}"
```

## Behavior

- Extracts first line from comment and trims whitespace
- Validates GitHub format: `owner/repo` (alphanumeric, dash, dot, underscore)
- Validates GitLab format: Full URL with protocol
- Posts error comment on issue if validation fails
- Posts confirmation comment if validation succeeds
- Outputs: `upstream_repo` (validated string), `should_proceed` (true/false)

## Security

**Prevents code injection** by:
- Accepting input as action parameter (not string interpolation)
- Reading from environment variable in bash (not `${{ }}` expansion)
- Validating with regex before any further use

**DO NOT** use `${{ github.event.comment.body }}` directly in bash - this allows arbitrary code execution.

## Testing

```bash
cd .github/local-actions/validate-upstream-repo

# Test valid GitHub format
export COMMENT_BODY="owner/repo"
export ISSUE_NUMBER="123"
export GITHUB_TOKEN="test"
./action.sh  # Should output: upstream_repo=owner/repo, should_proceed=true

# Test injection attempt (should be rejected)
export COMMENT_BODY='owner/repo"; rm -rf / #'
./action.sh  # Should output: should_proceed=false
```