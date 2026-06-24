# ADR-032: CI/CD Deploy Loop via Suspended Flux

## Context

The OSDU SPI engineering system (three-branch fork model — [ADR-001](001-three-branch-strategy.md)) produces validated Maven artifacts but no container images, deployments, or integration-test signal. The runtime infrastructure (`osdu-spi-stack`) uses Flux GitOps for initial cluster provisioning and baseline state.

Two forces are in tension:

- **Flux reconciliation** continuously drives cluster state toward the declared HelmRelease manifests; any image injected outside GitOps is reverted on the next reconcile cycle.
- **Per-PR CI cadence** requires mutating live Deployments freely — once per push — without waiting for a GitOps commit round-trip or creating per-PR HelmRelease revisions.

The template-workflow distribution model ([ADR-015](015-template-workflows-separation-pattern.md)) means the deploy mechanism must be expressible as a reusable GitHub Actions job pattern, not a cluster-operator workflow.

There is a single shared `osdu-spi-stack` AKS cluster. Per-service "CI mode toggles" on that shared cluster are not feasible; the coexistence strategy must cover the whole cluster.

## Decision

Operate the shared `osdu-spi-stack` cluster with **all Flux Kustomizations permanently suspended** as the normal steady state.

Key mechanics:

- After initial cluster bring-up, `flux suspend kustomization --all -n flux-system` is run once and never reversed during CI operation.
- Per-PR deploy jobs execute `kubectl set image deployment/<name> <container>=<registry>/<image>@<digest> -n osdu` directly.
- Images are always referenced by **immutable digest** (`sha256:…`), never by mutable tag, so the running image is guaranteed to be what the build produced.
- A pre-flight step in every deploy job asserts that all Flux Kustomizations are still suspended; the job fails fast if any are found resumed, surfacing accidental operator action immediately.
- Flux is resumed only during a **planned baseline refresh** — a coordinated, CI-freeze outage that resets all Deployments to the declared HelmRelease state, then re-suspends Flux.
- Deployment and container names are exposed as per-service GitHub repo variables (`K8S_DEPLOYMENT_NAME`, `K8S_CONTAINER_NAME`) rather than derived from service names, insulating CI from Helm chart naming changes.

## Consequences

**Positive:**

- Per-PR deploy cadence is achievable with sub-minute latency — no GitOps commit round-trip.
- Zero race conditions between CI image injection and Flux reconciliation.
- Deploy mechanism is a single `kubectl set image` invocation; no Helm dynamics, no HelmRelease editing required in CI.
- Pre-flight Flux assertion prevents silent drift caused by accidental Flux resume.
- Immutable digest references prevent tag-reuse and guarantee test/run image identity.

**Negative:**

- Cluster state drifts progressively from the declared HelmRelease manifests after many CI runs; only a baseline refresh resets it.
- Operators cannot rely on Flux self-healing during CI cycles (e.g., an accidental `kubectl delete deployment` is not auto-restored).
- Baseline refresh is a planned outage requiring a CI freeze across all current service forks — not a casual cron job.
- The "CI mode" invariant requires explicit operator awareness; documentation and the pre-flight assertion are the only enforcement mechanisms.

## Alternatives Considered

- **Flux image automation** (image-reflector + image-automation controllers watching the registry and updating the HelmRelease) — rejected: requires a writable GitOps commit per image push, adds reflector poll latency, and still races when two PRs build simultaneously against the same shared Deployment.

- **Argo CD instead of Flux** (`argocd app set --helm-set image.tag=…`) — avoids direct `kubectl` mutation. Rejected: introduces a second GitOps tool alongside the Flux-managed baseline; the cluster is already provisioned with Flux, so the operational complexity outweighs the benefit for a shared sandbox cluster.

- **Helm CI release-per-PR** (`helm upgrade --install <svc>-pr-<number> …`) — each PR installs an isolated Helm release. Rejected: requires per-PR namespace or resource segregation, complicates integration tests against the shared gateway, and leaves orphaned releases when branches are deleted without careful cleanup hooks.

---

[← ADR-031](031-template-sync-duplicate-prevention.md) | :material-arrow-up: [Catalog](index.md)
