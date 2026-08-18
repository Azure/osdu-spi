# Service Descriptor (`.spi/service.yaml`)

The service descriptor is the one file a fork owns that tells the copied workflows *what this
repository is*. It is created during initialization, validated by a template-owned schema, and
never overwritten by template-sync ([ADR-039](../adr/039-fork-owned-service-descriptor.md)).

## What it looks like

A conventional Java service needs almost nothing:

```yaml
schemaVersion: 1

service:
  name: partition
  archetype: java-maven-azure
```

A Python service records the facts the Python lane needs:

```yaml
schemaVersion: 1

service:
  name: wellbore-ddms-worker
  archetype: python-uv-fastapi

build:
  python:
    runtimeVersion: "3.12"
    packageManager: uv
    lockfile: uv.lock
    distribution: osdu-wbddms-worker
    importPackage: wdmsworker
    testExtras: [dev]
    runtimeExtras: [az]

tests:
  unit:
    type: pytest
    path: tests/unit
    coverage: true

container:
  appModule: wdmsworker.app:app
```

`container.appModule` is the ASGI target baked into the canonical Python image, because the Stack
chart cannot override a container command. Its pattern is deliberately narrow —
`<dotted.module>:<attribute>` — so the value can never carry a space, an option or a shell
metacharacter into a build argument. It is required for `python-uv-fastapi` and rejected for a Java
service.

The full field list is the template-owned schema at
`.github/scripts/service-config/schema.json`.

## Supported archetypes

| Archetype | Selected when | Build lane installed |
| --- | --- | --- |
| `java-maven-azure` | `pom.xml` is present at initialization | Yes — build, test, image, push, deploy, integration tests |
| `python-uv-fastapi` | `pyproject.toml` and `uv.lock` are present | Yes — build, test, image, push (no deploy or integration tests) |

Anything else halts initialization with an actionable message instead of guessing a build lane. For
a Python service the ASGI module is detected the same way: an unambiguous `src/<package>/app.py`
defining a top-level `app` becomes `container.appModule`; anything less clear halts and asks for a
reviewed, hand-written descriptor.

## What it may never contain

The descriptor is edited by ordinary pull requests, so it is restricted to closed-enum, path and
name data. Azure identity, subscription/tenant, cluster, namespace, Deployment/container target,
GitHub Environment, secrets, permissions, workflow or action references and arbitrary commands are
rejected by the validator. Those values stay in repository/environment variables written by
`spi onboard` and in Stack-side configuration.

## How the workflows use it

`build.yml` and `validate.yml` start with a `read-service-config` job that emits a fixed output set:

```text
descriptor_present  schema_version  archetype     service_name  dockerfile_profile
unit_test_type      has_coverage    build_lane    lane_implemented  fallback
python_runtime_version  python_distribution  python_import_package
python_test_extras      python_runtime_extras  app_module
```

`build_lane` selects the statically declared language job (`🔨 Java Build` or `🐍 Python Build`)
and the image profile: the Java lane keeps artifact mode with `build/Dockerfile`, the Python lane
builds `build/python/Dockerfile` from source plus `uv.lock` with `app_module` and
`python_runtime_extras` as build arguments. The Python outputs are also the python-build action's
inputs, so a fork parameterises its build by editing the descriptor, never the workflow.

The required check keeps its exact context name, `🐳 Docker Build`, and fails closed when the
descriptor is invalid, when it declares an archetype whose lane is not installed in the fork's
template version, or when the selected lane did not actually build.

Deploy and integration testing remain Java-only and are gated on `build_lane == 'java'`.

For `pull_request_target` runs the descriptor and its parser are restored from `origin/main`, so an
untrusted branch can never influence a privileged run.

## Changing the descriptor

1. Edit `.spi/service.yaml` in a normal pull request.
2. The change is build-relevant: `.spi/**` always runs the selected build lane and CodeQL.
3. `/.spi/` is owned in `CODEOWNERS`. If your organization has not configured
   `SPI_ENGINEERING_OWNERS`, the seeded rule is a documented placeholder and `settings-apply`
   tracks it in the onboarding issue until a real team is set.

## Local validation

```bash
# Resolve the descriptor exactly as the workflows do
python3 .github/scripts/service-config/read_service_config.py --root . --format json

# Regenerate a missing descriptor (never overwrites an existing one)
python3 .github/scripts/service-config/generate_descriptor.py --root . --service-name partition

# Seed or refresh the /.spi/ ownership rule
python3 .github/scripts/service-config/generate_codeowners.py \
  --path CODEOWNERS --owners "@my-org/engineering-system"
```

No third-party packages are required: the parser is a strict, checked-in YAML subset reader that
runs on the standard library available on every GitHub-hosted runner. Keep descriptors simple —
anchors, aliases, tags, block scalars and multiple documents are rejected by design.

## Forks without a descriptor

Existing forks keep working. With no descriptor and a `pom.xml` present, the workflows fall back to
the legacy Java inference and log a warning; with no descriptor and no Maven markers the required
check passes as it always did.
