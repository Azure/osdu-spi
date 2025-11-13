# Sync Configuration System

This document explains the configuration-driven approach for syncing files between the template repository and forked repositories.

## Overview

The sync configuration system uses `.github/sync-config.json` to define exactly which files and directories should be synchronized between the template and forked repositories. This ensures consistency and makes it easy to manage what gets synced.

## Configuration File: `.github/sync-config.json`

### Structure

```json
{
  "description": "Configuration for syncing .github files between template and forked repositories",
  "sync_rules": {
    "directories": [...],
    "files": [...],
    "workflows": {
      "essential": [...],
      "template_only": [...]
    },
    "tracking_files": [...]
  },
  "exclusions": [...],
  "cleanup_rules": {
    "directories": [...],
    "files": [...],
    "workflows": [...]
  }
}
```

### Sync Rules

#### Directories
Directories that are synced entirely from template to fork:
- `actions/` - Custom GitHub Actions (including sync-state-manager for upstream sync duplicate prevention)
- `fork-resources/` - Fork-specific templates and configuration files

#### Files
Individual files that are synced:
- `dependabot.yml` - Dependency update configuration
- `labels.json` - Repository label definitions
- `branch-protection.json` - Branch protection rules
- `security-*.json` - Security configuration files
- `security-patterns.txt` - Security scanning patterns

#### Workflows

**Essential Workflows** (synced to forks):
- `sync.yml` - Upstream synchronization
- `validate.yml` - PR validation
- `build.yml` - Build and test automation
- `release.yml` - Release management
- `template-sync.yml` - Template updates
- `dependabot-validation.yml` - Dependabot automation

**Template-Only Workflows** (not synced):
- `init.yml` - Repository initialization
- `init-complete.yml` - Setup completion
- `cascade.yml` - Multi-repo operations
- `cascade-monitor.yml` - Cascade monitoring

#### Tracking Files
Files automatically created and managed:
- `.template-sync-commit` - Tracks last synced template commit

### Exclusions
Files that are never synced:
- `copilot-instructions.md` - AI assistant instructions

### Cleanup Rules
Files and directories removed during repository initialization to eliminate template-specific content:

#### Directories Removed
- `doc/` - Template documentation (replaced by upstream project docs)

#### Files Removed
- `.github/copilot-instructions.md` - Template-specific AI instructions

#### Template-Specific Templates Removed
- `.github/ISSUE_TEMPLATE/branch-protection-reminder.md` - Template initialization issue template
- `.github/ISSUE_TEMPLATE/init-error.md` - Template initialization issue template
- `.github/ISSUE_TEMPLATE/init-request.md` - Template initialization issue template
- `.github/ISSUE_TEMPLATE/init-started.md` - Template initialization issue template
- `.github/PULL_REQUEST_TEMPLATE/init-pr.md` - Template initialization PR template
- `.github/PULL_REQUEST_TEMPLATE/cleanup-pr.md` - Template initialization PR template

#### Workflows Removed
- `init.yml` - One-time initialization workflow
- `init-complete.yml` - One-time setup workflow

These cleanup rules ensure forked repositories only contain project-relevant files while removing template development artifacts.

## How It Works

### During Repository Initialization

The `init-complete.yml` workflow:
1. Reads the sync configuration from template
2. Copies directories, files, and essential workflows according to config
3. Initializes tracking files
4. Removes template-specific content using cleanup rules

### During Template Sync

The `template-sync.yml` workflow:
1. Detects existing template-sync PRs to prevent duplicates
2. Checks for changes only in configured sync paths
3. Syncs directories, files, and workflows that have changed
4. Updates existing PR if one is open, or creates new PR
5. Updates the sync configuration file itself
6. Creates or updates PR with detailed change information

#### Duplicate Prevention
Template sync implements duplicate prevention (ADR-031) to avoid creating multiple open PRs:
- Only one template-sync PR can be open at a time
- When template changes are detected, existing PRs are updated instead of creating new ones
- Force-pushes updates to existing branches when template advances
- Updates PR title and description to reflect current state

## Benefits

### Maintainability
- Single source of truth for what gets synced
- Easy to add/remove files from sync process
- Clear separation between template and fork files

### Visibility
- Configuration is versioned and visible
- PR descriptions show exactly what changed
- Audit trail of sync activities

### Flexibility
- Can easily exclude specific files
- Different treatment for different file types
- Graceful handling of missing files

### Consistency
- All forked repositories get the same essential files
- Template improvements automatically propagate
- Reduced manual maintenance

## Adding New Files to Sync

To add a new file or directory to the sync process:

1. **Edit `.github/sync-config.json`** in the template repository
2. **Add the path** to the appropriate section:
   - `directories` for entire directories
   - `files` for individual files  
   - `workflows.essential` for workflows that should go to forks
   - `workflows.template_only` for template-exclusive workflows

3. **Commit the change** to the template repository
4. **Wait for sync** - existing forks will automatically get the new file in their next template sync

### Example: Adding a New Action

```json
{
  "sync_rules": {
    "directories": [
      {
        "path": ".github/actions/my-new-action",
        "sync_all": true,
        "description": "Custom action for new functionality"
      }
    ]
  }
}
```

### Example: Adding a New Essential Workflow

```json
{
  "sync_rules": {
    "workflows": {
      "essential": [
        {
          "path": ".github/workflows/security-scan.yml",
          "description": "Automated security scanning"
        }
      ]
    }
  }
}
```

### Example: Adding Cleanup Rules

```json
{
  "cleanup_rules": {
    "files": [
      {
        "path": "TEMPLATE_README.md",
        "reason": "Template-specific readme replaced by project readme"
      }
    ],
    "directories": [
      {
        "path": "template-assets/",
        "reason": "Assets only needed for template development"
      }
    ]
  }
}
```

## Monitoring Sync Status

- **Template Sync PRs** show exactly which files changed
- **GitHub Actions logs** provide detailed sync information  
- **Tracking files** maintain sync state history
- **Configuration changes** are visible in repository history

This system ensures that template improvements automatically reach all forked repositories while maintaining clear boundaries between template management and project-specific functionality.