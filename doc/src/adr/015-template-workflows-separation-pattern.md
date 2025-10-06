# ADR-015: Template-Workflows Separation Pattern

## Status

**Accepted** - 2025-10-01

## Context

During implementation of the initialization workflows, we discovered a fundamental architectural challenge with workflow distribution in GitHub template repositories:

**The Workflow Pollution Problem:**

GitHub template repositories need two distinct types of workflows:

1. **Template Development Workflows**: For managing the template itself (init, testing, releases)
2. **Fork Production Workflows**: For the repositories created from the template (sync, build, validate)

**Previous Approach Issues:**

- All workflows stored in `.github/workflows/` caused fork repositories to inherit template development workflows
- Template-specific workflows (like `init.yml`) would appear in production forks where they serve no purpose
- No clear separation between template infrastructure and fork functionality
- Difficult to maintain and test template workflows without affecting fork behavior

**GitHub App Workflow Permissions Discovery:**

During initialization testing, we encountered a critical permission issue:

- GitHub Apps (including `GITHUB_TOKEN`) cannot create or modify workflow files without explicit `workflows` permission
- Error: `refusing to allow a GitHub App to create or update workflow .github/workflows/build.yml without workflows permission`
- Solution required using Personal Access Token (PAT) with workflows scope as `GH_TOKEN`

**Template Bootstrap Pattern Limitation:**

The existing bootstrap pattern (ADR-007) addressed workflow version updates but didn't solve workflow distribution segregation.

## Decision

Implement a **Template-Workflows Separation Pattern** that cleanly separates template development from fork production workflows:

### Directory Structure

```
.github/
├── workflows/                    # Template development workflows
│   ├── init.yml                  # Repository initialization
│   ├── init-complete.yml         # Repository setup
│   ├── dev-ci.yml               # Template testing
│   ├── dev-test.yml             # Template validation
│   └── dev-release.yml          # Template releases
└── template-workflows/           # Fork production workflows  
    ├── sync.yml                  # Upstream synchronization
    ├── validate.yml              # PR validation
    ├── build.yml                 # Project builds
    ├── release.yml               # Semantic releases
    ├── cascade.yml               # Multi-repo cascade
    ├── cascade-monitor.yml       # Cascade monitoring
    ├── sync-template.yml         # Template updates
    └── dependabot-validation.yml # Dependency automation
```

### Initialization Copy Process

During repository initialization, workflows are copied from `template-workflows/` to `workflows/` in the fork:

```bash
# Copy fork workflows from template repository
git checkout template/main -- .github/template-workflows/
mkdir -p .github/workflows
cp .github/template-workflows/*.yml .github/workflows/
```

## Rationale

### Clear Separation of Concerns

1. **Template Development**: All template-specific workflows stay in `.github/workflows/`
2. **Fork Production**: All production workflows stored in `.github/template-workflows/`
3. **No Pollution**: Forks only receive relevant production workflows
4. **Maintainable**: Easy to identify and maintain each workflow type

### Security and Permissions Benefits

1. **Controlled Distribution**: Only intended workflows reach fork repositories
2. **Permission Management**: Template workflows can have different permission requirements
3. **Security Isolation**: Template development workflows don't expose fork repositories to unnecessary permissions

### Development and Testing Advantages

1. **Independent Testing**: Template workflows can be tested without affecting fork behavior
2. **Clear Ownership**: Template developers vs. fork developers have clear workflow boundaries
3. **Version Control**: Template and fork workflows can evolve independently
4. **Documentation**: Clear documentation of what gets copied vs. what stays in template

## Alternatives Considered

### 1. Git Submodules for Workflow Distribution

- **Pros**: External workflow repository, version pinning
- **Cons**: Complex setup, external dependency, requires Git submodule knowledge
- **Decision**: Rejected - Adds unnecessary complexity

### 2. Workflow Generation Scripts

- **Pros**: Dynamic workflow creation, highly flexible
- **Cons**: Complex maintenance, harder to test, less transparent
- **Decision**: Rejected - Over-engineering for current needs

### 3. Multiple Template Repositories

- **Pros**: Complete separation, independent versioning
- **Cons**: Maintenance overhead, user confusion, complex updates
- **Decision**: Rejected - Breaks single template simplicity

### 4. Conditional Workflow Logic

- **Pros**: Single workflow files with template vs. fork behavior
- **Cons**: Complex conditions, harder to maintain, poor separation
- **Decision**: Rejected - Violates separation of concerns principle

## Implementation Details

### Initialization Process

```yaml
# init-complete.yml workflow excerpt
steps:
  - name: Copy fork workflows from template repository
    run: |
      # Add template remote and fetch
      git remote add template "$TEMPLATE_REPO_URL" || true
      git fetch template main --depth=1
      
      # Copy template-workflows directory
      git checkout template/main -- .github/template-workflows/
      
      # Ensure workflows directory exists and copy files
      mkdir -p .github/workflows
      cp .github/template-workflows/*.yml .github/workflows/
      
      # Clean up template-workflows directory (no longer needed)
      rm -rf .github/template-workflows/
```

### Sync Configuration Integration

Template-workflows are referenced in `.github/sync-config.json`:

```json
{
  "sync_rules": {
    "workflows": {
      "template_workflows": [
        {
          "path": ".github/template-workflows/sync.yml",
          "description": "Upstream repository synchronization"
        },
        {
          "path": ".github/template-workflows/validate.yml", 
          "description": "PR validation and commit message checks"
        }
      ]
    }
  }
}
```

### Authentication Requirements

Due to GitHub App workflow permission limitations:

- **Required**: Personal Access Token (PAT) with `workflows` permission as `GH_TOKEN` secret
- **Fallback**: Clear error message if `GH_TOKEN` not available
- **Process**: Checkout action uses `${{ secrets.GH_TOKEN || secrets.GITHUB_TOKEN }}`

## Consequences

### Positive

- **Clean Fork Repositories**: Only production workflows copied, no template pollution
- **Clear Maintenance**: Template developers know exactly which workflows affect forks
- **Security Isolation**: Template development workflows don't expose forks to unnecessary permissions
- **Better Testing**: Template workflows can be tested independently
- **User Experience**: Fork repositories have only relevant, functional workflows
- **Version Control**: Independent evolution of template vs. fork workflows

### Negative

- **Directory Duplication**: Template-workflows must be kept in sync with intended behavior
- **Authentication Complexity**: Requires PAT setup for workflow permissions
- **Documentation Overhead**: Need to maintain clear documentation of what goes where
- **Migration Impact**: Existing documentation needs updates to reflect new pattern

### Mitigation Strategies

1. **Clear Documentation**: Comprehensive documentation of directory structure and purposes
2. **Sync Configuration**: Automated tracking of which workflows should be copied
3. **Testing Strategy**: Validate both template and copied workflows function correctly
4. **Migration Guide**: Clear instructions for updating existing repositories

## Success Criteria

- ✅ Fork repositories contain only production workflows (no init, dev, or template workflows)
- ✅ Template repository maintains separation between development and production workflows
- ✅ Initialization process successfully copies workflows from template-workflows to workflows
- ✅ Authentication works with both GITHUB_TOKEN and GH_TOKEN approaches
- ✅ Documentation clearly explains workflow distribution strategy
- ✅ Testing validates that copied workflows function correctly in fork repositories

## Testing and Validation

### Template Testing

1. **Template Workflow Testing**: Validate init, dev, and release workflows in template repository
2. **Copy Process Testing**: Ensure template-workflows are correctly copied during initialization
3. **Permission Testing**: Validate both GITHUB_TOKEN and GH_TOKEN authentication paths

### Fork Testing 

1. **Production Workflow Testing**: Validate copied workflows function in fork repositories
2. **No Pollution Testing**: Ensure no template development workflows appear in forks
3. **Update Testing**: Validate template-sync can update production workflows

## Implementation Timeline

1. **✅ Phase 1**: Implement template-workflows directory structure
2. **✅ Phase 2**: Update initialization workflow to copy from template-workflows
3. **✅ Phase 3**: Resolve GitHub App workflow permission issues
4. **🔄 Phase 4**: Update documentation to reflect new pattern
5. **📋 Phase 5**: Validate with test repositories and gather feedback

## Related Decisions

- **ADR-006**: Two-Workflow Initialization Pattern - This pattern builds on the initialization architecture
- **ADR-007**: Initialization Workflow Bootstrap Pattern - This addresses workflow distribution rather than versioning
- **ADR-013**: Reusable GitHub Actions Pattern - Complements this with shared action components

## Future Considerations

1. **Automatic Sync Validation**: Ensure template-workflows stay in sync with intended behavior
2. **Workflow Templates**: Support for customizable workflow templates per fork type
3. **Multi-Environment Support**: Different workflow sets for different deployment environments
4. **Advanced Permissions**: Fine-grained workflow permission management
5. **Workflow Analytics**: Tracking which workflows are most/least used across forks

## Migration Guide

### For Template Maintainers

1. **Move Production Workflows**: Move fork-intended workflows from `.github/workflows/` to `.github/template-workflows/`
2. **Update Sync Config**: Add template-workflows to `.github/sync-config.json` 
3. **Test Initialization**: Validate that new repositories get correct workflow set
4. **Update Documentation**: Reflect new structure in README and architecture docs

### For Fork Maintainers

1. **No Action Required**: Existing forks continue to work with current workflows
2. **Optional Migration**: Can adopt new template-sync workflow for ongoing updates
3. **Clean Slate**: New forks automatically get clean workflow set

## References

- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [GitHub App Permissions](https://docs.github.com/en/developers/apps/building-github-apps/setting-permissions-for-github-apps)
- [Template Repository Documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository)
---

[← ADR-014](014-ai-enhanced-development-workflow.md) | :material-arrow-up: [Catalog](index.md) | [ADR-016 →](016-initialization-security-handling.md)
