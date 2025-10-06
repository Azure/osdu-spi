# ADR-011: Configuration-Driven Template Synchronization

## Status
**Accepted** - 2025-10-01

## Context

The original template repository pattern (ADR-003) created a bootstrap problem: once repositories were created from the template, there was no systematic way to propagate template improvements (workflow updates, security patches, new features) to existing forked repositories without manual intervention or repository recreation.

**Problems with Static Template Approach:**

- **Template Drift**: Forked repositories became outdated as template improved
- **Manual Updates**: No automated way to get workflow improvements
- **Inconsistent Infrastructure**: Repositories diverged from template over time
- **Security Lag**: Security improvements in template didn't reach existing forks
- **Maintenance Burden**: Teams had to manually track and apply template changes

**Need for Systematic Sync Management:**

- Define exactly which files should be synchronized between template and forks
- Distinguish between template-management files and project-essential files
- Handle cleanup of template-specific content during initialization
- Provide visibility into what gets synced and why

## Decision

Implement a **Configuration-Driven Template Synchronization System** using `.github/sync-config.json` to define:

### 1. **Sync Configuration File**: `.github/sync-config.json`
```json
{
  "sync_rules": {
    "directories": [],      // Directories synced entirely
    "files": [],           // Individual files synced
    "workflows": {
      "essential": [],     // Workflows copied to forks
      "template_only": []  // Workflows that stay in template
    },
    "tracking_files": []   // Auto-managed sync state files
  },
  "cleanup_rules": {
    "directories": [],     // Directories removed during init
    "files": [],          // Files removed during init
    "workflows": []       // Workflows removed during init
  },
  "exclusions": []        // Files never synced
}
```

### 2. **Selective File Synchronization**

- **Essential Infrastructure**: Issue templates, PR templates, security configs, labels
- **Essential Workflows**: Sync, validate, build, release, template-sync, dependabot-validation
- **Template-Only Content**: Initialization workflows, cascade management, template documentation
- **Cleanup Content**: Template-specific files removed during repository initialization

### 3. **Configuration-Aware Workflows**

- **`init-complete.yml`**: Uses sync config to copy only essential files during initialization
- **`template-sync.yml`**: Uses sync config to determine what files to check for updates
- **Tracking System**: `.github/.template-sync-commit` tracks last synced template version

## Rationale

### Benefits of Configuration-Driven Approach

1. **Maintainable**: Single source of truth for sync behavior
2. **Visible**: Clear documentation of what gets synced and why
3. **Flexible**: Easy to add/remove files from sync process
4. **Consistent**: All forked repositories get same essential infrastructure
5. **Safe**: Explicit rules prevent accidental over-syncing or under-syncing
6. **Auditable**: Changes to sync behavior are tracked in version control

### Solving Template Drift Problem

1. **Automated Propagation**: Template improvements automatically reach forks
2. **Selective Updates**: Only essential files get updated, not project-specific content
3. **Conflict Prevention**: Clear separation between template and project concerns
4. **Version Tracking**: Track what template version each fork is synchronized to

### Initialization Cleanup Benefits

1. **Clean Forks**: Remove template development artifacts from forked repositories
2. **Documented Cleanup**: Clear reasons for each cleanup rule
3. **Consistent Results**: All forks have same clean starting state
4. **Future-Proof**: Easy to adjust cleanup behavior

## Alternatives Considered

### 1. **Manual Sync Documentation**

- **Pros**: Simple, no automation complexity
- **Cons**: Error-prone, time-consuming, rarely followed
- **Decision**: Rejected due to poor adoption and consistency

### 2. **Git Subtree/Submodule for Template**

- **Pros**: Native Git functionality
- **Cons**: Complex for users, doesn't handle selective syncing
- **Decision**: Rejected due to user experience complexity

### 3. **Hardcoded Sync Lists in Workflows**

- **Pros**: Direct, no additional configuration
- **Cons**: Difficult to maintain, no documentation of decisions
- **Decision**: Rejected due to maintainability concerns

### 4. **External Sync Service**

- **Pros**: Powerful, could handle complex scenarios
- **Cons**: External dependency, additional infrastructure
- **Decision**: Rejected due to complexity and dependencies

## Implementation Details

### Sync Configuration Categories

#### Essential Infrastructure Files
```json
{
  "directories": [
    ".github/ISSUE_TEMPLATE",
    ".github/PULL_REQUEST_TEMPLATE", 
    ".github/actions"
  ],
  "files": [
    ".github/dependabot.yml",
    ".github/labels.json",
    ".github/branch-protection.json",
    ".github/security-on.json",
    ".github/security-off.json",
    ".github/security-patterns.txt"
  ]
}
```

#### Essential vs Template-Only Workflows
```json
{
  "workflows": {
    "essential": [
      ".github/workflows/sync.yml",
      ".github/workflows/validate.yml",
      ".github/workflows/build.yml", 
      ".github/workflows/release.yml",
      ".github/workflows/template-sync.yml",
      ".github/workflows/dependabot-validation.yml"
    ],
    "template_only": [
      ".github/workflows/init.yml",
      ".github/workflows/init-complete.yml",
      ".github/workflows/cascade.yml",
      ".github/workflows/cascade-monitor.yml"
    ]
  }
}
```

#### Initialization Cleanup Rules
```json
{
  "cleanup_rules": {
    "directories": [
      {"path": "doc/", "reason": "Template documentation replaced by upstream project docs"}
    ],
    "files": [
      {"path": ".github/copilot-instructions.md", "reason": "Template-specific AI instructions"}
    ],
    "workflows": [
      {"path": ".github/workflows/init.yml", "reason": "One-time initialization workflow"},
      {"path": ".github/workflows/init-complete.yml", "reason": "One-time setup workflow"}
    ]
  }
}
```

### Configuration Usage Patterns

#### During Initialization (init-complete.yml)
```bash
# Copy directories that should be synced entirely
DIRECTORIES=$(jq -r '.sync_rules.directories[] | .path' .github/sync-config.json)
for dir in $DIRECTORIES; do
  git checkout main -- "$dir/" || echo "Directory $dir not found, skipping"
done

# Remove template-specific content using cleanup rules
CLEANUP_DIRS=$(jq -r '.cleanup_rules.directories[]? | .path' .github/sync-config.json)
for dir in $CLEANUP_DIRS; do
  rm -rf "$dir"
done
```

#### During Template Sync (template-sync.yml)
```bash
# Check for changes only in configured sync paths
SYNC_PATHS=""
DIRECTORIES=$(jq -r '.sync_rules.directories[] | .path' temp-sync-config.json)
for dir in $DIRECTORIES; do
  SYNC_PATHS="$SYNC_PATHS $dir"
done

# Check for changes in the configured paths only
for path in $SYNC_PATHS; do
  CHANGES=$(git diff --name-only $LAST_SYNC_COMMIT..$TEMPLATE_COMMIT template/main -- "$path")
done
```

## Consequences

### Positive

- **Eliminates Template Drift**: Forked repositories automatically stay current with template
- **Selective Synchronization**: Only essential infrastructure gets updated
- **Clean Repository State**: Template artifacts automatically removed during initialization
- **Maintainable Sync Logic**: Single configuration file controls all sync behavior
- **Transparent Process**: Clear documentation of what gets synced and why
- **Version Tracking**: Track template synchronization history
- **Conflict Prevention**: Clear boundaries between template and project content

### Negative

- **Configuration Complexity**: Additional configuration file to maintain
- **Bootstrap Dependency**: Sync configuration must exist before sync can work
- **Learning Curve**: Team needs to understand sync configuration structure
- **JSON Management**: Configuration changes require JSON syntax knowledge

### Mitigation Strategies

- **Documentation**: Comprehensive documentation with examples (doc/sync-configuration.md)
- **Validation**: JSON validation during development and in workflows
- **Self-Updating**: Configuration file itself is synced, ensuring consistency
- **Clear Examples**: Well-documented examples for adding new sync rules

## Success Criteria

- ✅ **Template improvements automatically reach forked repositories**
- ✅ **No manual intervention required for infrastructure updates**
- ✅ **Clear separation between template and project content**
- ✅ **Easy to add new files to sync process**
- ✅ **Forked repositories maintain clean state without template artifacts**
- ✅ **Sync behavior is documented and auditable**
- ✅ **Template drift problem is eliminated**

## Future Evolution

### Potential Enhancements

1. **Conditional Sync Rules**: Sync different files based on project type
2. **Conflict Resolution**: Automated handling of sync conflicts
3. **Sync Analytics**: Tracking sync success rates and common issues
4. **Custom Sync Schedules**: Per-repository sync frequency configuration

### Extensibility Design

- **Modular Configuration**: Easy to add new sync rule categories
- **Version Evolution**: Configuration schema can evolve with backward compatibility
- **Plugin Architecture**: Support for custom sync processors
- **Integration Points**: Hooks for additional sync validation or processing

## Related ADRs

- **ADR-003**: Template Repository Pattern for Self-Configuration (updated by this decision)
- **ADR-006**: Two-Workflow Initialization Pattern (enhanced by sync configuration)
- **ADR-012**: Template Update Propagation Strategy (depends on this configuration system)
---

[← ADR-010](010-yaml-safe-shell-scripting.md) | :material-arrow-up: [Catalog](index.md) | [ADR-012 →](012-template-update-propagation-strategy.md)
