# ADR-039: Fork-Owned Service Descriptor for Build Archetype and Service Configuration

## Status

**Accepted** — 2026-08-17

Supersedes the Java-only aspect of [ADR-025](025-java-maven-build-architecture.md).
Extends ADR-003, ADR-011, ADR-012, ADR-013, ADR-018, ADR-028, ADR-030, ADR-035,
ADR-036 and ADR-037.

> Note: the originating design note (`osdu-spi-service-descriptor-architecture-2026-08-17`)
> reserved the number "ADR-038" for this decision. ADR-038 had already been allocated to
> *Defer Extra-File Dockerfile Support*, so this decision is recorded as ADR-039.

## Context

- The template copies the same workflows and actions into every service repository. Those
  workflows discover what a repository *is* by re-detecting `pom.xml` in each workflow, and then
  assume JDK 17, Maven, the `core,azure` profile set, JaCoCo, a Spring Boot JAR and the canonical
  Java Dockerfile (ADR-025, ADR-035, ADR-037).
- Initialization captures only `UPSTREAM_REPO_URL`. ADR-003 described a project-type configuration
  parameter that was never implemented, so language and build shape are re-derived at run time
  instead of being recorded once and reviewed.
- Service-specific knowledge is scattered across runtime inference, hardcoded defaults, repository
  variables (`SERVICE_NAME`, `MAVEN_PROFILE`, `SERVICE_TARGET_JAR`), onboarding variables and
  copied files. None of it is versioned, schema-checked or visible in normal source review.
- Template-sync force-replaces `.github/actions/**`, copied `.github/workflows/**`, `build/**`,
  rulesets and settings scripts (ADR-011, ADR-012). Any service-specific configuration placed in
  those paths is overwritten, so persistent service metadata needs a declared service-owned path.
- GitHub does not allow expressions in `jobs.<id>.uses` or step-level `uses:`, so a workflow cannot
  dynamically select `./.github/actions/${{ language }}-build`. Supported language lanes must be
  declared statically and gated with `if:`.
- The changed-path filter in `validate.yml` and `codeql.yml` treats any dotted path as
  configuration-only. A descriptor under `.spi/` would therefore have skipped the build while the
  required `🐳 Docker Build` check still reported success.

## Decision

### 1. One new contract: `.spi/service.yaml`

A single fork-owned descriptor is created during initialization, schema-validated by the template,
and never overwritten by template-sync. It carries only unprivileged build, test and packaging
metadata:

```yaml
schemaVersion: 1

service:
  name: partition
  archetype: java-maven-azure
```

Ownership tiers:

| Tier | Owner | Examples |
| --- | --- | --- |
| Engineering system | template-sync | `.github/workflows/**`, `.github/actions/**`, `build/**`, rulesets, `.github/scripts/service-config/**` |
| Service, non-privileged | the fork, by pull request | `.spi/service.yaml` |
| Admin / Stack, privileged | `spi onboard`, environments, Stack | `AZURE_*`, `AKS_*`, `K8S_*`, acceptance secret maps |

### 2. Closed schema, fail closed

`.github/scripts/service-config/schema.json` defines schema version 1 with closed enums and no
additional keys. `descriptor.py` parses a deliberately small YAML subset with the Python standard
library only — GitHub runners guarantee `python3` but not PyYAML or `yq`, and a checked-in parser
keeps parsing deterministic and reviewable. Anchors, aliases, tags, block scalars, multiple
documents, tabs and nulls are rejected.

The initial archetype enum is `java-maven-azure` and `python-uv-fastapi`. Validation fails closed
for a malformed descriptor, an unknown archetype, an unknown key, a future `schemaVersion`, a path
that escapes the repository, or any privileged-looking key (`env`, `secrets`, `permissions`,
`uses`, `namespace`, `azure*`, `command`, …).

### 3. Detect once at initialization, then persist and review

After the upstream tree is merged, initialization runs `generate_descriptor.py`:

| Markers | Result |
| --- | --- |
| `pom.xml` | minimal `java-maven-azure` descriptor |
| `pyproject.toml` + `uv.lock` | `python-uv-fastapi` descriptor including the detected runtime, distribution, import package, extras and `container.appModule` |
| both, neither, or `pyproject.toml` without `uv.lock` | halt with an actionable error |
| Python service whose ASGI module is missing or ambiguous | halt: the module is a container entrypoint and must be reviewed, not guessed |

An existing descriptor is never overwritten. Unknown service shapes halt rather than silently
selecting a default build lane.

### 4. Language-neutral workflow prelude

`build.yml` and `validate.yml` gain a `read-service-config` job that emits one fixed output set:

```text
descriptor_present  schema_version  archetype     service_name  dockerfile_profile
unit_test_type      has_coverage    build_lane    lane_implemented  fallback
python_runtime_version  python_distribution  python_import_package
python_test_extras      python_runtime_extras  app_module
```

Job outputs never carry shell commands. Language lanes are statically declared and gated on
`build_lane`. The Java lane keeps its name, its action, and `vars.MAVEN_PROFILE` handling. The
Python outputs are the `python-build` action's inputs and the canonical Python image's build
arguments, so a service parameterises its build by editing the reviewed descriptor rather than the
copied workflow. `container.appModule` uses a narrow `<dotted.module>:<attribute>` pattern because
it becomes a container entrypoint value.

### 5. Stable required check that fails closed

The required context stays exactly `🐳 Docker Build`. Renaming it would wedge open pull requests
until every fork's ruleset is reconciled (ADR-030). The summary job now fails when the descriptor
is invalid, fails when a *present* descriptor declares an archetype whose lane is not installed
in the running template version, and fails when the selected lane did not actually build and
validate an image. Only these cases still pass as a skip: uninitialized repository, Dependabot,
config/docs-only changes, and `build_lane == none` (no descriptor and no Maven markers).

Initialization detection follows the same rule: the descriptor, Maven markers and uv Python markers
all count as an initialized service, so a Python repository can never pass the required check by
looking uninitialized.

### 6. `.spi/**` is build-relevant

`validate.yml` and `codeql.yml` special-case `.spi/*` as always build-relevant, next to the existing
`.mvn/*` case. A descriptor-only pull request therefore runs the selected build lane and cannot
obtain a green required check by being classified as configuration.

### 7. Trust boundary

Unprivileged build/test work may read the descriptor from the pull-request tree. For
`pull_request_target` the prelude restores `.spi/` and `.github/scripts/service-config/` from
`origin/main` before resolving, mirroring the existing trusted-actions and `build/` restore. The
descriptor may never select identity, environment, cluster, namespace, Deployment/container target,
secrets, permissions, workflow/action references or arbitrary commands; those remain repository or
environment configuration written by `spi onboard` and the Stack.

`/.spi/` is protected by CODEOWNERS. Because the reviewing team differs per organization and an
unknown owner silently disables `require_code_owner_review`, initialization seeds an *active* rule
only when the `SPI_ENGINEERING_OWNERS` repository variable names a syntactically valid team/user;
otherwise it writes a documented, commented placeholder and `settings-apply` reports it through the
existing deduplicated onboarding issue. Initialization still removes the template's own CODEOWNERS
(it names template maintainers) and then re-seeds the fork-owned file, so the cleanup rule and the
sync exclusion now describe complementary behaviour rather than deleting ownership outright.

### 8. Backward-compatible fallback

| Situation | Behaviour |
| --- | --- |
| No descriptor, Maven markers present | legacy Java inference, `fallback=java-inference`, warning |
| No descriptor, no markers | `build_lane=none`, required check passes as before |
| Descriptor present and valid | descriptor selects the lane |
| Descriptor present and invalid | prelude fails; required check fails closed |
| Fork without the synced scripts | workflow falls back to inline Maven detection |

### 9. Migration

1. Copied workflows learn to read the descriptor; `.spi/**` becomes build-relevant (this ADR).
2. `settings-apply` reports descriptor and `/.spi/` ownership gaps through the existing
   `human-required` onboarding issue (this ADR).
3. Initialization generates descriptors for new repositories (this ADR).
4. Add the `python-build` action, Dockerfile profile and static `python-build` job; generalize
   `docker-build` with a `source` build mode; flip `laneImplemented` for `python-uv-fastapi`
   (done, issue #42). Python deployment and integration testing remain out of scope: the lane
   ends at a published GHCR image and the deploy jobs are explicitly gated on
   `build_lane == 'java'`.
5. Pilot descriptors: Partition, then Entitlements, then the Python pilot.
6. Once the fleet has descriptors, remove the remaining per-workflow language inference in
   `cascade.yml` and `dependabot-validation.yml`, keeping a documented compatibility window.

## Consequences

### Positive

- Build archetype becomes explicit, versioned and reviewable instead of re-inferred per workflow.
- Multi-language support no longer requires divergent copied workflows or a second required check.
- Descriptor changes are ordinary pull requests that run the full selected lane.
- Privileged configuration stays outside PR control; the descriptor is closed-enum data only.
- Existing forks keep working unchanged until they adopt a descriptor.

### Negative

- A second configuration surface exists next to repository variables during migration.
- The strict YAML subset rejects some legal YAML (multi-document files, anchors, block scalars);
  descriptors must stay simple.
- A descriptor for an archetype whose lane is not yet installed intentionally blocks merges.

### Neutral

- `.github/.template-sync-commit` remains the installed engineering-system version; the descriptor
  carries no CI version pin.
- Repository custom properties remain a possible reporting mirror, not the workflow input.

## Alternatives Considered

| Option | Assessment |
| --- | --- |
| Central service catalog in the template | Rejected as primary: every service deviation becomes a central pull request, and the catalog drifts from the service. |
| Repository variables only | Rejected as primary: not versioned, not schema-checked, invisible in code review. Kept for privileged values. |
| Generate per-language workflow variants at init | Rejected: template-sync force-overwrites workflows and required checks would diverge per fork. |
| Separate `validate-java.yml` / `validate-python.yml` | Rejected: doubles workflow surface and required-check complexity. |
| Dynamic reusable-workflow selection | Impossible: expressions are not allowed in `jobs.<id>.uses`. |
| Thin caller + central reusable workflow | Deferred: changes ADR-015 ownership and makes every required check depend on template availability at run time. |

## Related ADRs

- [ADR-003: Template Repository Pattern](003-template-repository-pattern.md) — implements the
  previously described project-type configuration.
- [ADR-011: Configuration-Driven Template Sync](011-configuration-driven-template-sync.md) —
  declares a service-owned, never-synced path.
- [ADR-012: Template Update Propagation](012-template-update-propagation-strategy.md) —
  propagation adds capabilities, not service choices.
- [ADR-013](013-reusable-github-actions-pattern.md) and
  [ADR-028](028-workflow-script-extraction-pattern.md) — the parser and generators are extracted
  scripts, not inline workflow shell.
- [ADR-018: Fork-Resources Staging](018-fork-resources-staging-pattern.md) — initialization stages
  the generated descriptor as a fork resource.
- [ADR-025: Java/Maven Build Architecture](025-java-maven-build-architecture.md) — Java/Maven
  remains the default archetype, but its "multi-language support rejected" position is superseded:
  the archetype is now selected by the fork-owned descriptor.
- [ADR-030: CodeQL Summary Job Pattern](030-codeql-summary-job-pattern.md) — the language-invariant
  summary check keeps its exact context name.
- [ADR-035: Azure-Only Maven Profile](035-azure-only-maven-profile.md) — Java profile defaults move
  under the Java archetype's defaults.
- [ADR-036: Workflow Trust Boundaries](036-workflow-trust-boundaries.md) — descriptor trust rules
  follow the same trusted-restore pattern.
- [ADR-037: Engineering System Owns the Canonical Service Dockerfile](037-engineering-system-owns-service-dockerfile.md)
  — one canonical Dockerfile profile per language, selected by `dockerfile_profile`.

---

[← ADR-038](038-defer-extra-file-dockerfile-support.md) | :material-arrow-up: [Catalog](index.md)
