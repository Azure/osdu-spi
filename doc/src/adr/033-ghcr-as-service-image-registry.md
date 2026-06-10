# ADR-033: GHCR as Service Image Registry

## Context

- SPI service images are CI test artifacts consumed by the shared `osdu-spi-stack` AKS cluster — not customer-shipped product containers.
- The registry must accept pushes from GitHub Actions with no extra auth wiring and allow AKS to pull without per-fork pull secrets.
- The publishing-org policy context differs for CI/tooling artifacts vs. product containers: Microsoft's MCR onboarding policy (`aka.ms/mcr/onboarding`) targets customer-shipped product containers, while developer-tooling and CI/test-loop containers commonly land on GHCR. Observable Azure-org precedent normalizes public GHCR for this class of artifact (e.g. Eraser, Azure Workload Identity, Azure Developer CLI, Kubelogin, AKS-MCP). See design §7.4.

## Decision

- Use **public GHCR** as the SPI service image registry.
- Push images via the workflow `GITHUB_TOKEN` (no extra credential); AKS pulls anonymously (no `imagePullSecret`).
- Keep image publication aligned with current CI/test-consumer needs in the shared `osdu-spi-stack` AKS environment.
- Defer MCR migration to a future decision (Phase 4 upstream review), not a current requirement.

## Consequences

- Positive:
  - No image-pull-secret provisioning in the cluster and no cross-cloud auth wiring.
  - Fast path for publishing and consuming service images in existing SPI CI workflows.
  - Aligns with established Azure GitHub ecosystem practice for tooling/CI containers.
  - Free storage for public packages.
- Trade-off:
  - Image visibility is tied to package settings — an accidental private flip breaks AKS pulls with `ErrImagePull`.
  - If policy interpretation or artifact scope changes (CI artifact → customer-shipped), the registry choice may need to be swapped later.

## Alternatives Considered

- **Option A — ACR + existing `AcrPull` (or a future MCR path)**:
  - Viable fallback aligned with the §7.4 future-migration framing.
  - Migration-swap scope is **localized** — touches only the visibility helper used by `W2`, `ONBOARD-INIT-A`, and `SETTINGS-APPLY`; cluster-side is untouched (the kubelet identity already holds `AcrPull`).
  - Deferred for now because public GHCR already satisfies CI/test-artifact needs.

- **Option B — private GHCR + per-fork `imagePullSecret`**:
  - Viable fallback but **broader-touch** operationally: requires `regcred` Secrets in the `osdu` namespace, chart-level `imagePullSecrets:` wiring in `osdu-spi-stack`, and a Secret-provisioning step in `ONBOARD`.
  - Not selected — it reintroduces the per-fork pull-secret management that public GHCR avoids.

---

[← ADR-031](031-template-sync-duplicate-prevention.md) | :material-arrow-up: [Catalog](index.md)
