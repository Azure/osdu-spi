# ADR-003: Template Repository Pattern for Self-Configuration

## Status
**Accepted** - 2025-10-01

## Context
Teams need a way to quickly set up fork management systems for different upstream repositories without manual configuration. The setup process involves creating branch structures, configuring workflows, setting up branch protection rules, and establishing the upstream relationship.

Manual setup requirements would include:
- Creating and configuring three branches with proper relationships
- Setting up GitHub Actions workflows with repository-specific parameters
- Configuring branch protection rules and security settings
- Establishing upstream repository connection
- Initializing project-specific build configurations

The solution must provide zero-configuration deployment while allowing customization for different project types and requirements.

## Decision
Implement the fork management system as a GitHub Template Repository with automatic self-configuration through an initialization workflow that:

1. **Template Repository Structure**: Repository marked as template with complete workflow and configuration files
2. **Issue-Based Configuration**: Use GitHub Issues to capture upstream repository URL during initialization
3. **Automated Setup Workflow**: `init.yml` workflow configures the repository automatically upon creation
4. **Self-Modifying Workflows**: Workflows update themselves with repository-specific parameters

## Rationale

### Template Repository Benefits
1. **One-Click Deployment**: Users create new repositories with single click from template
2. **Complete Setup**: All workflows, configurations, and documentation included
3. **Version Control**: Template updates can be tracked and deployed systematically
4. **GitHub Native**: Uses GitHub's built-in template functionality
5. **No External Dependencies**: Requires no external tools or services

### Issue-Based Configuration
1. **User-Friendly**: Simple form-based interface for configuration input
2. **Validation**: Can validate upstream repository URLs before processing
3. **Audit Trail**: Configuration decisions are recorded in issue history
4. **Interactive**: Allows clarification and validation during setup
5. **Accessible**: Works through GitHub web interface without technical setup

### Self-Configuration Approach
1. **Immediate Activation**: Repository becomes functional immediately after creation
2. **Customization**: Can adapt to different project types and requirements
3. **Consistency**: Ensures all fork repositories follow the same patterns
4. **Maintenance**: Template updates can be propagated to existing repositories

## Alternatives Considered

### 1. Manual Setup Documentation
- **Pros**: Simple, no automation complexity
- **Cons**: Error-prone, time-consuming, inconsistent results, requires technical expertise
- **Decision**: Rejected due to user experience and consistency concerns

### 2. CLI Tool for Setup
- **Pros**: Powerful, flexible configuration options
- **Cons**: Requires tool installation, platform dependencies, maintenance overhead
- **Decision**: Rejected due to deployment complexity

### 3. External Configuration Service
- **Pros**: Centralized management, advanced configuration options
- **Cons**: External dependency, security concerns, additional infrastructure
- **Decision**: Rejected due to complexity and external dependencies

### 4. Cookiecutter/Yeoman Template
- **Pros**: Industry standard, powerful templating
- **Cons**: Requires local tools, no automatic updates, static generation
- **Decision**: Rejected due to local tool requirements

## Consequences

### Positive
- **Zero Friction**: Teams can deploy fork management in under 5 minutes
- **Consistency**: All repositories follow identical patterns and configurations
- **Self-Updating**: Template improvements benefit all deployed repositories
- **User-Friendly**: No technical expertise required for deployment
- **Maintainable**: Centralized template makes updates and improvements easy
- **Scalable**: Can support unlimited repository deployments

### Negative
- **GitHub Lock-in**: Tied specifically to GitHub's template repository feature
- **Limited Customization**: Initial setup options are constrained by issue form capabilities
- **Bootstrap Complexity**: Self-modifying workflows add complexity to initialization
- ~~**Update Propagation**: Changes to template don't automatically update existing repositories~~ **[RESOLVED by ADR-011, ADR-012]**

## Implementation Details

### Template Repository Setup
- Repository marked as template in GitHub settings
- Complete workflow files with placeholder variables
- Documentation and configuration files included
- Example configurations for common scenarios

### Initialization Process
1. **Repository Creation**: User creates repository from template
2. **Issue Creation**: `init.yml` workflow creates configuration issue automatically
3. **User Input**: User provides upstream repository URL in issue comment
4. **Validation**: Workflow validates upstream repository accessibility
5. **Configuration**: Workflows update themselves with repository-specific parameters
6. **Branch Setup**: Three-branch structure created with upstream connection
7. **Protection Rules**: Branch protection and security settings applied
8. **Cleanup**: Initialization issue closed, repository ready for use

### Configuration Parameters
- **Upstream Repository**: GitHub or GitLab repository URL
- **Project Type**: Java, Node.js, Python, etc. (affects build workflows)
- **Sync Schedule**: Weekly, daily, or manual synchronization
- **Security Settings**: Branch protection, required reviews, status checks

### Self-Modification Approach
```yaml
# Example: Update workflow file with repository-specific values
- name: Configure Sync Workflow
  run: |
    sed -i 's|UPSTREAM_REPO_PLACEHOLDER|${{ env.UPSTREAM_REPO }}|g' .github/workflows/sync.yml
    git add .github/workflows/sync.yml
    git commit -m "Configure upstream repository for sync workflow"
```

## Success Criteria
- Repository deployment completes in under 5 minutes from template creation
- Non-technical users can successfully deploy and configure repositories
- All deployed repositories maintain consistent structure and behavior
- Template updates can be propagated to existing repositories
- Configuration errors are caught and reported clearly during setup
- Deployed repositories are immediately functional for upstream synchronization
---

[← ADR-002](002-github-actions-automation.md) | :material-arrow-up: [Catalog](index.md) | [ADR-004 →](004-release-please-versioning.md)
