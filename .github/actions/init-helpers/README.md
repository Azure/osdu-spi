# Initialization Helpers Action

Repository initialization utility scripts for setting up fork management infrastructure.

## Purpose

This action provides a suite of initialization scripts that configure repository settings during the one-time initialization process. Each operation is independent and can be called separately.

## Operations

### 1. setup-upstream

Adds upstream remote and detects the default branch.

**Detects branches in order:**
1. `main`
2. `master`
3. Symbolic reference from HEAD
4. Common alternatives (develop, production, etc.)

**Usage:**
```yaml
- uses: ./.github/actions/init-helpers
  with:
    operation: setup-upstream
    github_token: ${{ secrets.GITHUB_TOKEN }}
    upstream_repo: ${{ inputs.upstream_repo }}
    issue_number: ${{ github.event.issue.number }}
```

**Outputs:**
- Sets `DEFAULT_BRANCH` environment variable
- Sets `REPO_URL` environment variable

### 2. setup-branch-protection

Configures branch protection rules for fork management branches.

**Protection rules:**
- `main`: Requires PR reviews (production)
- `fork_upstream`: Basic protection (automation allowed)
- `fork_integration`: Unprotected (cascade workflow needs direct push)

**Usage:**
```yaml
- uses: ./.github/actions/init-helpers
  with:
    operation: setup-branch-protection
    github_token: ${{ secrets.GH_TOKEN }}
    repo_full_name: ${{ github.repository }}
    issue_number: ${{ github.event.issue.number }}
```

**Outputs:**
- Sets `BRANCH_PROTECTION_SUCCESS` environment variable

### 3. setup-security

Enables security features and GitHub Copilot automatic code review.

**Features enabled:**
- Secret scanning
- Dependency alerts
- GitHub Copilot code review ruleset

**Usage:**
```yaml
- uses: ./.github/actions/init-helpers
  with:
    operation: setup-security
    github_token: ${{ secrets.GH_TOKEN }}
    repo_full_name: ${{ github.repository }}
    issue_number: ${{ github.event.issue.number }}
```

**Outputs:**
- Sets `SECURITY_SUCCESS` environment variable

### 4. deploy-fork-resources

Deploys fork-specific resources and cleans up template files.

**Resources deployed:**
- Copilot instructions
- Dependabot configuration
- Copilot firewall config
- Triage prompts
- VS Code MCP config
- Issue templates
- Copilot setup workflow

**Cleanup performed:**
- `fork-resources/` directory
- `dev-*` workflows
- `template-workflows/` directory
- Template files per sync-config.json

**Usage:**
```yaml
- uses: ./.github/actions/init-helpers
  with:
    operation: deploy-fork-resources
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

## Full Example

```yaml
- name: Setup upstream repository
  uses: ./.github/actions/init-helpers
  with:
    operation: setup-upstream
    github_token: ${{ secrets.GITHUB_TOKEN }}
    upstream_repo: "azure/osdu-infrastructure"
    issue_number: ${{ github.event.issue.number }}

- name: Setup branch protection
  uses: ./.github/actions/init-helpers
  with:
    operation: setup-branch-protection
    github_token: ${{ secrets.GH_TOKEN }}
    repo_full_name: ${{ github.repository }}
    issue_number: ${{ github.event.issue.number }}

- name: Setup security features
  uses: ./.github/actions/init-helpers
  with:
    operation: setup-security
    github_token: ${{ secrets.GH_TOKEN }}
    repo_full_name: ${{ github.repository }}
    issue_number: ${{ github.event.issue.number }}

- name: Deploy fork resources
  uses: ./.github/actions/init-helpers
  with:
    operation: deploy-fork-resources
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

## Local Testing

### Prerequisites

```bash
# Install gh CLI
brew install gh  # or apt install gh

# Authenticate
gh auth login
export GITHUB_TOKEN=$(gh auth token)

# For PAT operations
export GH_TOKEN="ghp_your_pat_token"
```

### Test setup-upstream

```bash
cd .github/actions/init-helpers

# Test with GitHub repo
./setup-upstream.sh "azure/osdu-infrastructure" ""

# Expected output:
# Setting up upstream repository: azure/osdu-infrastructure
# Repository URL: https://github.com/azure/osdu-infrastructure.git
# Available branches: main develop feature-x
# ✅ Detected default branch: main
# Upstream repository setup complete
```

### Test setup-branch-protection

```bash
cd .github/actions/init-helpers

# Test with your repository (requires GH_TOKEN with admin access)
export GH_TOKEN="ghp_your_pat"
./setup-branch-protection.sh "owner/repo" ""

# Expected output:
# Setting up branch protection for owner/repo...
# Protecting main branch...
# ✅ Protected main branch with PR requirements
# Protecting fork_upstream branch...
# ✅ Protected fork_upstream branch (automation pushes allowed)
# ✅ fork_integration branch left unprotected
# Branch protection setup complete: true
```

### Test setup-security

```bash
cd .github/actions/init-helpers

# Test with your repository (requires GH_TOKEN with admin access)
export GH_TOKEN="ghp_your_pat"
./setup-security.sh "owner/repo" ""

# Expected output:
# Setting up security features for owner/repo...
# Enabling security features from security-on.json...
# ✅ Security features enabled
# 🤖 Creating GitHub Copilot automatic code review ruleset...
# Created basic ruleset with ID: 12345
# ✅ GitHub Copilot automatic code review enabled
# Security setup complete: true
```

### Test deploy-fork-resources

```bash
cd .github/actions/init-helpers

# Note: This must be run from repository root with fork-resources present
cd /path/to/repo
./.github/actions/init-helpers/deploy-fork-resources.sh

# Expected output:
# Deploying fork-specific resources...
# Installing fork-specific copilot instructions...
# Installing fork-specific Dependabot configuration...
# ... (various installation messages)
# Removing fork-resources directory after copying...
# Cleaning up template development workflows...
# ✅ Fork resources deployed and template files cleaned up
```

## Implementation Details

### Script Organization

Each operation is implemented as a separate bash script:

```
init-helpers/
├── action.yml                      # Composite action router
├── setup-upstream.sh               # Upstream repository setup
├── setup-branch-protection.sh      # Branch protection rules
├── setup-security.sh               # Security features enablement
├── deploy-fork-resources.sh        # Resource deployment & cleanup
└── README.md                       # This file
```

### Error Handling

All scripts use `set -euo pipefail` for strict error handling:
- `-e`: Exit on error
- `-u`: Exit on undefined variable
- `-o pipefail`: Exit on pipe failure

### Token Requirements

- `GITHUB_TOKEN`: Sufficient for most read operations and issue comments
- `GH_TOKEN`: Required for branch protection, security config (needs admin access)

### Environment Variable Outputs

Scripts set environment variables for workflow use:

| Script | Variable | Description |
|--------|----------|-------------|
| setup-upstream | `DEFAULT_BRANCH` | Detected default branch name |
| setup-upstream | `REPO_URL` | Full upstream repository URL |
| setup-branch-protection | `BRANCH_PROTECTION_SUCCESS` | Success status (true/false) |
| setup-security | `SECURITY_SUCCESS` | Success status (true/false) |

## Used By

- `init-complete.yml` - Repository initialization workflow

## Related

- **ADR-006**: Two-Workflow Initialization Pattern
- **ADR-015**: Template-Workflows Separation Pattern
- **ADR-018**: Fork-Resources Staging Pattern
- **ADR-028**: Workflow Script Extraction Pattern