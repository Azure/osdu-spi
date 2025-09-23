# ADR Catalog

Architecture Decision Records for Fork Management Template

## Index

| ID  | Title                                      | Status   | Date       | Details |
| --- | ------------------------------------------ | -------- | ---------- | ------- |
| 001 | Three-Branch Fork Management Strategy      | Accepted | 2025-05-28 | [ADR-001](001-three-branch-strategy.md) |
| 002 | GitHub Actions-Based Automation            | Accepted | 2025-05-28 | [ADR-002](002-github-actions-automation.md) |
| 003 | Template Repository Pattern                | Accepted | 2025-05-28 | [ADR-003](003-template-repository-pattern.md) |
| 004 | Release Please for Version Management      | Accepted | 2025-05-28 | [ADR-004](004-release-please-versioning.md) |
| 005 | Automated Conflict Management Strategy     | Accepted | 2025-05-28 | [ADR-005](005-conflict-management.md) |
| 006 | Two-Workflow Initialization Pattern        | Accepted | 2025-05-28 | [ADR-006](006-two-workflow-initialization.md) |
| 007 | Initialization Workflow Bootstrap Pattern  | Proposed | 2025-05-29 | [ADR-007](007-initialization-workflow-bootstrap.md) |
| 008 | Centralized Label Management Strategy      | Accepted | 2025-06-03 | [ADR-008](008-centralized-label-management.md) |
| 009 | Asymmetric Cascade Review Strategy         | Accepted | 2025-06-03 | [ADR-009](009-asymmetric-cascade-review-strategy.md) |
| 010 | YAML-Safe Shell Scripting in GitHub Actions | Accepted | 2025-06-03 | [ADR-010](010-yaml-safe-shell-scripting.md) |
| 011 | Configuration-Driven Template Synchronization | Accepted | 2025-06-04 | [ADR-011](011-configuration-driven-template-sync.md) |
| 012 | Template Update Propagation Strategy | Accepted | 2025-06-04 | [ADR-012](012-template-update-propagation-strategy.md) |
| 013 | Reusable GitHub Actions Pattern for PR Creation | Accepted | 2025-06-04 | [ADR-013](013-reusable-github-actions-pattern.md) |
| 014 | AI-Enhanced Development Workflow Integration | Accepted | 2025-06-04 | [ADR-014](014-ai-enhanced-development-workflow.md) |
| 015 | Template-Workflows Separation Pattern | Accepted | 2025-06-04 | [ADR-015](015-template-workflows-separation-pattern.md) |
| 016 | Initialization Security Handling | Accepted | 2025-01-06 | [ADR-016](016-initialization-security-handling.md) |
| 017 | MCP Server Integration Pattern | Accepted | 2025-01-07 | [ADR-017](017-mcp-server-integration-pattern.md) |
| 018 | Fork-Resources Staging Pattern | Accepted | 2025-01-09 | [ADR-018](018-fork-resources-staging-pattern.md) |
| 019 | Cascade Monitor Pattern | Accepted | 2025-06-20 | [ADR-019](019-cascade-monitor-pattern.md) |
| 020 | Human-Required Label Strategy | Accepted | 2025-06-20 | [ADR-020](020-human-required-label-strategy.md) |
| 021 | Pull Request Target Trigger Pattern | Accepted | 2025-06-24 | [ADR-021](021-pull-request-target-trigger-pattern.md) |
| 022 | Issue Lifecycle Tracking Pattern | Accepted | 2025-06-25 | [ADR-022](022-issue-lifecycle-tracking-pattern.md) |
| 023 | Meta Commit Strategy for Release Please | Accepted | 2025-06-30 | [ADR-023](023-meta-commit-strategy-for-release-please.md) |
| 024 | Sync Workflow Duplicate Prevention Architecture | Accepted | 2025-07-03 | [ADR-024](024-sync-workflow-duplicate-prevention-architecture.md) |
| 025 | GitLab Cross-Platform Integration Strategy for OSDU | Accepted | 2025-07-21 | [ADR-025](025-gitlab-cross-platform-integration-strategy.md) |

## Overview

These Architecture Decision Records document the key design choices made in the Fork Management Template project. Each ADR explains the context, decision, rationale, and consequences of significant architectural choices that enable automated management of long-lived forks of upstream repositories.

## Quick Reference

### Core Architecture Decisions

**Three-Branch Strategy (ADR-001)**
- `main`: Stable production branch
- `fork_upstream`: Tracks upstream changes
- `fork_integration`: Conflict resolution workspace

**Automation Framework (ADR-002)**
- GitHub Actions for all workflow automation
- Self-configuring template repository pattern
- Scheduled and event-driven synchronization

**Two-Workflow Initialization (ADR-006)**
- Separated user interaction from repository setup
- Issue-driven configuration with progress updates
- Simplified state management and error handling

**Workflow Bootstrap Pattern (ADR-007)**
- Self-updating initialization workflows
- Ensures latest fixes are always available
- Solves the template version bootstrap problem

**Centralized Label Management (ADR-008)**
- All labels defined in `.github/labels.json`
- Created during repository initialization
- Single source of truth for label definitions

**Version Management (ADR-004)**
- Release Please with Conventional Commits
- Automated semantic versioning
- Upstream version reference tracking

**Configuration-Driven Template Sync (ADR-011)**
- `.github/sync-config.json` defines what files get synced
- Selective synchronization between template and forked repositories
- Automated cleanup of template-specific content

**Template Update Propagation (ADR-012)**
- Weekly automated template updates via `template-sync.yml`
- AI-enhanced PR descriptions for template changes
- Solves template drift problem for forked repositories

**Reusable GitHub Actions (ADR-013)**
- Custom composite action for AI-enhanced PR creation
- DRY principle for common workflow functionality
- Centralized AI integration with multiple provider support

**AI-Enhanced Workflows (ADR-014)**
- Multi-provider AI support (Azure OpenAI, OpenAI)
- AI-powered security analysis and PR description generation

**Template-Workflows Separation (ADR-015)**
- Clean separation between template development and fork production workflows
- `.github/workflows/` for template development (not copied)
- `.github/template-workflows/` for fork production workflows (copied during init)
- Eliminates workflow pollution in fork repositories

**Initialization Security Handling (ADR-016)**
- Temporarily disables push protection during initialization
- Allows syncing upstream repositories with historical secrets
- Re-enables full security immediately after initialization
- Simple and maintainable approach without complex error handling

**MCP Server Integration Pattern (ADR-017)**
- Automatic MCP server configuration for GitHub Copilot Agent
- Maven MCP Server provides AI-enhanced dependency management
- Configuration stored in fork-resources for template-wide deployment
- Read-only MCP servers for security and Maven Central integration

**Fork-Resources Staging Pattern (ADR-018)**
- `.github/fork-resources/` as staging area for specialized template deployment
- Templates requiring custom deployment logic (issue templates, AI configs, prompts)
- Two-stage deployment: template staging → fork final locations
- Integrates with sync configuration for automatic updates

**Cascade Monitor Pattern (ADR-019)**
- Separates trigger detection from cascade execution
- Event-driven architecture for upstream sync detection
- Health monitoring and conflict escalation
- Robust error handling with fallback mechanisms

**Human-Required Label Strategy (ADR-020)**
- Replaces assignee-based task management with labels
- Eliminates username resolution failures
- Flexible team workflow management
- Works across all repository instances

**Pull Request Target Trigger Pattern (ADR-021)**
- Solves "missing YAML" problem for cascade triggering
- Uses `pull_request_target` to read workflow from main branch
- Single-line change for dramatic reliability improvement
- Maintains same security model as PAT approach

**Issue Lifecycle Tracking Pattern (ADR-022)**
- Comprehensive tracking of cascade state through GitHub issues
- Label-based state management for machine and human readability
- Complete audit trail from upstream sync to production deployment
- Integration with human-centric cascade pattern

**Meta Commit Strategy for Release Please (ADR-023)**
- Preserves complete upstream commit history for debugging and compliance
- AI-generated conventional meta commits drive Release Please versioning
- Robust fallback to conservative `feat:` commits during AI service outages
- Solves upstream non-conventional commit format conflicts

**Sync Workflow Duplicate Prevention Architecture (ADR-024)**
- State-based duplicate detection using git config persistence
- Smart decision matrix for handling all duplicate sync scenarios
- Branch update strategy maintains human workflow continuity
- Automatic cleanup of abandoned sync branches and state management

**GitLab Cross-Platform Integration Strategy (ADR-025)**
- AI-driven GitHub-to-GitLab bridging using Model Context Protocol (MCP) servers
- OSDU-specific GitLab targeting for `community.opengroup.org` integration
- Unified GitLab token authentication for both Maven and API access
- Automated merge request creation with AI-enhanced workflow triggers