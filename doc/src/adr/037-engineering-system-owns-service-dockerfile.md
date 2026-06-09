# ADR-037: Engineering System Owns the Canonical Service Dockerfile

## Context

- The `docker-build` / `docker-push` jobs (W5a) need a Dockerfile to turn each service's JARs into a container image. The merged `docker-build` action defaulted `dockerfile_path` to `devops/azure/Dockerfile` — assuming every service fork ships its own usable Dockerfile.
- That assumption does not hold. The `partition` reference fork's in-repo `provider/partition-azure/Dockerfile` is stale and unusable for this pipeline: it bases on `openjdk:8-jdk-alpine` (CI builds JDK17), `COPY`s a fictional `partition-aks-1.0.0.jar` (the real artifact is `partition-azure-<version>-spring-boot.jar`), and uses a module-relative build context. Other services may carry a different Dockerfile, an outdated one, or none at all.
- OSDU itself does not treat the Dockerfile as service-owned. Its GitLab pipeline clones a shared `service-base-image` repository and copies `java/Dockerfile` into each service at build time; the recipe is service-agnostic via a `JAR_FILE` build-arg, and the AppInsights agent is baked into the base image at `/opt/agents/`.
- The deployable JAR is built from source by our own `java-build` job and consumed as the `build-artifacts` artifact; the image build is a COPY-prebuilt step, not a Maven run (ADR-025, and the docker-build action contract). The OSDU Maven registry is used only to resolve build **dependencies** — never to fetch the service's own deployable JAR.

## Decision

- The engineering system (`osdu-spi`) owns a single canonical Java service Dockerfile at `build/Dockerfile`, synced to every fork via `sync-config.json` (`directories[]`, `sync_all`). Service forks do not supply their own Dockerfile for CI; the `docker-build` action default `dockerfile_path` becomes `build/Dockerfile`.
- The recipe mirrors the OSDU community `service-base-image/java/Dockerfile`: `COPY ${JAR_FILE} app.jar` into a base image, with the JVM / AppInsights / MSI environment the community image expects. No Maven runs inside the image build.
- The service JAR is selected by the `docker-build` action, not hard-wired: the caller passes the conventional path (or a `SERVICE_TARGET_JAR` override) via the action's `jar_file` input — default `provider/<SERVICE_NAME>-azure/target/*-spring-boot.jar` (`SERVICE_NAME` itself defaulting to the repo name) — and the action resolves it and supplies it to the Dockerfile as the `JAR_FILE` build-arg. When the conventional path matches no file — a service whose Azure module name deviates from the repo name (e.g. `entitlements` → `entitlements-v2-azure`) — the `docker-build` action auto-discovers the Azure Spring Boot JAR, so a fresh fork builds with no per-service variable and no first failure; `SERVICE_TARGET_JAR` is then needed only to disambiguate a service that builds more than one Azure JAR. The repo-name default assumes the repo name is the Maven service slug, which holds for the bare-named service forks; a renamed or `osdu-spi-*`-prefixed repo sets `SERVICE_NAME`. The JAR is always one we built from source; it is never a prebuilt artifact pulled from OSDU's Maven registry.
- The base is the Microsoft Build of OpenJDK 17 on Azure Linux (`mcr.microsoft.com/openjdk/jdk:17-azurelinux`), pinned by digest directly on `FROM` for reproducibility. It is published multi-arch (`linux/amd64` + `linux/arm64`), so release images pull natively on Apple Silicon developer machines as well as amd64 servers, and MCR is anonymously pullable from GitHub Actions runners. Base-image patches are owned centrally: the `docker` Dependabot ecosystem runs **only in the template** (`directory: /build`) and opens the digest-bump PR there; `template-sync` then propagates the updated Dockerfile to every fork. Forks carry no `docker` ecosystem and never author their own base bump. The ref sits on `FROM` (not behind an `ARG`) because Dependabot does not reliably follow `FROM ${ARG}`; a base pivot is a one-line `FROM` edit.
- The Application Insights Java agent that OSDU's `alpine-zulu17` baked at `/opt/agents/` is reproduced here: the Dockerfile bakes a version + sha256-pinned agent via `ADD --checksum` (no `RUN`, so the arm64 leg stays cheap), and the canonical entrypoint (`build/docker-entrypoint.sh`) attaches it with `-javaagent` only when a real `APPLICATIONINSIGHTS_CONNECTION_STRING` is set — the image default is the sentinel `dummy`, so production gets codeless instrumentation while local / unconfigured runs start clean. Dependabot's docker ecosystem only tracks `FROM` refs, not `ADD` URLs, so agent version bumps are manual.

## Consequences

### Positive

- One Dockerfile to audit and patch (base CVE bumps, JVM flags) for all forks — no per-fork drift.
- A new or Dockerfile-less service builds an image with zero per-service Docker work: onboarding sets `SERVICE_NAME` (and `MAVEN_PROFILE`), and the canonical Dockerfile arrives via sync.
- The image provably ships the JAR we compiled from source, not a third-party artifact.

### Negative

- The App Insights agent is version + sha256-pinned and is **not** seen by Dependabot (it arrives via `ADD --checksum`, not `FROM`), so agent security bumps are a manual edit (new version in the URL arg + new checksum) rather than an automated PR. The base image, by contrast, is Dependabot-managed. MCR is anonymously pullable, so there is no registry-auth dependency at `FROM` time.
- The `linux/arm64` leg is built under QEMU emulation on the amd64 runner. The canonical Dockerfile has no `RUN` steps (it only `COPY`s the prebuilt, arch-independent JAR), so emulation cost is limited to pulling the arm64 base layers; a service that later adds `RUN` steps to the image build will pay real emulation time on the arm64 leg.
- A service whose Azure module name deviates from the `<name>-azure` convention (e.g. `entitlements-v2-azure`) needs no configuration: the `docker-build` action discovers the Azure Spring Boot JAR when the conventional path matches nothing. `SERVICE_TARGET_JAR` is required only to disambiguate a service that builds more than one Azure JAR; `SERVICE_NAME` is set when the repo name is not the service slug (it also drives the image name).
- A fork can no longer trivially diverge its Dockerfile — intentional, consistent with the template/engineering-system model (ADR-003).

### Neutral

- Stale in-repo Dockerfiles in service forks become simply unused by CI; they may be removed upstream later but do not block the pipeline.

## Alternatives Considered

- **Service-owned Dockerfile (the original default)** — rejected: partition's is stale and wrong, not every service has one, and the model produces per-fork drift and silent build failures.
- **Pull the prebuilt service JAR from OSDU's Maven registry** — rejected: the build lane must build and ship our own JAR for provenance; OSDU's own pipeline also builds the JAR itself and uses the registry only for dependencies.
- **Build-from-source inside the Dockerfile (multi-stage `mvn package`)** — rejected: duplicates the `java-build` job, loses the shared Maven cache and the coverage path, and slows every image build.

---

[← ADR-036](036-workflow-trust-boundaries.md) | :material-arrow-up: [Catalog](index.md)
