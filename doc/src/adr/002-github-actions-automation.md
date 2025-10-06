# ADR-002: GitHub Actions-Based Automation Architecture

## Status
**Accepted** - 2025-10-01

## Context
The fork management system requires extensive automation to handle repository initialization, upstream synchronization, conflict detection, build validation, and release management. The automation must be reliable, maintainable, and integrate seamlessly with GitHub's repository management features.

Key automation requirements:
- Repository initialization and configuration
- Scheduled upstream synchronization
- Automated conflict detection and resolution workflows
- Build and test automation
- Release management and versioning
- Security scanning and compliance checks

## Decision
Implement all automation using GitHub Actions with a modular workflow architecture consisting of:

1. **init.yml** - Repository initialization and setup
2. **sync.yml** - Upstream synchronization with issue lifecycle tracking and duplicate prevention
3. **cascade.yml** - Human-triggered integration workflow with issue updates
4. **cascade-monitor.yml** - Safety net detection and health monitoring
5. **validate.yml** - PR validation and compliance checks
6. **build.yml** - Build, test, and coverage reporting
7. **release.yml** - Automated release management

## Rationale

### GitHub Actions Benefits
1. **Native Integration**: Deep integration with GitHub repository features
2. **No External Dependencies**: Eliminates need for external CI/CD services
3. **Cost Effective**: Included with GitHub repositories
4. **Security**: Runs in GitHub's secure environment with built-in secrets management
5. **Marketplace Ecosystem**: Rich ecosystem of pre-built actions
6. **Event-Driven**: Responds to repository events automatically

### Modular Workflow Design
1. **Separation of Concerns**: Each workflow has a single responsibility
2. **Maintainability**: Easier to update and debug individual workflows
3. **Reusability**: Common patterns can be extracted to composite actions
4. **Conditional Execution**: Workflows only run when relevant
5. **Parallel Execution**: Independent workflows can run concurrently

## Alternatives Considered

### 1. External CI/CD Platform (Jenkins, GitLab CI, etc.)
- **Pros**: More powerful build environments, advanced features
- **Cons**: External dependencies, additional cost, complexity, security considerations
- **Decision**: Rejected due to complexity and external dependencies

### 2. Monolithic Single Workflow
- **Pros**: All logic in one place
- **Cons**: Complex, hard to maintain, unnecessary execution of unrelated tasks
- **Decision**: Rejected due to maintainability concerns

### 3. Serverless Functions (AWS Lambda, Azure Functions)
- **Pros**: Highly scalable, event-driven
- **Cons**: Platform lock-in, complex setup, additional infrastructure costs
- **Decision**: Rejected due to complexity and vendor lock-in

## Consequences

### Positive
- **Zero Setup**: Works immediately when repository is created from template
- **Integrated Security**: Leverages GitHub's security features and secrets management
- **Event-Driven**: Automatically responds to repository changes
- **Maintainable**: Modular design makes updates and debugging easier
- **Cost Effective**: No additional service costs beyond GitHub subscription
- **Reliable**: GitHub's infrastructure provides high availability

### Negative
- **GitHub Lock-in**: Tied to GitHub platform specifically
- **Execution Limits**: Subject to GitHub Actions usage limits and timeouts
- **Limited Environment**: Less control over build environment compared to self-hosted runners
- **YAML Complexity**: Complex workflows can become difficult to read and maintain

## Implementation Details

### Workflow Triggers
- **init.yml**: `repository_dispatch` event triggered by repository creation
- **sync.yml**: Scheduled (daily) + manual `workflow_dispatch` - creates tracking issues with duplicate prevention
- **cascade.yml**: Manual `workflow_dispatch` (human-triggered) - updates issue lifecycle
- **cascade-monitor.yml**: Scheduled (6 hours) + manual `workflow_dispatch` - safety net
- **validate.yml**: PR events (opened, synchronize, reopened)
- **build.yml**: Push to feature branches and PR events
- **release.yml**: Push to main branch with conventional commit messages

### Security Considerations
- **Secrets Management**: Use GitHub secrets for API keys and tokens
- **Token Permissions**: Minimal required permissions for each workflow
- **Branch Protection**: Workflows enforce branch protection rules
- **Security Scanning**: Integrated Trivy scanning for vulnerabilities

### Composite Actions
Extract common patterns into reusable composite actions:
- **pr-status**: Update PR status with validation results
- **java-build**: Standardized Java/Maven build process
- **java-build-status**: Report build status with coverage

### Error Handling
- **Graceful Degradation**: Workflows continue even if optional steps fail
- **Clear Error Messages**: Detailed error reporting for debugging
- **Issue Lifecycle Tracking**: Comprehensive issue tracking for cascade state management
- **Human-Required Labels**: Failed workflows create issues with `human-required` labels
- **Safety Net Recovery**: Monitor workflow detects and recovers from missed triggers
- **Retry Logic**: Automatic retry for transient failures

## Success Criteria
- Repository initialization completes successfully within 5 minutes
- Upstream synchronization runs reliably on schedule with issue tracking and duplicate prevention
- 90%+ of sync merges followed by manual cascade triggers within 2 hours
- Issue lifecycle tracking provides complete audit trail for 95%+ of cascades
- Build workflows complete within 15 minutes for typical projects
- Failed workflows create actionable issues for team resolution
- Safety net detects 100% of missed cascade triggers within 6 hours
- Workflows are maintainable by team members without GitHub Actions expertise
- Security scanning catches vulnerabilities before they reach main branch

## Related Decisions

- [ADR-029: GitHub App Authentication Strategy](029-github-app-authentication-strategy.md) - Authentication mechanism for workflow automation

---

[← ADR-001](001-three-branch-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-003 →](003-template-repository-pattern.md)
