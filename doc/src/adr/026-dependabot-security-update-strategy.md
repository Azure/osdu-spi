# ADR-026: Dependabot Security Update Strategy

## Status
**Accepted** - 2025-10-01
**Updated** - 2025-10-24 (Separation of Concerns Architecture)
**Updated** - 2025-10-28 (Removed pip/doc from template to prevent fork caching issues)
**Updated** - 2025-12-19 (Changed Maven schedule from weekly to daily for faster rebasing)

## Context

Fork repositories managing OSDU services face unique challenges with dependency management:

1. **Security Vulnerabilities**: Dependencies need timely security updates to prevent exploits
2. **Upstream Compatibility**: Updates must not break compatibility with upstream OSDU
3. **Validation Requirements**: All dependency updates need thorough testing before merge
4. **Update Frequency**: Balance between security responsiveness and stability
5. **Fork-Specific Dependencies**: Local enhancements may have additional dependencies
6. **Engineering System Updates**: Workflows and actions maintained separately from application code

GitHub's Dependabot provides automated dependency updates, but the fork management template needed a strategy that:
- Ensures security updates are applied promptly
- Maintains compatibility with the three-branch strategy
- Provides appropriate validation for different update types
- Handles both upstream and fork-specific dependencies
- **Separates platform concerns (workflows) from application concerns (code dependencies)**
- **Eliminates race conditions during fork initialization**

## Decision

Implement a **Separation of Concerns Dependabot Strategy** with:

1. **Template Owns Engineering System**: Template repository monitors `.github` (workflows, actions) and `doc` (documentation)
2. **Forks Own Application Code**: Fork repositories monitor Maven dependencies ONLY
3. **Template Sync Propagates Platform Updates**: Engineering system updates flow via `sync-template` workflow
4. **Grouped Updates**: Related dependencies updated together to reduce PR noise
5. **Conservative Update Policy**: Patch and minor updates only, major versions require manual review
6. **No Duplicate PRs**: Forks never scan `.github`, eliminating race conditions and duplicate updates

## Rationale

### Security-First Approach

1. **Vulnerability Mitigation**: Security updates applied within 48 hours of disclosure
2. **Automated Detection**: GitHub Security Advisory database integration
3. **Priority Handling**: Security PRs labeled and prioritized appropriately
4. **Compliance Requirements**: Meet enterprise security update SLAs

### Controlled Update Strategy

1. **Stability Focus**: Conservative update policy prevents breaking changes
2. **Validation Gates**: All updates must pass build, test, and integration checks
3. **Grouped Updates**: Reduces PR proliferation and review overhead
4. **Manual Major Versions**: Breaking changes require human review and testing

### Auto-Rebase Strategy

Dependabot automatically rebases open PRs when:
1. The scheduled daily check runs at 09:00 UTC
2. Conflicts are detected with the target branch
3. A closed PR is reopened

**Why Daily Schedule**: A weekly schedule meant PRs could become stale for up to 7 days before rebasing. With multiple developers merging changes to `pom.xml`, Dependabot PRs often had outdated dependency versions. The daily schedule ensures PRs are rebased within 24 hours of any conflicting merge to main.

**Manual Rebase**: Use `@dependabot rebase` comment on any PR to trigger immediate rebase.

## Alternatives Considered

### 1. Disable Dependabot Entirely
- **Pros**: No automated PRs, full manual control
- **Cons**: Miss critical security updates, increased security risk
- **Decision**: Rejected - Security risk too high

### 2. Aggressive Update Strategy
- **Pros**: Always latest versions, newest features
- **Cons**: Frequent breaks, incompatibility with upstream OSDU
- **Decision**: Rejected - Stability more important than latest features

### 3. Security-Only Updates
- **Pros**: Minimal changes, only critical updates
- **Cons**: Miss important bug fixes, technical debt accumulation
- **Decision**: Rejected - Need balance between security and maintenance

### 4. Manual Security Monitoring
- **Pros**: Human judgment for each update
- **Cons**: Slow response time, human error, doesn't scale
- **Decision**: Rejected - Automation essential for timely updates

## Implementation Details

### Dependabot Configuration

**Template Repository** (`.github/dependabot.yml`):
```yaml
version: 2
updates:
  # Engineering System - Template Responsibility
  - package-ecosystem: "github-actions"
    directory: "/.github"  # Monitors ALL .github subdirectories recursively
    schedule:
      interval: "daily"
      time: "08:00"
    groups:
      github-actions:
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"

  # Note: pip/doc ecosystem REMOVED as of 2025-10-28
  # Reason: Forks inherit this config momentarily before deploy-fork-resources.sh runs,
  # causing Dependabot to cache the pip/doc ecosystem even after it's replaced with
  # Maven-only config. Since /doc is removed during fork initialization, Dependabot
  # fails trying to scan a non-existent directory.
```

**Fork Repositories** (`.github/fork-resources/dependabot.yml` → `.github/dependabot.yml`):
```yaml
version: 2
updates:
  # NO GitHub Actions monitoring - Receives via sync-template!

  # Maven Dependencies - Application Code Only
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "daily"
      time: "09:00"
    groups:
      spring:
        patterns:
          - "org.springframework*"
        update-types:
          - "patch"
    # Additional Maven configs for /<service>-core and /provider/<service>-azure
```

### Validation Workflow

```yaml
# dependabot-validation.yml
name: Dependabot Validation
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  validate:
    if: github.actor == 'dependabot[bot]'
    steps:
      - Auto-approve security updates
      - Run comprehensive test suite
      - Check for breaking changes
      - Validate against upstream OSDU
```

### Update Flow Architecture

```
Template Repository (azure/osdu-spi):
  Day 1 08:00 → Dependabot scans /.github
             → Finds actions/checkout@v4 → v5
             → Creates PR in template
  Day 1 10:00 → Platform team merges PR
  Day 2 08:00 → sync-template workflow runs
             → Creates PRs in all forks with updated workflows

Fork Repositories (danielscholl-osdu/*):
  Day 2 08:00 → Receive sync-template PR with workflow updates
             → Review and merge (engineering system updates)
  Daily 09:00 → Dependabot scans Maven dependencies
             → Creates PRs for Spring Boot, Jackson, etc.
             → Rebases open PRs when conflicts detected
             → NO GitHub Actions scanning (eliminates duplicates)
```

### Update Groups

| Repository | Ecosystem | Update Frequency | Managed By |
|------------|-----------|------------------|------------|
| **Template** | GitHub Actions | Daily | Template Dependabot |
| **Template** | Python/pip | Daily | Template Dependabot |
| **Forks** | Maven (root) | Daily | Fork Dependabot |
| **Forks** | Maven (core) | Daily | Fork Dependabot |
| **Forks** | Maven (provider) | Daily | Fork Dependabot |
| **Forks** | GitHub Actions | N/A | Template sync-template |

### Label Strategy

- `dependencies` - All Dependabot PRs
- `security` - Security-related updates
- `auto-merge` - Safe to merge automatically
- `needs-review` - Requires human review
- `breaking-change` - Potentially breaking update

## Consequences

### Positive
- **Improved Security Posture**: Vulnerabilities patched within 48 hours via template
- **Eliminated Race Conditions**: Forks don't scan `.github`, no timing issues during init
- **No Duplicate PRs**: Single source of truth for engineering system updates
- **Clear Separation of Concerns**: Template owns platform, forks own application code
- **Reduced Manual Work**: Automated dependency updates save developer time
- **Scalable Architecture**: 1 template update → N fork updates automatically
- **Consistent Validation**: All updates go through same validation process
- **Audit Trail**: Complete history of dependency updates in GitHub
- **OSDU Compatibility**: Conservative approach maintains upstream compatibility

### Negative
- **PR Noise**: Regular automated PRs require attention
- **Validation Overhead**: All updates require CI/CD resources
- **Potential Conflicts**: Updates may conflict with local modifications
- **Template Dependency**: Forks rely on template for workflow/action updates

### Neutral
- **GitHub Dependency**: Relies on GitHub's Dependabot service
- **Update Lag**: Conservative strategy means not always latest versions
- **Unified Daily Schedule**: Both engineering system and application code update daily

## Success Criteria

- Security vulnerabilities patched within 48 hours of disclosure
- < 10 open Dependabot PRs at any time
- 95% of security updates auto-merge successfully
- Zero breaking changes from automated updates
- Build success rate > 90% for Dependabot PRs
- Clear audit trail of all dependency updates

## Monitoring and Metrics

### Key Metrics
- **Time to Patch**: Hours from CVE disclosure to PR merge
- **PR Success Rate**: Percentage of Dependabot PRs that pass validation
- **Auto-merge Rate**: Percentage of PRs merged automatically
- **Breaking Change Rate**: Frequency of updates causing failures

### Alerts
- Security updates pending > 48 hours
- Dependabot PRs failing repeatedly
- Critical vulnerabilities detected
- Update limit reached (10 PRs)

## Integration Points

### With Build System (ADR-025)
- Dependabot updates trigger Maven builds
- JaCoCo coverage must remain above thresholds
- Community repository dependencies validated

### With Validation Workflow
- Comprehensive testing of dependency updates
- Integration testing with upstream OSDU
- Automated approval for safe updates

### With Release Management (ADR-004)
- Dependency updates reflected in release notes
- Security patches trigger patch releases
- Changelog includes dependency updates

## Future Evolution

### Potential Enhancements
1. **Smart Grouping**: ML-based dependency grouping for optimal updates
2. **Risk Scoring**: Automated risk assessment for updates
3. **Rollback Automation**: Automatic rollback of problematic updates
4. **Custom Security Policies**: Organization-specific security requirements
5. **Cross-Repository Coordination**: Synchronized updates across fork family

### Integration Opportunities
- Integration with security scanning tools
- Custom validation for OSDU-specific dependencies
- Automated compatibility testing with upstream
- Security update notifications to Slack/Teams

## Related ADRs

- [ADR-002: GitHub Actions-Based Automation Architecture](002-github-actions-automation.md) - Automation foundation
- [ADR-016: Initialization Security Handling](016-initialization-security-handling.md) - Security considerations
- [ADR-025: Java/Maven Build Architecture](025-java-maven-build-architecture.md) - Build system integration

## References

- [GitHub Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [GitHub Security Advisories](https://github.com/advisories)
- [OWASP Dependency Check](https://owasp.org/www-project-dependency-check/)
- [Maven Dependency Management](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html)
---

[← ADR-025](025-java-maven-build-architecture.md) | :material-arrow-up: [Catalog](index.md) | [ADR-027 →](027-documentation-generation-strategy.md)
