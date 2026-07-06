# ADR-038: Defer Extra-File Dockerfile Support for Core Service Onboarding

## Context

- ADR-037 established that the engineering system owns a single canonical service Dockerfile at `build/Dockerfile`, synced into service forks. Service forks do not supply their own CI Dockerfile.
- The immediate SPI onboarding target is the 10 core service set used by the shared SPI Stack deploy loop: `partition`, `entitlements`, `legal`, `schema`, `file`, `storage`, `indexer`, `indexer-queue`, `search`, and `workflow`.
- Official Azure SPI currently has only one service fork, `Azure/osdu-spi-partition`. SPI Stack already deploys the 10 core services plus three reference services, `crs-catalog`, `crs-conversion`, and `unit`, from community images through `osdu-image-lock`.
- ADME's shared `oep-deployment-resources` build system has an alternate `DockerfileForExtraFiles` with an `OPTIONAL_FILES` build argument. That mechanism copies extra runtime files into the image with `COPY ${OPTIONAL_FILES} ${OPTIONAL_FILES}`.
- ADME Partition and Entitlements do not use `OPTIONAL_FILES`. ADME usage was found only in the reference services:
  - `OSDU-Crs-Catalog-Service`: `data/crs_catalog_v2.json`
  - `OSDU-Crs-Conversion-Service`: `apachesis_setup`
  - `OSDU-Unit-Service`: `data/unit_catalog_v2.json`
- A raw `OPTIONAL_FILES` passthrough has a sharp edge: the ADME Dockerfile warns that an empty value can copy the entire Docker context. SPI's GitHub Actions path should not add that footgun without a concrete service requirement and path validation.

## Decision

Do not change the SPI canonical Dockerfile or `docker-build` action for the 10 core service onboarding wave.

Do not add ADME-style raw `OPTIONAL_FILES` support now. The current `build/Dockerfile` plus `JAR_FILE` resolution remains sufficient for the 10 core services.

If SPI later onboards reference services that need extra runtime files, introduce a separate, explicit, validated mechanism such as `SERVICE_EXTRA_FILES`, rather than a raw Docker build-arg passthrough. That future mechanism must validate that paths are relative, non-empty, present in the build context, and cannot use parent traversal or absolute paths.

## Rationale

- The current onboarding scope does not require extra files. Partition and Entitlements were checked directly, and neither ADME service uses `OPTIONAL_FILES`.
- The ADME services that need extra files map to SPI Stack's reference-service set, not Daniel's immediate 10 core service set.
- Keeping the Dockerfile unchanged avoids delaying core service onboarding for a capability that is not required by the core services.
- Deferring extra-file support preserves the security and simplicity of the current Docker build contract: the build job produces a JAR, and the image build copies only that JAR plus centrally managed runtime files.
- A future reference-service implementation can be designed with safe input validation instead of inheriting ADME's raw `OPTIONAL_FILES` behavior.

## Consequences

### Positive

- The 10 core services can onboard with the existing canonical Dockerfile.
- No extra per-service Dockerfile override or build argument is required for core services.
- The Docker build contract stays small and auditable.
- Future reference-service work can add extra-file support deliberately, with validation and tests.

### Negative

- `crs-catalog`, `crs-conversion`, and `unit` cannot yet be built by SPI if their runtime image requires the same extra files ADME bakes into those images.
- A later reference-service onboarding wave will need a small design and implementation step before those services can use SPI-built images.

### Neutral

- SPI Stack can continue deploying reference services from community images through `osdu-image-lock` until SPI-built images for reference services are explicitly in scope.
- ADME's `DockerfileForExtraFiles` remains useful evidence for future reference-service support, but it is not copied into SPI as-is.

## Alternatives Considered

- **Add raw `OPTIONAL_FILES` support now**: rejected because it is not needed for the 10 core services and can accidentally copy too much of the Docker context if empty or misconfigured.
- **Copy ADME `DockerfileForExtraFiles` into SPI**: rejected because SPI should keep one canonical Dockerfile and avoid ADME-specific production pipeline assumptions.
- **Service-owned Dockerfiles for services needing extras**: rejected for now because ADR-037 intentionally centralizes Dockerfile ownership to avoid per-fork drift. If reference services need extras, the centralized action/Dockerfile should support them safely.

---

[← ADR-037](037-engineering-system-owns-service-dockerfile.md) | :material-arrow-up: [Catalog](index.md)
