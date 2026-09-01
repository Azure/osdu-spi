# ADR-035: Azure-Only Maven Profile Restriction

## Status

Accepted (2026-06-04)

Amended 2026-06-04: the first draft specified "unset = no profile filter". For these profile-gated poms an unfiltered build produces no provider JAR, so the default became `core,azure`.

## Context

- Forked OSDU services carry one Maven profile per cloud provider (Azure, AWS, IBM, GC), built via the standard Java/Maven architecture ([ADR-025](025-java-maven-build-architecture.md)). SPI is Azure-only, so the other profiles are wasted CPU and irrelevant signal.
- The ten service forks share a near-uniform layout: no default `<modules>`, a `core` profile marked `activeByDefault`, and one profile per provider. Maven deactivates an `activeByDefault` profile as soon as any explicit `-P` is passed, so `-P azure` alone drops `core` and the Azure module fails to resolve `<svc>-core`. The Azure build needs `-P core,azure`.
- Two forks deviate: `entitlements` builds at `provider/entitlements-v2-azure`, and `indexer-queue` has no provider profiles at all (providers live in the default `<modules>`). These need a per-fork override.

## Decision

- CI builds with a hardcoded default of `core,azure`, correct for nine of the ten forks with no per-fork configuration.
- `MAVEN_PROFILE` is an optional per-service repository variable. When set it overrides the default; when unset CI uses `core,azure`. `cascade.yml` passes `${{ vars.MAVEN_PROFILE || 'core,azure' }}`; `validate.yml` uses the same expression except on a filter-mode `fork_upstream`, where it builds `core` only because the generated tree has no Azure module ([ADR-038](038-upstream-filter-transform.md)).
- The build always passes a non-empty `-P` value; it never emits a bare `-P`.

## Consequences

- Positive:
  - Fewer modules built per CI run, and unit-test results limited to code SPI ships.
  - Nine of ten forks build correctly with no variable set; the override handles the rest without a template edit.
- Negative:
  - No signal on whether upstream changes break the other providers. Acceptable because SPI does not ship them.
  - A fork that deviates from the common pom layout builds the wrong module set until its `MAVEN_PROFILE` override is set. This is caught on the fork's first build.

## Alternatives Considered

- **Continue building all provider profiles in every CI run**: rejected, higher runtime and cost for signal nobody consumes.

---

[← ADR-033](033-ghcr-as-service-image-registry.md) | :material-arrow-up: [Catalog](index.md)
