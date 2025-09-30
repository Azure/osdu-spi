# Configure Git

Configures git user identity as github-actions[bot] for automated commits.

## Usage

```yaml
- name: Configure Git
  uses: ./.github/local-actions/configure-git
  with:
    pull_rebase: 'false'  # optional
```

## Behavior

- Always sets `user.name` and `user.email` to github-actions[bot]
- Optionally sets `pull.rebase` if specified

## Testing

```bash
cd .github/local-actions/configure-git
git init test-repo && cd test-repo
export PULL_REBASE="false"
../action.sh
git config user.name  # Should output: github-actions[bot]
```