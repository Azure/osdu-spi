# Initialization Helpers

Suite of scripts for one-time repository initialization during fork setup.

## Usage

```yaml
- name: [Operation Name]
  uses: ./.github/local-actions/init-helpers
  with:
    operation: [operation-name]
    github_token: ${{ secrets.GITHUB_TOKEN }}
    # ... operation-specific inputs
```

## Operations

**setup-upstream** - Adds upstream remote and detects default branch
- Tries: main → master → symbolic HEAD → common alternatives
- Outputs: `DEFAULT_BRANCH`, `REPO_URL` environment variables

**setup-branch-protection** - Configures branch protection rules
- `main`: Requires PR reviews
- `fork_upstream`: Basic protection (automation allowed)
- `fork_integration`: Unprotected (allows cascade direct push)
- Requires `GH_TOKEN` with admin permissions

**setup-security** - Enables repository security features
- Secret scanning, dependency alerts, Dependabot
- Requires `GH_TOKEN` with admin permissions

**deploy-fork-resources** - Deploys fork-specific templates
- Copies `.github/fork-resources/*` to final locations
- Removes fork-resources directory after deployment

## Testing

```bash
cd .github/local-actions/init-helpers

# Test setup-upstream
export GITHUB_TOKEN="test"
export UPSTREAM_REPO="owner/repo"
export ISSUE_NUMBER="123"
./setup-upstream.sh  # Verify DEFAULT_BRANCH output

# Test setup-branch-protection
export GH_TOKEN="test"
export REPO_FULL_NAME="owner/repo"
./setup-branch-protection.sh

# Test setup-security
export GH_TOKEN="test"
export REPO_FULL_NAME="owner/repo"
./setup-security.sh

# Test deploy-fork-resources
# (Requires actual .github/fork-resources/ directory structure)
./deploy-fork-resources.sh
```