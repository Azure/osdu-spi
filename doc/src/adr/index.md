# Architecture Decision Records

This catalog documents the architectural choices that shape the OSDU SPI Fork Management system. Each ADR captures the context, rationale, and consequences of significant design choices that enable automated management of long-lived upstream forks.

!!! info "Impact Levels"
    **:material-star: Critical** - Fundamental to system operation; changes require careful migration planning

    **:material-trending-up: High** - Significant workflow effects; changes affect multiple components

    **:material-minus: Medium** - Localized improvements; changes have bounded effects

## Catalog

### :material-layers: Foundation & Core Architecture

*"What are the fundamental design choices?"*

Foundation decisions that define the system's structure and approach:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [001](001-three-branch-strategy.md) | **Three-Branch Strategy** | :material-star: Critical | :material-check-circle: Accepted |
| [002](002-github-actions-automation.md) | **GitHub Actions Automation** | :material-star: Critical | :material-check-circle: Accepted |
| [003](003-template-repository-pattern.md) | **Template Repository Pattern** | :material-star: Critical | :material-check-circle: Accepted |

### :material-rocket-launch-outline: Repository Initialization & Setup

*"How do I create and configure a new fork?"*

Decisions governing repository initialization, configuration, and security setup:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [006](006-two-workflow-initialization.md) | **Two-Workflow Initialization** | :material-trending-up: High | :material-check-circle: Accepted |
| [007](007-initialization-workflow-bootstrap.md) | **Workflow Bootstrap Pattern** | :material-minus: Medium | :material-check-circle: Accepted |
| [008](008-centralized-label-management.md) | **Centralized Label Management** | :material-minus: Medium | :material-check-circle: Accepted |
| [016](016-initialization-security-handling.md) | **Initialization Security Handling** | :material-minus: Medium | :material-check-circle: Accepted |
| [017](017-mcp-server-integration-pattern.md) | **MCP Server Integration** | :material-minus: Medium | :material-check-circle: Accepted |

### :material-sync: Upstream Synchronization & Integration

*"How do I keep my fork in sync with upstream?"*

Decisions for synchronizing with upstream repositories and integrating changes:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [005](005-conflict-management.md) | **Conflict Management Strategy** | :material-star: Critical | :material-check-circle: Accepted |
| [009](009-asymmetric-cascade-review-strategy.md) | **Asymmetric Cascade Review** | :material-minus: Medium | :material-check-circle: Accepted |
| [019](019-cascade-monitor-pattern.md) | **Cascade Monitor Pattern** | :material-trending-up: High | :material-check-circle: Accepted |
| [021](021-pull-request-target-trigger-pattern.md) | **Pull Request Target Pattern** | :material-minus: Medium | :material-check-circle: Accepted |
| [023](023-meta-commit-strategy-for-release-please.md) | **Meta Commit Strategy** | :material-trending-up: High | :material-check-circle: Accepted |
| [024](024-sync-workflow-duplicate-prevention-architecture.md) | **Duplicate Prevention Architecture** | :material-minus: Medium | :material-check-circle: Accepted |

### :material-label-outline: State Management & Tracking

*"How do I track progress and workflow state?"*

Decisions for managing workflow state and tracking lifecycle:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [020](020-human-required-label-strategy.md) | **Human-Required Label Strategy** | :material-trending-up: High | :material-check-circle: Accepted |
| [022](022-issue-lifecycle-tracking-pattern.md) | **Issue Lifecycle Tracking** | :material-minus: Medium | :material-check-circle: Accepted |

### :material-hammer-wrench: Build, Test & Dependencies

*"How do I build, test, and maintain dependencies?"*

Build architecture, dependency management, and documentation:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [025](025-java-maven-build-architecture.md) | **Java/Maven Build Architecture** | :material-trending-up: High | :material-check-circle: Accepted |
| [026](026-dependabot-security-update-strategy.md) | **Dependabot Security Updates** | :material-minus: Medium | :material-check-circle: Accepted |
| [027](027-documentation-generation-strategy.md) | **Documentation Generation** | :material-minus: Medium | :material-check-circle: Accepted |

### :material-package-variant: Release Management

*"How do releases get created and published?"*

Version management and release automation:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [004](004-release-please-versioning.md) | **Release Please Versioning** | :material-trending-up: High | :material-check-circle: Accepted |

### :material-update: Template Maintenance & Evolution

*"How do fork repositories stay updated with template improvements?"*

Decisions for propagating template updates to fork repositories:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [011](011-configuration-driven-template-sync.md) | **Configuration-Driven Sync** | :material-trending-up: High | :material-check-circle: Accepted |
| [012](012-template-update-propagation-strategy.md) | **Template Update Propagation** | :material-trending-up: High | :material-check-circle: Accepted |
| [018](018-fork-resources-staging-pattern.md) | **Fork-Resources Staging** | :material-minus: Medium | :material-check-circle: Accepted |
| [031](031-template-sync-duplicate-prevention.md) | **Template Sync Duplicate Prevention** | :material-minus: Medium | :material-check-circle: Accepted |

### :material-cog-outline: Workflow Infrastructure & Patterns

*"What are the reusable building blocks?"*

Technical patterns and infrastructure for workflow implementation:

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| [010](010-yaml-safe-shell-scripting.md) | **YAML-Safe Shell Scripting** | :material-minus: Medium | :material-check-circle: Accepted |
| [013](013-reusable-github-actions-pattern.md) | **Reusable GitHub Actions** | :material-minus: Medium | :material-check-circle: Accepted |
| [014](014-ai-enhanced-development-workflow.md) | **AI-Enhanced Workflows** | :material-trending-up: High | :material-check-circle: Accepted |
| [015](015-template-workflows-separation-pattern.md) | **Template-Workflows Separation** | :material-minus: Medium | :material-check-circle: Accepted |
| [028](028-workflow-script-extraction-pattern.md) | **Workflow Script Extraction** | :material-minus: Medium | :material-check-circle: Accepted |
| [029](029-github-app-authentication-strategy.md) | **GitHub App Authentication** | :material-trending-up: High | :material-check-circle: Accepted |
| [030](030-codeql-summary-job-pattern.md) | **CodeQL Summary Job Pattern** | :material-trending-up: High | :material-check-circle: Accepted |

## Navigation Tips

### Finding Relevant ADRs

**By Workflow Task**: Use the question-based categories above to find ADRs related to specific activities (initialization, synchronization, build, release, etc.).

**By Impact Level**: Focus on :material-star: Critical and :material-trending-up: High Impact ADRs when understanding core system behavior or planning significant changes.

**By Category**: Navigate to specific sections when troubleshooting issues in particular workflow areas.

### Understanding Context

Most ADRs reference related decisions. Follow the cross-reference links to understand how decisions build upon each other and why certain patterns evolved.

---

*For insights on lessons learned and architectural principles, see [Learnings](learnings.md).*
