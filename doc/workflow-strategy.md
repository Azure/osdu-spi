# Workflow Distribution Strategy

This document outlines the **Template-Workflows Separation Pattern** (ADR-015) which cleanly separates template development workflows from fork production workflows.

## Architecture Overview

**Template-Workflows Separation Pattern:**
- `.github/workflows/` - Template development workflows (stay in template)
- `.github/template-workflows/` - Fork production workflows (copied during initialization)

## Fork Production Workflows (Copied from template-workflows/)

These workflows are stored in `.github/template-workflows/` and copied to `.github/workflows/` in fork repositories during initialization:

### Core Functionality
- **`sync.yml`** - Upstream repository synchronization
- **`validate.yml`** - PR validation and commit message checks  
- **`build.yml`** - Project build and test automation
- **`release.yml`** - Automated semantic versioning and releases

### Infrastructure Management
- **`sync-template.yml`** - Template repository updates
- **`dependabot-validation.yml`** - Dependabot PR automation

### Advanced Features
- **`cascade.yml`** - Multi-repository cascade operations
- **`cascade-monitor.yml`** - Cascade monitoring and SLA management

### Support Files
- **`.github/actions/`** - Custom GitHub Actions
- **`.github/labels.json`** - Repository label configuration
- **`.github/dependabot.yml`** - Dependency update configuration
- **`.github/.template-sync-commit`** - Template sync tracking file

## Template Development Workflows (Stay in template)

These workflows remain in `.github/workflows/` in the template repository and are NOT copied to forks:

### Repository Management  
- **`init.yml`** - Repository initialization trigger
- **`init-complete.yml`** - Repository setup and configuration

### Template Development
- **`dev-ci.yml`** - Template testing and validation
- **`dev-test.yml`** - Template workflow testing
- **`dev-release.yml`** - Template version releases

## How Template-Workflows Separation Works

### During Initialization
1. **Template Fetch**: Initialization workflow fetches latest template repository
2. **Workflow Copy**: Copy workflows from `.github/template-workflows/` to `.github/workflows/` in fork
3. **Cleanup**: Remove `.github/template-workflows/` directory (no longer needed in fork)
4. **Configuration**: Apply sync configuration from `.github/sync-config.json`

### Ongoing Template Updates  
1. **Template Sync**: `sync-template.yml` workflow pulls updates for fork workflows
2. **Version Tracking**: `.template-sync-commit` tracks last synced template version
3. **Selective Updates**: Only production workflows updated, never template development workflows

### Authentication Requirements
Due to GitHub App workflow permission limitations:
- **Required**: Personal Access Token (PAT) with `workflows` permission as `GH_TOKEN` secret
- **Process**: `${{ secrets.GH_TOKEN || secrets.GITHUB_TOKEN }}` for checkout authentication

For detailed information about the sync configuration, see [Sync Configuration Documentation](sync-configuration.md).

## Benefits of Template-Workflows Separation

- **Clean Fork Repositories**: Only production workflows copied, no template pollution
- **Clear Maintenance**: Template developers know exactly which workflows affect forks  
- **Security Isolation**: Template development workflows don't expose forks to unnecessary permissions
- **Better Testing**: Template workflows can be tested independently
- **Version Control**: Independent evolution of template vs. fork workflows
- **User Experience**: Fork repositories have only relevant, functional workflows

## Repository Structure Comparison

### Template Repository
```
.github/
├── workflows/                    # Template development (NOT copied)
│   ├── init.yml                  # Repository initialization
│   ├── init-complete.yml         # Repository setup
│   ├── dev-ci.yml               # Template testing
│   ├── dev-test.yml             # Template validation
│   └── dev-release.yml          # Template releases
└── template-workflows/           # Fork production (COPIED)
    ├── sync.yml                  # → Copied to forks
    ├── validate.yml              # → Copied to forks
    ├── build.yml                 # → Copied to forks
    ├── release.yml               # → Copied to forks
    ├── cascade.yml               # → Copied to forks
    ├── cascade-monitor.yml       # → Copied to forks
    ├── sync-template.yml         # → Copied to forks
    └── dependabot-validation.yml # → Copied to forks
```

### Fork Repository (After Initialization)
```
.github/workflows/                # Clean production workflows only
├── sync.yml                      # Copied from template-workflows
├── validate.yml                  # Copied from template-workflows
├── build.yml                     # Copied from template-workflows
├── release.yml                   # Copied from template-workflows
├── cascade.yml                   # Copied from template-workflows
├── cascade-monitor.yml           # Copied from template-workflows
├── sync-template.yml             # Copied from template-workflows
└── dependabot-validation.yml     # Copied from template-workflows
```

## Key Advantages

1. **No Workflow Pollution**: Fork repositories never receive template development workflows
2. **Clear Purpose**: Each workflow has a clear intended environment (template vs. fork)
3. **Independent Testing**: Template workflows can be tested without affecting forks
4. **Security Boundaries**: Template and fork workflows have appropriate permission scopes
5. **Maintenance Clarity**: Easy to identify which workflows affect production vs. development

This pattern ensures forks get all essential automation while maintaining clean separation between template development infrastructure and production fork functionality.