# Three-Branch Strategy

The three-branch strategy forms the cornerstone of safe, systematic fork management in the OSDU SPI Fork Management system. This architectural pattern provides controlled integration checkpoints that prevent cascade failures while enabling continuous upstream synchronization.

## Branch Architecture

```mermaid
graph TD
    A[Upstream Repository] --> B[fork_upstream<br/>Filtered Shared Code]
    B --> C[fork_integration<br/>Staging]  
    C --> D[main<br/>Production]
    
    E[Local Development] --> F[Feature Branches]
    F --> D
    
    style A fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    style B fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style C fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style D fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    style E fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    style F fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
```

### Branch Purposes

<div class="grid cards" markdown>

-   :material-source-branch-check:{ .lg .middle } **`main` - Production Branch**

    ---

    Stable production branch containing successfully integrated changes

    - Maximum security with required PR reviews
    - Production-ready shared and fork-owned Azure code
    - Upstream updates arrive through validated release PRs from `fork_integration`
    - Local feature and hotfix branches also merge through reviewed PRs
    - All changes must pass comprehensive validation

</div>

<div class="grid cards" markdown>

-   :material-source-commit:{ .lg .middle } **`fork_upstream` - Generated Upstream Tree**

    ---

    Deterministic upstream-owned tree generated from the upstream tip

    - Keeps shared core, acceptance-test, test-core, POM, documentation, and license content
    - Excludes provider source, `core-plus`, `devops/`, non-Azure tests, and upstream CI files
    - Injects POM references to Azure modules that exist only on the fork-owned branches
    - Halts when new shared content is not classified
    - Filtered from its first generation: initialization generates the branch through the engine, so the fork never carries a verbatim mirror and the Azure trees never enter the merge base

</div>

<div class="grid cards" markdown>

-   :material-source-merge:{ .lg .middle } **`fork_integration` - Integration Workspace**

    ---

    Dedicated space for conflict resolution and comprehensive validation

    - Flexible protection for conflict resolution workflows
    - Combines generated shared code with fork-owned Azure provider and test source
    - Automated merges from `fork_upstream` with conflict resolution
    - Azure POM version stamping plus `core,azure` build and test validation

</div>

## Process Flow

#### **Synchronize**
```mermaid
sequenceDiagram
    participant U as Upstream Repo
    participant FU as fork_upstream
    participant S as Sync Workflow
    participant F as Upstream Filter
    participant H as Human Reviewer
    
    S->>U: Fetch latest changes
    S->>S: Check existing sync PRs and upstream SHA
    S->>F: Generate and verify provider-less tree
    
    alt New upstream changes, no existing PR
        S->>FU: Create sync branch containing generated tree
        activate FU
        S->>S: Generate AI analysis
        S->>S: Create new sync PR and issue
        S->>H: Notify human reviewer
    else Upstream advanced, existing PR open
        S->>FU: Update existing sync branch (force push)
        S->>S: Update PR title and description
        S->>S: Add progress comment to existing issue
        S->>H: Update notification on existing issue
    else Duplicate detected (same upstream SHA)
        S->>S: Keep existing PR and issue unchanged
    else No changes detected
        S->>S: Exit - no action needed
    end
    
    opt Human approval received
        H->>H: Review and approve
        H->>FU: Merge sync branch into fork_upstream
        S->>S: Update issue and PR state
        S->>S: Cleanup completed sync artifacts
        deactivate FU
    end
```

!!! info "Sync State Management"
    The synchronization process tracks the upstream SHA, active PR, and issue state to prevent duplicates. Before creating or updating a sync branch, the upstream filter classifies the upstream tip and halts on unknown shared content. When upstream advances while a PR is open, the existing branch is regenerated and updated.

#### **Integrate**
```mermaid
sequenceDiagram
    participant M as main
    participant FU as fork_upstream
    participant FI as fork_integration
    participant C as Cascade Workflow
    participant H as Human Reviewer
    
    C->>M: Check for local changes
    M->>FI: Merge main → fork_integration
    activate FI
    C->>FU: Check for upstream updates
    FU->>FI: Merge fork_upstream → fork_integration
    C->>FI: Assert Azure trees and stamp POM versions
    C->>FI: Build and test core,azure
    C->>C: Create main PR
    
    alt Validation Conflicts/Failures
        C->>C: Create conflict resolution issue
        C->>H: Notify about conflicts
        H->>FI: Push conflict resolution to fork_integration
    end
    
    C->>FI: Run validation suite
    C->>H: Notify human reviewer
    H->>H: Review and approve
    FI->>M: Merge to main
    deactivate FI
```

#### **Release**
```mermaid
sequenceDiagram
    participant M as main
    participant R as Release Workflow
    participant H as Human Reviewer
    participant DR as Downstream Repo
    
    M->>R: Push to main triggers release
    R->>R: Analyze commits for version bump
    R->>M: Create release branch with CHANGELOG.md
    activate M
    R->>H: Create release PR
    R->>M: Run validation suite
    H->>H: Review and approve
    H->>M: Merge release branch into main
    deactivate M
    R->>R: Create release & tags
    
    alt Downstream Consumption
        DR->>M: Pull desired release tag
    end
```

A downstream repository does not have to stop at pulling release tags. It can be a customer-tier fork running this same three-branch machinery in mirror mode: `fork_upstream` becomes a verbatim mirror of this repository's `main`, the cascade integrates it with the downstream's local work, and contribution PRs flow back through the fork network. See [Fork Tiers](fork_tiers.md) and ADR-039.

## Safety Mechanisms

### Branch Protection Rules

| Protection Setting | :material-source-branch: *main* | :material-source-branch: *fork_upstream* | :material-source-branch: *fork_integration* |
|-------------------|-------|---------------|------------------|
| **Required Reviews** | 1 minimum | Not required | Not required |
| **Status Checks** | `CodeQL`, `🐳 Docker Build` | Not required | Not required |
| **Up-to-date Branch** | Required | Not enforced | Not enforced |
| **Force Push** | Blocked | Allowed | Allowed |
| **Expected Writers** | Reviewed PRs | Sync automation | Cascade and cleanup automation |

### Quality Gates

!!! check "Integration Validation"
    ✓ **Build Verification**: `core,azure` compilation and dependency resolution
    ✓ **Test Execution**: Unit tests plus compile-only validation of the separate Azure testing reactor
    ✓ **Container Validation**: Canonical Dockerfile build on branches that contain the Azure JAR
    ✓ **Security Scanning**: CodeQL reports through its separate workflow

!!! warning "Production Validation"
    ⚠️ **Human Review**: Manual approval for all production changes  
    ⚠️ **Impact Assessment**: Analysis of changes to Azure SPI implementations  
    ⚠️ **Rollback Planning**: Verification of rollback procedures if needed  
    ⚠️ **Documentation**: Change documentation and release notes

## Workflow Benefits

<div class="grid cards" markdown>

-   :material-target:{ .lg .middle } **Conflict Isolation**

    ---

    Merge conflicts are resolved in the dedicated `fork_integration` branch, preventing disruption to the stable `main` branch during resolution.

-   :material-magnify:{ .lg .middle } **Clear Change Attribution**

    ---

    Clear separation between generated upstream-owned shared code and fork-owned Azure implementation changes.

-   :material-shield-account:{ .lg .middle } **Multi-Stage Validation**

    ---

    Multiple review and validation points ensure problematic changes are caught before reaching production systems.

-   :material-history:{ .lg .middle } **Upstream Tracking**

    ---

    Reproducible filtered commits retain upstream history and record the upstream SHA and filter revision.

-   :material-backup-restore:{ .lg .middle } **Rollback Capability**

    ---

    Easy reversion of problematic integrations without losing upstream synchronization state or affecting ongoing development.

-   :material-database:{ .lg .middle } **Branch Preservation**

    ---

    All three branches are permanently preserved, maintaining historical state for analysis and providing continuous availability.

</div>

## Operational Patterns

### Daily Synchronization Cycle

**Automated Processing:**

:material-arrow-right: **Step 1:** Check Upstream - Daily automated check for new upstream changes  
:material-arrow-right: **Step 2:** Filter Transform - Regenerate and verify the upstream-owned tree
:material-arrow-right: **Step 3:** Sync Review - Review and merge the filtered PR to `fork_upstream`
:material-arrow-right: **Step 4:** Cascade - Merge into integration, stamp Azure POMs, and run validation

**Human Intervention Points:**

:material-arrow-right: **Step 1:** Conflict Resolution - Manual resolution when automated merge fails  
:material-arrow-right: **Step 2:** Validation Review - Assessment of test results and security findings  
:material-arrow-right: **Step 3:** Production Approval - Final authorization for changes to reach `main`  
:material-arrow-right: **Step 4:** Release Coordination - Alignment with downstream system requirements

### Emergency Procedures

#### **Upstream Rollback**
If upstream changes cause issues:

1. Identify last known good state in `fork_upstream`
2. Create rollback branch from previous stable point
3. Update `fork_integration` with rollback changes
4. Execute normal validation and approval process

#### **Production Hotfix**
For urgent Azure SPI fixes:

1. Create hotfix branch from current `main`
2. Implement and test fix in isolation
3. Fast-track through integration validation
4. Deploy with minimal upstream integration delay

!!! info "Release Strategy"
    For production deployments, temporary release branches (`release/upstream-YYYYMMDD-HHMMSS`) are created from `fork_integration` to `main`, allowing safe cleanup while preserving the three-branch core architecture.

---