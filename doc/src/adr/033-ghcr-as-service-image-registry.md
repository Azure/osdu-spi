# ADR-033: GHCR as Service Image Registry

## Status

Accepted (2026-06-04)

## Context

- SPI service images are CI test artifacts consumed by the shared `osdu-spi-stack` AKS cluster, not customer-shipped product containers.
- The registry must accept pushes from GitHub Actions with no extra auth wiring and allow AKS to pull without per-fork pull secrets.
- Microsoft's MCR onboarding policy targets customer-shipped product containers; CI and developer-tooling containers from Azure GitHub organizations are commonly published on public GHCR.

## Decision

- Use **public GHCR** as the SPI service image registry.
- Push images via the workflow `GITHUB_TOKEN` (no extra credential); AKS pulls anonymously (no `imagePullSecret`). The `docker-build` action sets the package public after the first push.
- Defer any MCR migration to a later decision; it is not a current requirement.

## Consequences

- Positive:
  - No image-pull-secret provisioning in the cluster and no cross-cloud auth wiring.
  - Free storage for public packages.
- Trade-off:
  - Image visibility is tied to package settings; an accidental private flip breaks AKS pulls with `ErrImagePull`. `settings-apply.yml` reports the visibility on its cadence but cannot correct it, because GHCR has no API to change package visibility.
  - If the artifact scope changes from CI artifact to customer-shipped, the registry choice may need to be swapped later.

## Alternatives Considered

**ACR with the existing `AcrPull` role, or a future MCR path.** A viable fallback. The swap is localized to the package-visibility helper in the `docker-build` action; the cluster side is untouched because the kubelet identity already holds `AcrPull`. Deferred because public GHCR already satisfies CI/test-artifact needs.

**Private GHCR with a per-fork `imagePullSecret`.** Also viable but broader in reach: it needs `regcred` Secrets in the `osdu` namespace, chart-level `imagePullSecrets` wiring in `osdu-spi-stack`, and a Secret-provisioning step at onboarding. Not selected because it reintroduces the per-fork pull-secret management that public GHCR avoids.

---

[← ADR-031](031-template-sync-duplicate-prevention.md) | :material-arrow-up: [Catalog](index.md)
