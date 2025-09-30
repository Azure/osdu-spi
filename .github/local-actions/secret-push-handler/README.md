# Secret Push Handler

Detects secret scanning violations in git push output and creates escalation issues with secret allowlist URLs.

## Usage

```yaml
- name: Push with error capture
  run: |
    set +e
    git push origin branch 2>&1 | tee push_output.txt
    echo "PUSH_EXIT_CODE=${PIPESTATUS[0]}" >> $GITHUB_ENV
    set -e

- name: Handle secret push violation
  if: env.PUSH_EXIT_CODE != '0'
  uses: ./.github/local-actions/secret-push-handler
  with:
    push_output_file: push_output.txt
    issue_number: ${{ github.event.issue.number }}
    upstream_repo: ${{ needs.validate.outputs.upstream_repo }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

## Behavior

- Searches for `GH013: Repository rule violations found` pattern
- Extracts secret allowlist URLs (handles ANSI escape codes)
- Extracts blob IDs from git output
- Creates escalation issue with 3 resolution options
- Comments on original issue with link to escalation
- Outputs: `push_protected` (true/false), `escalation_issue_url`

## Testing

```bash
cd .github/local-actions/secret-push-handler
cat > test_output.txt <<'EOF'
remote: error: GH013: Repository rule violations found
remote: https://github.com/owner/repo/secret-scanning/unblock-secret/AbC123
EOF
export PUSH_OUTPUT_FILE="test_output.txt"
export ISSUE_NUMBER="123"
export GITHUB_TOKEN="test"
./action.sh  # Should output: push_protected=true
```