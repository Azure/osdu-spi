# ADR-037: Engineering System Owns the Canonical Service Dockerfile

## Status

Accepted (2026-06-04)

## Context

- The `docker-build` and `docker-push` jobs in `validate.yml` need a Dockerfile to turn each service's JAR into a container image. The first `docker-build` action defaulted `dockerfile_path` to `devops/azure/Dockerfile`, assuming every service fork ships its own usable Dockerfile.
- That assumption does not hold. The `partition` reference fork's `provider/partition-azure/Dockerfile` bases on `openjdk:8-jdk-alpine` (CI builds JDK 17), copies a `partition-aks-1.0.0.jar` that does not exist (the real artifact is `partition-azure-<version>-spring-boot.jar`), and uses a module-relative build context. Other services may carry a different Dockerfile, an outdated one, or none.
- OSDU itself does not treat the Dockerfile as service-owned. Its GitLab pipeline copies `java/Dockerfile` from a shared `service-base-image` repository into each service at build time; the recipe is service-agnostic via a `JAR_FILE` build-arg, and the AppInsights agent is baked into the base image at `/opt/agents/`.
- The deployable JAR is built from source by the `java-build` job and consumed as the `build-artifacts` artifact; the image build copies a prebuilt JAR and runs no Maven ([ADR-025](025-java-maven-build-architecture.md)). The OSDU Maven registry resolves build dependencies only, never the service's own deployable JAR.

## Decision

- The engineering system owns one canonical Java service Dockerfile at `build/Dockerfile`, synced to every fork through the `build` directory entry in `sync-config.json`. Service forks do not supply their own Dockerfile for CI; the `docker-build` action defaults `dockerfile_path` to `build/Dockerfile`.
- The recipe mirrors the OSDU community `service-base-image/java/Dockerfile`: `COPY ${JAR_FILE} /app.jar` into a base image, with the JVM, AppInsights, and MSI environment the community image expects. No Maven runs inside the image build.
- The `docker-build` action selects the JAR. The caller passes `jar_file`, defaulting to `provider/<SERVICE_NAME>-azure/target/*-spring-boot.jar` with `SERVICE_NAME` defaulting to the repository name, and the action supplies the resolved path as the `JAR_FILE` build-arg. When that path matches nothing (for example `entitlements` builds `provider/entitlements-v2-azure`), the action discovers the Azure Spring Boot JAR itself, so a fresh fork builds with no per-service variable. `SERVICE_TARGET_JAR` is needed only to disambiguate a service that builds more than one Azure JAR, and `SERVICE_NAME` only when the repository name is not the Maven service slug; it also names the image.
- The base is the Microsoft Build of OpenJDK 17 on Azure Linux, `mcr.microsoft.com/openjdk/jdk:17-azurelinux`, pinned by digest on `FROM`. It is multi-arch, so release images pull natively on arm64 and amd64, and MCR is anonymously pullable from runners. Dependabot's `docker` ecosystem runs only in the template (`directory: /build`) and opens the digest-bump PR there; template sync carries the updated Dockerfile to every fork, and forks carry no `docker` ecosystem. The ref sits on `FROM` rather than behind an `ARG` because Dependabot does not reliably follow `FROM ${ARG}`.
- The Application Insights Java agent is fetched with `ADD --checksum` (version and sha256 pinned, no `RUN` so the arm64 leg needs no emulation) to `/opt/agents/`, where OSDU's base image kept it. `build/docker-entrypoint.sh` attaches it with `-javaagent` only when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set to something other than the image default `dummy`. Dependabot tracks `FROM` refs, not `ADD` URLs, so agent bumps are a manual edit of the version and checksum.

## Consequences

### Positive

- One Dockerfile to audit and patch for all forks, with no per-fork drift.
- A new or Dockerfile-less service builds an image with no per-service Docker work; the Dockerfile arrives via sync and the JAR is discovered.
- The image ships the JAR compiled from source in this fork, never a third-party artifact.

### Negative

- The `linux/arm64` leg builds under QEMU emulation on the amd64 runner, on the push path only; the validate-only build is amd64. With no `RUN` steps the cost is pulling the arm64 base layers, but a service that later adds `RUN` steps to the image will pay real emulation time.
- A fork can no longer trivially diverge its Dockerfile. This is intentional and consistent with the template model ([ADR-003](003-template-repository-pattern.md)).

### Neutral

- Stale in-repo Dockerfiles in service forks are unused by CI. They may be removed upstream later but do not block the pipeline.

## Alternatives Considered

- **Service-owned Dockerfile (the original default)**: rejected. Partition's is stale, not every service has one, and the model produces per-fork drift and silent build failures.
- **Pull the prebuilt service JAR from OSDU's Maven registry**: rejected. The build lane must ship a JAR it built for provenance; OSDU's own pipeline also builds the JAR itself.
- **Build from source inside the Dockerfile (multi-stage `mvn package`)**: rejected. It duplicates the `java-build` job, loses the shared Maven cache and the coverage path, and slows every image build.

---

[← ADR-036](036-workflow-trust-boundaries.md) | :material-arrow-up: [Catalog](index.md)
