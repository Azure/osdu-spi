# Repository Initialization Workflow

The repository initialization workflow transforms a newly created repository from the OSDU Azure SPI Management template into a fully functional fork management system. This workflow handles all the complex setup tasks automatically, including deploying the complete workflow suite, creating the three-branch architecture, configuring security settings, and validating that everything is working correctly before your team begins development.

The initialization process is designed with a two-phase approach that separates the immediate user experience from the more time-consuming system configuration tasks. This ensures you get immediate feedback that setup has started successfully, while the detailed configuration work happens in the background without requiring you to wait or monitor the process.

## When It Runs

The initialization workflow activates in several scenarios to ensure your repository is properly configured:

- **Template creation** - Automatically triggers when you create a new repository from this template
- **Push to `main`** - The template's initial commit starts the workflow in a newly created repository

The completion phase starts only after an owner, member, or collaborator replies to the generated initialization issue.

## What Happens

The initialization process unfolds in two coordinated phases designed to provide optimal user experience while ensuring thorough setup:

### Immediate Setup Phase (30 seconds)
The workflow verifies that the repository is not the template itself, creates the standard labels, and opens a setup issue. Reply to that issue with the upstream repository reference; the issue comment triggers the completion workflow.

### Full Configuration Phase (5-10 minutes)
The completion workflow validates the upstream repository, sets `UPSTREAM_REPO_URL`, generates a filtered `fork_upstream` through the upstream filter engine, creates `fork_integration`, seeds the fork-owned Azure trees and plants `.github/upstream-filter.yml`, deploys all fork workflows, applies fork resources and repository rulesets, and marks `INITIALIZATION_COMPLETE`.

The filter configuration comes from the template's `.github/fork-resources/upstream-filter.yml` with `<service>` substituted from the upstream repository name. A service that deviates from the conventional shape (extra top-level entries, a module prefix that differs from the repository name) uses the escape hatch: commit a complete `.github/upstream-filter.yml` to the fork's `main` before replying to the initialization issue, and initialization prefers that file over the template. If the filter halts on an unclassified entry, the initialization issue receives the halt detail and both remediation paths; fix the config and comment again to retry.

The Azure provider and test trees (`provider/<service>-azure`, `testing/<service>-test-azure`) are seeded from the newest upstream commit that still contains them, version-stamped against the generated tree, and committed on `fork_integration` before the merge to `main`. From that point the fork owns them: they never appear on `fork_upstream`, so upstream merges cannot touch them.

The initialization process produces clear outcomes to guide your next steps:
- **Success**: Your repository is fully configured and ready for upstream synchronization and team development
- **Failure**: The setup issue is updated with specific resolution steps and guidance for addressing any configuration problems

## When You Need to Act

### Required Configuration
- **GitHub App credentials** - `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` must be available for workflow and ruleset writes
- **Upstream repository** - Reply to the initialization issue with `owner/repository` or a supported repository URL
- **Filter configuration** - Generated automatically from the template; only nonconventional services need a hand-planted `.github/upstream-filter.yml` on `main` before replying to the issue
- **Team permissions** - Ensure team has appropriate access levels

### Optional Configuration
- **AI providers** - Configure API keys for enhanced PR descriptions
- **Notifications** - Set up issue/PR notifications for your team
- **Custom labels** - Add project-specific labels beyond defaults

## How to Respond

### Complete Required Setup
1. **Check setup issue** - Look for repository configuration checklist
2. **Reply with the upstream repository**:
   ```
   OpenSubsurfaceDataForum/partition
   ```

3. **Verify repository variables** - Initialization sets `UPSTREAM_REPO_URL` and `INITIALIZATION_COMPLETE`
4. **Verify branch protection** - Ensure the repository rulesets are active
5. **Test initial sync** - Run upstream sync manually to verify setup

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
- **`fork_upstream`** - Generated upstream-owned tree without provider source
- **`fork_integration`** - Integration and conflict resolution branch

### Workflows Installed
- **`sync.yml`** - Daily upstream synchronization
- **`cascade.yml`** - Three-branch integration process
- **`build.yml`** - Build and test automation
- **`validate.yml`** - PR quality gates
- **`release.yml`** - Automated version and image-tag management
- **Supporting workflows** - Template sync, CodeQL, Dependabot validation, cascade monitoring, integration cleanup, settings reconciliation, and GHCR retention

### Security Configuration
- **Branch protection** - Required PR reviews and status checks
- **Action permissions** - Appropriate workflow execution permissions
- **Issue templates** - Standardized issue reporting
- **Security scanning** - Dependabot and vulnerability detection

## Configuration

| Name | Type | Purpose |
|------|------|---------|
| `UPSTREAM_REPO_URL` | Variable, set during initialization | Repository to synchronize |
| `INITIALIZATION_COMPLETE` | Variable, set during initialization | Enables fork workflows |
| `MAVEN_PROFILE` | Optional variable | Overrides the `core,azure` default |
| `SERVICE_NAME` | Optional variable | Overrides the repository-name image/service slug |
| `SERVICE_TARGET_JAR` | Optional variable | Disambiguates repositories that build multiple Azure JARs |
| `GITHUB_TOKEN` | Automatic secret | Normal GitHub API and package operations |
| `AZURE_API_KEY`, `AZURE_API_BASE`, `AZURE_API_VERSION` | Optional secrets | AI-enhanced sync descriptions |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Setup issue not created" | Check Actions are enabled, rerun workflow |
| "Branch creation failed" | Verify default branch is 'main', check permissions |
| "Workflow deployment error" | Remove conflicting `.github/workflows/` files |
| "Protection rules failed" | Ensure admin access, check repository settings |
| "Initial sync fails" | Verify the `UPSTREAM_REPO_URL` variable and filter configuration |

## Post-Setup Checklist

- [ ] **Setup issue closed successfully** - Initialization completed without errors
- [ ] **Three branches exist** - `main`, `fork_upstream`, `fork_integration`
- [ ] **`fork_upstream` is filtered** - No `provider/` or `devops/` directories on the branch
- [ ] **Azure trees seeded on `main`** - `provider/<service>-azure` and `testing/<service>-test-azure` present, with `.github/upstream-filter.yml`
- [ ] **Workflows active** - All deployed fork workflows are visible in the Actions tab
- [ ] **Variables configured** - `UPSTREAM_REPO_URL` and `INITIALIZATION_COMPLETE` are set
- [ ] **GitHub App available** - Release App credentials support protected writes
- [ ] **Protection enabled** - `main` branch requires PR reviews
- [ ] **Initial sync works** - Manual upstream sync runs successfully
- [ ] **Team permissions** - Team has appropriate repository access

## Next Steps

1. **Verify upstream sync** - Confirm `UPSTREAM_REPO_URL` matches the issue response
2. **Run first sync** - Manually trigger upstream synchronization workflow
3. **Set up notifications** - Configure team alerts for sync issues and PRs
4. **Review documentation** - Read [synchronization](synchronization.md) and [cascade](cascade.md) workflows
5. **Add team members** - Invite collaborators with appropriate permissions

## Related

- [Synchronization Workflow](synchronization.md) - Next step after initialization
- [Three-Branch Strategy](../adr/001-three-branch-strategy.md) - Branching architecture
- [Initialization Security](../adr/016-initialization-security-handling.md) - Security configuration details
- [ADR-038: Upstream Filter Transform](../adr/038-upstream-filter-transform.md) - Filter and Azure seeding model