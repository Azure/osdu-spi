# Repository Initialization Workflow

The repository initialization workflow transforms a newly created repository from the OSDU Azure SPI Management template into a fully functional fork management system. This workflow handles all the complex setup tasks automatically, including deploying the complete workflow suite, creating the three-branch architecture, configuring security settings, and validating that everything is working correctly before your team begins development.

The initialization process is designed with a two-phase approach that separates the immediate user experience from the more time-consuming system configuration tasks. This ensures you get immediate feedback that setup has started successfully, while the detailed configuration work happens in the background without requiring you to wait or monitor the process.

## When It Runs

The initialization workflow activates in several scenarios to ensure your repository is properly configured:

- **Template creation** - Automatically triggers when you create a new repository from this template
- **Manual trigger** - Available via GitHub Actions tab if setup needs to be rerun or troubleshooting is required
- **Fork creation** - Activates when forking an existing OSDU SPI repository to ensure proper configuration

## What Happens

The initialization process unfolds in two coordinated phases designed to provide optimal user experience while ensuring thorough setup:

### Immediate Setup Phase (30 seconds)
The workflow immediately creates a setup issue that serves as a tracking mechanism for initialization progress, validates that all required template files are present and properly formatted, triggers the main configuration workflow to begin the detailed setup process, and provides immediate feedback through the setup issue so you know the process has started successfully.

### Full Configuration Phase (5-10 minutes)
The comprehensive setup process deploys all workflow files including sync, cascade, build, validation, and release management workflows to your repository. It creates the essential `fork_upstream` and `fork_integration` branches that form the foundation of the three-branch architecture, applies branch protection rules and security settings to ensure safe collaboration, enables repository features like issues and discussions that support the fork management process, and validates the entire setup by running initial checks to confirm everything is functioning correctly.

The initialization process produces clear outcomes to guide your next steps:
- **Success**: Your repository is fully configured and ready for upstream synchronization and team development
- **Failure**: The setup issue is updated with specific resolution steps and guidance for addressing any configuration problems

## When You Need to Act

### Required Configuration
- **Repository secrets** - Must be configured before first sync
- **Upstream repository** - Must specify which repository to sync from
- **Team permissions** - Ensure team has appropriate access levels

### Optional Configuration
- **AI providers** - Configure API keys for enhanced PR descriptions
- **Notifications** - Set up issue/PR notifications for your team
- **Custom labels** - Add project-specific labels beyond defaults

## How to Respond

### Complete Required Setup
1. **Check setup issue** - Look for repository configuration checklist
2. **Configure secrets**:
   ```
   UPSTREAM_REPO_URL - Repository to sync from (required)
   GITHUB_TOKEN - Provided automatically
   AZURE_API_KEY - AI provider (optional)
   AZURE_API_BASE - Azure Foundry endpoint (optional)
   AZURE_API_VERSION - Azure API version (optional)
   ```

3. **Verify branch protection** - Ensure `main` branch is protected
4. **Test initial sync** - Run upstream sync workflow manually to verify setup

### Handle Setup Failures
```bash
# Check workflow logs in Actions tab
# Common issues and solutions:

# Permission errors
# - Ensure repository has Actions write permissions
# - Check team has admin access to repository

# Branch creation failures
# - Verify default branch is 'main'
# - Check for existing conflicting branches

# Workflow deployment issues
# - Ensure Actions are enabled in repository settings
# - Verify no conflicting workflow files exist
```

### Verify Successful Setup
1. **Check branches** - Should have `main`, `fork_upstream`, `fork_integration`
2. **Test workflows** - All workflows should be visible in Actions tab
3. **Verify protection** - Branch protection rules should be active
4. **Run sync test** - Manual upstream sync should work without errors

## Repository Structure Created

### Branches
- **`main`** - Your production branch (protected)
- **`fork_upstream`** - Mirror of upstream repository
- **`fork_integration`** - Integration and conflict resolution branch

### Workflows Installed
- **`sync.yml`** - Daily upstream synchronization
- **`cascade.yml`** - Three-branch integration process
- **`build.yml`** - Build and test automation
- **`validate.yml`** - PR quality gates
- **`release.yml`** - Automated version management

### Security Configuration
- **Branch protection** - Required PR reviews and status checks
- **Action permissions** - Appropriate workflow execution permissions
- **Issue templates** - Standardized issue reporting
- **Security scanning** - Dependabot and vulnerability detection

## Required Secrets

| Secret | Purpose | Required |
|--------|---------|----------|
| `UPSTREAM_REPO_URL` | Repository to sync from | ✅ Yes |
| `GITHUB_TOKEN` | Automatically provided | ✅ Yes |
| `AZURE_API_KEY` | AI-enhanced PR descriptions | ❌ Optional |
| `AZURE_API_BASE` | Azure Foundry endpoint | ❌ Optional |
| `AZURE_API_VERSION` | Azure API version | ❌ Optional |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Setup issue not created" | Check Actions are enabled, rerun workflow |
| "Branch creation failed" | Verify default branch is 'main', check permissions |
| "Workflow deployment error" | Remove conflicting `.github/workflows/` files |
| "Protection rules failed" | Ensure admin access, check repository settings |
| "Initial sync fails" | Verify `UPSTREAM_REPO_URL` secret is correct |

## Post-Setup Checklist

- [ ] **Setup issue closed successfully** - Initialization completed without errors
- [ ] **Three branches exist** - `main`, `fork_upstream`, `fork_integration`
- [ ] **Workflows active** - All 5 workflows visible in Actions tab
- [ ] **Secrets configured** - At minimum `UPSTREAM_REPO_URL` is set
- [ ] **Protection enabled** - `main` branch requires PR reviews
- [ ] **Initial sync works** - Manual upstream sync runs successfully
- [ ] **Team permissions** - Team has appropriate repository access

## Next Steps

1. **Configure upstream sync** - Set `UPSTREAM_REPO_URL` to target repository
2. **Run first sync** - Manually trigger upstream synchronization workflow
3. **Set up notifications** - Configure team alerts for sync issues and PRs
4. **Review documentation** - Read [synchronization](synchronization.md) and [cascade](cascade.md) workflows
5. **Add team members** - Invite collaborators with appropriate permissions

## Related

- [Synchronization Workflow](synchronization.md) - Next step after initialization
- [Three-Branch Strategy](../decisions/adr_001_three_branch_strategy.md) - Branching architecture
- [Security Setup](../decisions/adr_016_security.md) - Security configuration details