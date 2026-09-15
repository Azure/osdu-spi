# Concepts


A cloud provider running the Open Subsurface Data Universe (OSDU) has to keep two things at once: compatibility with the community code, and its own Service Provider Interface (SPI) implementation. OSDU keeps community standards and cloud-specific code in separate layers. The diagram below shows how Microsoft keeps that separation through a fork:


```mermaid
graph TB
    subgraph Community["OSDU Community Repository - Upstream"]
        Shared["API, Core Code and SPI Interfaces"]
        Seed["Azure Provider and Test Source<br/>Last upstream revision containing them"]
    end

    Shared -->|Filtered sync| Generated["fork_upstream<br/>Shared code and Azure module references<br/>No Azure source"]

    subgraph Fork["Azure Service Fork - fork_integration and main"]
        Core["API and Core Code"] --- Interface["SPI Interfaces"] --- Azure["Fork-owned Azure Provider and Tests"]
    end

    Generated -->|Cascade shared changes| Core
    Seed -.->|Seed once at initialization| Azure

    style Community fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    style Fork fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style Generated fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    style Interface fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style Azure fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
```

The **SPI Interface** (orange) is the code boundary: shared service logic calls an interface implemented by the Azure provider. Source ownership follows a separate boundary. Sync regenerates `fork_upstream` from shared upstream code and injects references to the Azure modules, but excludes the provider implementations themselves.

Upstream plans to remove its Azure implementations. Initialization therefore seeds `provider/<svc>-azure` and `testing/<svc>-test-azure` once, from the newest upstream revision that still contains them. Those trees are then maintained in the service fork on `fork_integration` and `main`. Cascade combines shared changes with that fork-owned source and updates its Maven version wiring. Late upstream fixes to Azure source need an explicit port. See [ADR-038: Upstream Filter Transform and One-Time Azure Seeding](adr/038-upstream-filter-transform.md).

:material-open-source-initiative: **Upstream-Owned Components** include OSDU core interfaces, community-validated business logic, standard data models, and shared tests.

:material-microsoft-azure: **Fork-Owned Components** include the Azure provider and Azure test source, plus the fork's engineering configuration and build machinery.

## The Fork Management Problem

A long-lived fork of an upstream OSDU repository runs into four recurring problems:

<div class="challenge-cards" markdown="1">
  <div class="challenge-card" markdown="1">
:material-merge: **Integration Complexity**

Manual synchronization is slow, and slowest when an upstream change touches an interface the Azure SPI implementation depends on.
  </div>

  <div class="challenge-card" markdown="1">
:material-source-branch-sync: **Divergence Risk**

Local modifications drift from upstream over time, and each sync gets harder than the last.
  </div>

  <div class="challenge-card" markdown="1">
:material-block-helper: **Blocking Dependencies**

In a shared tree, a build or test failure in any provider's SPI implementation can block merging changes for every other provider.
  </div>

  <div class="challenge-card" markdown="1">
:material-source-repository-multiple: **Release Coordination**

Without tracking, nobody can say which upstream release a fork version contains.
  </div>
</div>

| Aspect | Manual Fork Management | This System |
|--------|----------------------------|-------------------|
| **Synchronization** | Weekly or monthly, by hand | Daily, as a reviewable PR |
| **Conflict Resolution** | Wherever the merge happened | Isolated in `fork_integration` |
| **Release Coordination** | Tracked by hand, if at all | Correlation tags against upstream releases |
| **Integration Testing** | After conflicts are resolved | At each branch stage |

## The Automation Solution

The system isolates each stage of integration in its own branch. Changes flow through `fork_upstream`, then `fork_integration`, then `main`, with validation at each step, so a failure stops at the stage where it happened.

```mermaid
graph TD
    A[OSDU Community Repository - Upstream]
    A -->|Filtered sync| B
    
    subgraph Azure["Azure SPI Repository"]
        B[fork_upstream<br/>Shared code; no Azure source]
        B --> C[fork_integration<br/>Shared code + fork-owned Azure source]
        C --> D[main<br/>Shared code + fork-owned Azure source]
    end
    
    style A fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    style Azure fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style B fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style C fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style D fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
```

**What the workflows do:**

<div class="workflow-benefits" markdown="1">
  <div class="benefit-card" markdown="1">
:material-sync: **Upstream Synchronization**

- Daily pull of the upstream tip
- Generated from shared upstream code, with Azure module references but no Azure source
- One PR per upstream state, with the commit list in the body
  </div>

  <div class="benefit-card" markdown="1">
:material-source-merge: **Conflict Management**

- Resolution happens in `fork_integration`
- A tracking issue records the conflict and the steps to resolve it
- Build and tests run before the change is offered to `main`
  </div>

  <div class="benefit-card" markdown="1">
:material-tag-multiple: **Release Coordination**

- Correlation tags against upstream versions
- Semantic versions computed from conventional commits
- Changelog generated by Release Please
  </div>
</div>

**The model extends one tier further.** A customer organization can run a true GitHub fork of a service repository through this same machinery in mirror mode: their `fork_upstream` mirrors the service repository's `main` verbatim, they build and release with their own credentials, and proven features return as contribution PRs through the fork network. See [Fork Tiers](architecture/fork_tiers.md).

## Why This Matters

The fork team spends its time on the Azure implementation instead of on merges. Upstream changes arrive as reviewable PRs on a predictable cadence, releases record which upstream version they contain, and downstream systems such as Azure Data Manager for Energy get stable release points to consume.

---
