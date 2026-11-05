# ADR-047: Component Governance Registration and Generated NOTICE

## Status

Accepted (2026-11-04)

## Context

Microsoft's open source compliance review of the service forks (ADO Feature 84645) found that none of them is registered with Component Governance (CG), so nothing tracks what a fork ships or raises its license and security alerts (P1), and that the dependency notices the forks publish are upstream's FOSSA output rather than a list of what our images contain (B2, B3). ADR-043 left `NOTICE` following upstream and reserved the name for a generated dependency notice.

CG registration needs an Azure DevOps pipeline: the detection task does not run in GitHub Actions. The pipelines run in the OpenEnergyPlatform `OSDU-SPI` project, reach GitHub through the Azure Pipelines GitHub App connection, and extend the 1ES Official pipeline template. Under 1ES the job's own steps run behind network isolation that blocks Maven Central and `ghcr.io`, and the CG step the template injects runs after isolation stops, after every other step of its job, and always registers.

What a fork ships is also not what a plain scan of its repository finds. The image carries one Spring Boot module built with the `core,azure` profiles, the Application Insights agent added outside Maven, and an Azure Linux base, while the repository also holds other providers' modules, Python test suites and upstream's history. The forks differ in module layout, profiles and test directories, and CG cannot read GitHub repository variables, so the per-fork facts must live in the repository.

## Decision

**Every service fork runs one template-owned Azure DevOps pipeline that registers what its image ships with Component Governance and generates its `NOTICE` from that registration. Its per-fork inputs are a `componentGovernance` section of the fork-owned `.spi/service.yaml`, and the generated `NOTICE` becomes fork-owned.**

### One synced pipeline, per-fork inputs in the descriptor

`.azuredevops/component-governance.yml` is a `sync-config.json` file entry, identical in every fork. Its steps are scripts in `.github/actions/component-governance/`, synced with the other actions. Each fork gets its own pipeline definition in `OSDU-SPI` pointing at that path, with the ADME Service Tree ID, so its alerts reach the service's owners.

The descriptor section (ADR-040) carries `upstream`, the OSDU community project URL and the only required key, and optionally `image`, `module`, `profiles` and `ignoreDirectories`. The defaults cover most forks: the repository name as the published image (Validation's name when the fork's `SERVICE_NAME` variable is unset, which Azure DevOps cannot read), the Spring Boot module under `provider/*-azure` and the `core,azure` profiles (ADR-035). The acceptance resolver validates the section with the rest of the closed contract, so an unknown key, a URL outside `community.opengroup.org/osdu`, a path that is not repository-relative, or an ignored directory containing the shipped module fails the run before anything is registered.

### What is registered

Steps prepare inputs only; nothing is built under isolation. `MAVEN_ARGS` (`-P <profiles> -pl <module> -am` with the fork's Maven settings) limits the CG Maven detector to the shipped module and its parents. `dockerImagesToScan` names the images Validation published for the commit, the service image and, for a fork with shared schemas, the loader image (ADR-042). `cgmanifest.json` registers what no detector sees: the upstream commit of the newest generated upstream tree (ADR-038, its `Upstream-Sha` equal to its last parent), every `Seeded-From` commit, and the Application Insights agent. Acceptance images are test tooling and are not scanned.

The pipeline runs on `v*` release tags and weekly on `main`; there is no CI or pull request trigger. Compliance is read from `main`. The weekly run also opens or updates the NOTICE pull request, so the NOTICE follows what `main` ships without anyone queuing a run.

### Nothing is registered without the published image

CG only warns when it cannot pull an image and registers the snapshot without it, which reports the image's alerts as fixed. A gate step therefore waits for a successful `Docker Push` of a push-triggered Validation run of the commit and fails the job otherwise. Pull request runs do not count: they publish the merge commit. The Azure Pipelines App cannot read the Actions API, so the gate counts check suites of `main` and refuses when the repository has a pull request from `main`. A commit that changes only files Validation's push filter ignores, such as a template sync, publishes no image and cannot change one, so once its push has settled the gate scans its first parent's images. A push has settled when it is older than a grace period and no workflow it started is still running. It is dated by the commit's first check suite on `main`, not by the commit time, and the running check matters because Validation's `Docker Push` job often starts more than 10 minutes after the push: one push can carry code below a documentation-only tip, and Validation then publishes the tip. The gate reads the persisted App token, which is removed before the scan step. Explicit images skip the gate with a warning.

### NOTICE from the same registration

A second job downloads the NOTICE CG generates for the snapshot the scan job registered, reports every registered component that has no entry, and fails when the scan could not process an image. It must be a second job because the injected CG step runs after all steps of a job. CG is disabled for this job through the 1ES per-job justification, because its own scan would register an empty snapshot that CG then keeps as the branch's production snapshot.

Weekly runs of `main`, and manual runs with `openNoticePr`, commit the NOTICE to `chore/notice-refresh/<branch>` and open or update a draft pull request. A run only replaces its own earlier refresh from an older commit or build, recorded in `Source-Commit` and `Build-Id` trailers, and pushes with a lease; when the refresh already holds the same NOTICE for the same commit it pushes nothing, so an unchanged `main` does not rerun the pull request's checks every week. The commit skips no checks, and `NOTICE` is no longer in Validation's push `paths-ignore`, so a merged refresh publishes the image that ships it.

### NOTICE becomes fork-owned

The filter keeps upstream's `NOTICE` (ADR-038), so a sync would overwrite the generated file. The first refresh in each fork also changes `NOTICE: keep` to `strip` in `.github/upstream-filter.yml`. That pull request touches an upstream-owned file and needs the `port` label. The next generation drops `NOTICE` from `fork_upstream`, and the cascade raises one modify/delete conflict on it, resolved by keeping the fork's file. From then on the merge base lacks `NOTICE` and syncs never touch it, the same arrangement as the fork-owned Azure trees. A silent deletion is not possible: the images copy `NOTICE` by name (ADR-043), so a fork without it fails its build.

## Consequences

### Positive

- Every fork is registered from the same code with its own inputs, reviewed in the fork beside the code they describe.
- Registration matches the shipped image: the module's Maven graph, the image's operating system packages, the agent and the upstream source.
- A missing image fails the run instead of erasing alerts.
- `NOTICE` is generated from the registration the compliance review reads, and every gap is visible in the pull request.

### Negative

- The first NOTICE is incomplete. For partition, 46 of 231 shipped jars have no entry (38 without a ClearlyDefined definition, 6 CG treats as not public, including the OSDU libraries), nor do the agent and the 117 image packages, and 15 entries are test-only components. A fork-owned supplement and a completeness check against the built jar are follow-up work.
- The NOTICE job runs under a 1ES policy exception.
- The forks are classified Non-Production in the 1ES Product Catalog, so their alerts do not reach S360 and CG documents NOTICE generation for such repositories as unsupported, although it works.
- The gate infers publication from check suites. Explicit images, or a pull that fails after the gate, still register without verification; the NOTICE job reports the latter.
- Each fork needs a pipeline definition, a queue authorization and a one-time NOTICE cutover outside the template.

### Neutral

- `NOTICE-OSDU-SPI` (ADR-043) is unchanged and still names the upstream project and holders.
- `osdu-spi-core-lib-azure` ships no image and is out of scope.

## Alternatives Considered

- **GitHub Actions only.** The CG detection task and the NOTICE API need Azure DevOps.
- **A pipeline outside 1ES.** The team chose 1ES Official, the organization's standard for production pipelines, which also supplies network isolation and SDL scanning; the injected CG step running after isolation makes it workable without a feed.
- **A CFS or Azure Artifacts feed for Maven under isolation.** Custom upstreams are npm-only, so the OSDU GitLab registry cannot be proxied, and nothing needs resolving under isolation.
- **NOTICE in the scan job.** The injected CG step runs after all of a job's steps, so that job would read the previous snapshot.
- **Extend a template from the osdu-spi repository instead of syncing a file.** A second repository resource adds a cross-repository authorization in every pipeline and a pin to manage; a synced file follows the existing template model (ADR-011).
- **Scan without the gate.** Proven to register snapshots without the image, 277 registrations and no operating system packages.
- **The `notice@0` task.** It calls the same API and is not installed in the organization.
- **Strip `NOTICE` when the template syncs.** It would delete the dependency notice from every fork before a generated one exists.

---

[← ADR-046](046-fleet-release-bom.md) | :material-arrow-up: [Catalog](index.md)
