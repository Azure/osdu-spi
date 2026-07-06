# ADR Catalog

> **Note**: This file provides a quick-reference table format of all ADRs with expandable summaries. It is specifically designed for AI agents and automated tools that need rapid access to ADR metadata and high-level context. For human-readable navigation with categorization and search, see [index.md](index.md).

Architecture Decision Records for Fork Management Template

## Index

| ID  | Title                                      | Details |
| --- | ------------------------------------------ | ------- |
| 001 | Three-Branch Fork Management Strategy      | [ADR-001](001-three-branch-strategy.md) |
| 002 | GitHub Actions-Based Automation            | [ADR-002](002-github-actions-automation.md) |
| 003 | Template Repository Pattern                | [ADR-003](003-template-repository-pattern.md) |
| 004 | Release Please for Version Management      | [ADR-004](004-release-please-versioning.md) |
| 005 | Automated Conflict Management Strategy     | [ADR-005](005-conflict-management.md) |
| 006 | Two-Workflow Initialization Pattern        | [ADR-006](006-two-workflow-initialization.md) |
| 007 | Initialization Workflow Bootstrap Pattern  | [ADR-007](007-initialization-workflow-bootstrap.md) |
| 008 | Centralized Label Management Strategy      | [ADR-008](008-centralized-label-management.md) |
| 009 | Asymmetric Cascade Review Strategy         | [ADR-009](009-asymmetric-cascade-review-strategy.md) |
| 010 | YAML-Safe Shell Scripting in GitHub Actions | [ADR-010](010-yaml-safe-shell-scripting.md) |
| 011 | Configuration-Driven Template Synchronization | [ADR-011](011-configuration-driven-template-sync.md) |
| 012 | Template Update Propagation Strategy       | [ADR-012](012-template-update-propagation-strategy.md) |
| 013 | Reusable GitHub Actions Pattern for PR Creation | [ADR-013](013-reusable-github-actions-pattern.md) |
| 014 | AI-Enhanced Development Workflow Integration | [ADR-014](014-ai-enhanced-development-workflow.md) |
| 015 | Template-Workflows Separation Pattern      | [ADR-015](015-template-workflows-separation-pattern.md) |
| 016 | Initialization Security Handling           | [ADR-016](016-initialization-security-handling.md) |
| 017 | MCP Server Integration Pattern             | [ADR-017](017-mcp-server-integration-pattern.md) |
| 018 | Fork-Resources Staging Pattern             | [ADR-018](018-fork-resources-staging-pattern.md) |
| 019 | Cascade Monitor Pattern                    | [ADR-019](019-cascade-monitor-pattern.md) |
| 020 | Human-Required Label Strategy              | [ADR-020](020-human-required-label-strategy.md) |
| 021 | Pull Request Target Trigger Pattern        | [ADR-021](021-pull-request-target-trigger-pattern.md) |
| 022 | Issue Lifecycle Tracking Pattern           | [ADR-022](022-issue-lifecycle-tracking-pattern.md) |
| 023 | Meta Commit Strategy for Release Please    | [ADR-023](023-meta-commit-strategy-for-release-please.md) |
| 024 | Sync Workflow Duplicate Prevention Architecture | [ADR-024](024-sync-workflow-duplicate-prevention-architecture.md) |
| 025 | Java/Maven Build Architecture              | [ADR-025](025-java-maven-build-architecture.md) |
| 026 | Dependabot Security Update Strategy        | [ADR-026](026-dependabot-security-update-strategy.md) |
| 027 | Documentation Generation Strategy with MkDocs | [ADR-027](027-documentation-generation-strategy.md) |
| 028 | Workflow Script Extraction Pattern         | [ADR-028](028-workflow-script-extraction-pattern.md) |
| 029 | GitHub App Authentication Strategy         | [ADR-029](029-github-app-authentication-strategy.md) |
| 030 | CodeQL Summary Job Pattern                 | [ADR-030](030-codeql-summary-job-pattern.md) |
| 031 | Template Sync Duplicate Prevention Pattern | [ADR-031](031-template-sync-duplicate-prevention.md) |
| 032 | CI/CD Deploy Loop via Suspended Flux       | [ADR-032](032-cicd-deploy-loop-via-suspended-flux.md) |
| 033 | GHCR as Service Image Registry             | [ADR-033](033-ghcr-as-service-image-registry.md) |
| 034 | Federated Identity for Actions to Azure    | [ADR-034](034-federated-identity-actions-to-azure.md) |
| 035 | Azure-Only Maven Profile Restriction       | [ADR-035](035-azure-only-maven-profile.md) |
| 036 | Workflow Trust Boundaries for CI/CD        | [ADR-036](036-workflow-trust-boundaries.md) |
| 037 | Engineering System Owns the Canonical Service Dockerfile | [ADR-037](037-engineering-system-owns-service-dockerfile.md) |
| 038 | Defer Extra-File Dockerfile Support for Core Service Onboarding | [ADR-038](038-defer-extra-file-dockerfile-support.md) |

## Overview

These Architecture Decision Records document the key design choices made in the Fork Management Template project. Each ADR explains the context, decision, rationale, and consequences of significant architectural choices that enable automated management of long-lived forks of upstream repositories.

## Quick Reference

### Core Architecture Decisions

**Three-Branch Strategy (ADR-001)**
- `main`: Stable production branch
- `fork_upstream`: Tracks upstream changes
- `fork_integration`: Conflict resolution workspace

**Automation Framework (ADR-002)**
- GitHub Actions for all workflow automation (init, sync, cascade, validate, build, release)
- Issue lifecycle tracking and duplicate prevention for upstream sync
- Modular workflow design with separation of concerns

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
- Daily automated template updates via `template-sync.yml`
- AI-enhanced PR descriptions and human-centric manual cascade instructions
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
- Human-centric cascade: manual triggering as primary path, monitor as safety net
- Issue lifecycle tracking with label-based state management
- Health monitoring detects missed triggers and conflict escalation
- Explicit human control over integration timing with clear instructions

**Human-Required Label Strategy (ADR-020)**
- Label-based task management replaces unreliable assignee approach
- `human-required` label marks items needing attention without username resolution
- Team-flexible filtering and priority systems via label combinations
- Works across all repository instances without GraphQL API failures

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
- Preserves complete upstream commit history while enabling automated versioning
- AIPR analyzes commit ranges to generate conventional meta commits
- Fallback to conservative `feat:` commits when AI unavailable
- Solves conflict between upstream non-conventional commits and Release Please requirements

**Sync Workflow Duplicate Prevention Architecture (ADR-024)**
- State-based duplicate detection using git config persistence
- Smart decision matrix for handling all duplicate sync scenarios
- Branch update strategy maintains human workflow continuity
- Automatic cleanup of abandoned sync branches and state management

**Java/Maven Build Architecture (ADR-025)**
- Java 17 Temurin as standard runtime with Maven 3.9+ build tool
- JaCoCo coverage reporting and GitLab Maven repository integration
- Reusable GitHub Actions for consistent build implementation
- Zero-configuration support for standard OSDU Java projects

**Dependabot Security Update Strategy (ADR-026)**
- Security-first configuration with 48-hour patch SLA
- Grouped dependency updates to reduce PR noise
- Conservative update policy for stability
- Automated validation and auto-merge for safe updates

**Documentation Generation with MkDocs (ADR-027)**
- MkDocs Material theme for professional documentation site
- Automatic publishing to GitHub Pages
- Full-text search and mobile-responsive design
- ADRs automatically included in documentation

**Workflow Script Extraction Pattern (ADR-028)**
- Extract embedded bash scripts to `.github/actions/` for local testing
- Composite action wrappers enable parameter passing and reuse
- Leverages existing sync infrastructure for propagation to forks
- 40% reduction in workflow file sizes with eliminated duplication

**GitHub App Authentication Strategy (ADR-029)**
- Replace PATs with GitHub Apps for workflow automation
- Short-lived tokens (1 hour) vs long-lived PATs (90+ days)
- Microsoft-compliant authentication eliminating PAT dependency
- Centralized management not tied to individual employees
- Required for release automation and repository initialization under org security policies

**CodeQL Summary Job Pattern (ADR-030)**
- Summary job aggregates analysis results for required status checks
- Enables branch protection rules with CodeQL regardless of language detection
- Fails when zero analyzable languages detected for real repository issues
- Consolidates multiple language analysis jobs into single mergeable status check

**Template Sync Duplicate Prevention Pattern (ADR-031)**
- Inline PR detection prevents duplicate template-sync PRs
- Same architectural pattern as upstream sync (ADR-024) with simpler implementation
- Label-based tracking with `template-sync` label for PR identification
- Branch reuse with force-push when template advances
- Eliminates daily accumulation of open template-sync PRs

**CI/CD Deploy Loop via Suspended Flux (ADR-032)**
- Shared `osdu-spi-stack` cluster runs with all Flux Kustomizations permanently suspended (CI steady state)
- Per-PR deploy jobs `kubectl set image` by immutable digest; a pre-flight asserts Flux is still suspended
- Flux is resumed only during a planned baseline refresh; `K8S_DEPLOYMENT_NAME`/`K8S_CONTAINER_NAME` insulate CI from chart naming

**GHCR as Service Image Registry (ADR-033)**
- Public GHCR for SPI service CI/test artifacts consumed by the `osdu-spi-stack` AKS cluster
- Push via `GITHUB_TOKEN`, pull anonymously from AKS — no `imagePullSecret`
- MCR migration deferred; ACR/MCR swap is localized to the visibility helper, private-GHCR fallback is broader-touch

**Federated Identity for Actions to Azure (ADR-034)**
- One User-Assigned Managed Identity per service fork; GitHub Actions auth via OIDC `azure/login` (no static `AZURE_CREDENTIALS`)
- Handoff contract is three repo secrets (`AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID`); `AZURE_CLIENT_ID` is also a variable for `if:`/diagnostics
- `oidc-smoke-test.yml` validates each federated-credential subject in isolation

**Azure-Only Maven Profile Restriction (ADR-035)**
- CI builds the Azure profile set with a hardcoded default of `core,azure` (correct for 9/10 forks); `core` is `activeByDefault`, so a bare `-P azure` would drop it
- `MAVEN_PROFILE` is an optional per-fork override (`${{ vars.MAVEN_PROFILE || 'core,azure' }}`) for forks that deviate (e.g. `indexer-queue`); never emits a bare `-P`
- Faster, Azure-relevant CI signal with zero per-fork config in the common case; non-Azure provider regressions are intentionally out of the default path

**Workflow Trust Boundaries for CI/CD (ADR-036)**
- Credential-bearing jobs (`docker-push`, `deploy`, `integration-test`) run only in trusted event contexts
- Canonical `if:` gate excludes `dependabot[bot]` and `pull_request_target` and permits only internal PR heads
- External-fork PRs lose deploy/test signal by design to protect the cluster federated identity

**Engineering System Owns the Canonical Service Dockerfile (ADR-037)**
- One canonical `build/Dockerfile` lives in the template and syncs to every fork (`sync-config.json` `directories[]`); services do not supply their own
- Mirrors the OSDU community `service-base-image/java/Dockerfile`: `COPY ${JAR_FILE} /app.jar` (no Maven in the image build); the JAR is the one our `java-build` job compiled from source, never a prebuilt artifact from OSDU's Maven registry
- `JAR_FILE` defaults to `provider/<SERVICE_NAME>-azure/target/*-spring-boot.jar` (override via the `SERVICE_TARGET_JAR` repository variable); `BASE_IMAGE` is an `ARG` defaulting to OSDU `alpine-zulu17` so a later registry pivot is a one-line swap

**Defer Extra-File Dockerfile Support for Core Service Onboarding (ADR-038)**
- No Dockerfile or `docker-build` action change is required for the immediate 10 core service onboarding wave
- ADME `OPTIONAL_FILES` usage was found only in reference services (`crs-catalog`, `crs-conversion`, `unit`), not Partition, Entitlements, or the 10 core service set
- Extra-file image support should be deferred until reference-service onboarding and implemented with validated paths, not a raw Docker build-arg passthrough
