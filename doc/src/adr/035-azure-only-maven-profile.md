# ADR-035: Azure-Only Maven Profile Restriction

## Context

- Forked OSDU services carry multiple cloud-provider Maven profiles (Azure, AWS, IBM, GC), built via the standard Java/Maven architecture ([ADR-025](025-java-maven-build-architecture.md)). Only Azure is relevant to SPI work — the profile is the CSP selector, and SPI is permanently Azure-only.
- Building and unit-testing the non-Azure profiles in every SPI CI run is wasted CPU and irrelevant signal.
- Surveying all ten service forks shows a near-uniform layout: no default `<modules>`, a `core` profile marked **`activeByDefault`** (the `*-core` / `*-core-plus` modules), and one profile per provider (`azure` → `provider/<svc>-azure`). Maven deactivates an `activeByDefault` profile the moment any explicit `-P` is passed, so `-P azure` alone silently drops `core`, and the Azure module then fails to resolve `<svc>-core:<revision>-SNAPSHOT`. The Azure build therefore requires `-P core,azure`, not a bare provider profile.
- Two forks deviate: `entitlements` builds at `provider/entitlements-v2-azure`, and `indexer-queue` has no provider profiles at all (providers live in the default `<modules>`, with two Azure deployables). A per-fork override is needed for these.

## Decision

- CI builds the Azure profile set with a hardcoded engineering-system default of **`core,azure`** — correct for nine of the ten forks and not requiring any per-fork configuration.
- `MAVEN_PROFILE` remains a **per-service repository variable, but optional**: when set it overrides the default (the workflow passes `${{ vars.MAVEN_PROFILE || 'core,azure' }}`); when unset CI uses `core,azure`. The override exists for forks whose profile shape differs (e.g. `indexer-queue`).
- The build always passes a non-empty `-P` value; it never emits a bare `-P`. (Earlier this ADR specified "unset = no profile filter"; that is superseded — for these profile-gated poms an unfiltered build produces no provider JAR, so a real default is both simpler and more correct.)

## Consequences

- **Positive**
  - Faster, cheaper CI (~3–5× fewer modules built) for Azure SPI service repositories.
  - Unit-test results are 100% Azure-relevant.
  - Zero per-fork configuration for the common case: nine of ten forks build correctly on the `core,azure` default with no variable set.
  - The optional `MAVEN_PROFILE` override handles deviant forks without a template edit + sync.
- **Negative**
  - Lost signal on whether upstream changes break other providers (AWS/IBM/GC) — acceptable since SPI does not ship those.
  - The `core,azure` default assumes the common pom layout; a fork that deviates (e.g. `indexer-queue`) silently builds the wrong module set unless its `MAVEN_PROFILE` override is set — caught on the fork's first build.
- **Neutral**
  - Cross-provider validation, when needed, is handled outside this default CI path.

## Alternatives Considered

- **Continue building all provider profiles in every CI run** — rejected: higher runtime/cost and low relevance to Azure-focused delivery.

---

[← ADR-033](033-ghcr-as-service-image-registry.md) | :material-arrow-up: [Catalog](index.md)
