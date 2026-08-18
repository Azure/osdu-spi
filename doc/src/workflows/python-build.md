# Python Build Profile

The Python build profile is the uv-based counterpart to the Java/Maven lane. It gives
Python services the same guarantees the Java lane already provides — reproducible
dependency installation, quality gates, test reports, and a canonical container image
owned by the engineering system rather than by each fork.

Two template-owned assets implement the profile:

| Asset | Purpose |
| --- | --- |
| `.github/actions/python-build` | Locked sync, lint, types, pytest suites, runtime import smoke, report upload |
| `build/python/Dockerfile` | Canonical service image built from source plus `uv.lock` |

Both are synced to every fork. Services do not author their own build action or
Dockerfile; they select and parameterise the profile.

## When the profile applies

A repository uses the Python profile when it contains both:

- `pyproject.toml`
- `uv.lock`

A `pyproject.toml` without a lockfile fails closed. The profile is lock-based end to
end: if the lockfile is missing, CI would test one dependency resolution and the image
would ship another.

Repositories without `pyproject.toml` skip the lane exactly as the Java action skips a
repository without `pom.xml`.

## Runtime versions

- **3.12 is the deployment runtime.** It matches the Azure Linux container base.
- **3.13 is a compatibility leg only.** MCR does not publish an
  `azurelinux/base/python:3.13` tag, so 3.13 must never be treated as the runtime.

The action takes a single `python_version`; a caller runs a compatibility matrix by
invoking it a second time with `python_version: '3.13'`.

## Build phases

The action runs a fixed phase sequence. Phases after the environment sync all run even
when an earlier one fails, so a single CI run reports every problem:

1. **sync-test-env** — `uv sync --locked` with the test extras. Fatal on failure.
2. **lock-drift** — `uv lock --locked` proves the lockfile matches `pyproject.toml`.
   The exported-requirements comparison runs **only** when the repository supplies its
   own regeneration script (`lock_regeneration_script`).
3. **quality** — `ruff check`, `ruff format --check`, `mypy`.
4. **tests** — unit, service in-process, and service subprocess pytest suites.
5. **package** — optional `uv build` packaging validation.
6. **runtime-extras** — `uv sync --locked --no-dev` plus the runtime extras, then an
   import smoke of the declared runtime modules. This proves the Azure provider extra
   actually installs and imports rather than merely appearing in a universal lockfile.
   It runs last because it replaces the test environment.

`build_result` is emitted from the single build step, so callers keep the same
success/failure contract the Java lane uses.

## Reports and artifacts

Upstream Python projects commonly overwrite one `report.xml` and one `coverage.xml`.
The profile writes one file per suite under `.spi-build-reports/`:

| Suite | JUnit | Cobertura |
| --- | --- | --- |
| unit | `unit-junit.xml` | `unit-coverage.xml` |
| service (in-process) | `service-inprocess-junit.xml` | `service-inprocess-coverage.xml` |
| service (subprocess) | `service-subprocess-junit.xml` | — (a separate process; coverage is not meaningful) |

Three artifacts are uploaded:

- `build-artifacts` — `build-manifest.json` (archetype, commit, versions, extras, lockfile
  digest) plus any wheel/sdist from the packaging validation. The name is deliberately
  identical to the Java lane's artifact so downstream jobs stay language-neutral.
- `python-junit-reports`
- `python-coverage-reports`

The job summary shows the resolved build plan, per-phase results, a per-suite test table,
and per-suite coverage.

## Inputs

Every input is a closed enum, a version, a PEP 508 name, a dotted module name, or a
repository-relative path. There is no command or argument passthrough, and nothing is
evaluated by a shell.

Optional inputs share one convention:

| Value | Meaning |
| --- | --- |
| `""` | Convention-based auto-detection; skip when nothing is found |
| `none` | Explicitly disabled |
| anything else | Used strictly; a missing path is an error, not a silent skip |

| Input | Default | Notes |
| --- | --- | --- |
| `python_version` | `3.12` | `MAJOR.MINOR` or `MAJOR.MINOR.PATCH` |
| `uv_version` | `0.12.5` | Pinned to the uv release the canonical image installs with; an explicitly empty value honours the repository `required-version` |
| `source_paths` | `""` | `src` when present, else the repository root |
| `format_check_paths` | `""` | Repository root |
| `package_name` | `""` | Detected from the source root; used for coverage and import smoke |
| `distribution_name` | `""` | `[project].name`; used for the installed-metadata check |
| `test_extras` | `""` | `dev` when declared in `[project.optional-dependencies]` |
| `runtime_extras` | `""` | `az` when declared |
| `runtime_import_modules` | `""` | Defaults to the import package |
| `unit_test_path` | `""` | `tests/unit` when present |
| `service_test_path` | `""` | `tests/service` when present |
| `service_test_modes` | `in-process,subprocess` | Enum list, or `none` |
| `service_in_process_flag` | `--no-subprocess` | A single flag token; values and spaces are rejected |
| `generate_coverage` | `false` | Cobertura for unit and in-process service suites |
| `lint_mode` / `typecheck_mode` | `auto` | `auto`, `required`, or `off` |
| `lock_regeneration_script` | `""` | Repository-owned `.sh`; enables the export drift gate |
| `lock_drift_paths` | `""` | Defaults to `uv.lock` plus committed requirements files |
| `package_build` | `false` | Runs `uv build` |
| `index_name` / `index_username` / `index_token` | `""` | Credentials for a private uv index; masked, never a build argument |

Extras are validated against `[project.optional-dependencies]`, so a typo fails with the
list of extras the project actually declares instead of a late resolver error.

## Caller prerequisites

The composite action installs its own toolchain — the caller does not need to run
`actions/setup-python` or `astral-sh/setup-uv` first.

The **caller owns the checkout**, exactly as it does for `java-build`. Check out with
`fetch-depth: 0`: the lock/export drift gate compares the working tree with the commit.
Under `pull_request_target` the caller checks out the reviewed ref and restores the
trusted actions from `origin/main` before this action runs, so the action never decides
which tree a privileged run sees.

Callers must supply:

- a runner with Docker-free Python build capability (`ubuntu-latest` is sufficient);
- `index_token` only when the service resolves from an authenticated package index.

## Workflow wiring

Both copied workflows declare the lane statically — GitHub allows no expression in
`uses:` — and gate it on the descriptor's language-neutral `build_lane` output
([service descriptor](../architecture/service_descriptor.md)):

```yaml
  python-build:
    name: "🐍 Python Build"
    needs: [check-initialization, check-repo-state, check-paths, read-service-config]
    if: needs.read-service-config.outputs.build_lane == 'python' && ...
    steps:
      - uses: actions/checkout@...      # caller-owned, fetch-depth: 0
      - uses: ./.github/actions/python-build
        with:
          python_version: ${{ needs.read-service-config.outputs.python_runtime_version || '3.12' }}
          package_name:   ${{ needs.read-service-config.outputs.python_import_package }}
          test_extras:    ${{ needs.read-service-config.outputs.python_test_extras }}
          runtime_extras: ${{ needs.read-service-config.outputs.python_runtime_extras }}
```

`validate.yml` then feeds the same descriptor into the image jobs. The `docker-build`
action builds in **source mode** for the Python lane: no artifact is downloaded, no JAR is
resolved, `build/python/Dockerfile` is used, and `container.appModule` plus
`build.python.runtimeExtras` become validated build arguments:

| Job | Lane | `build_mode` | Dockerfile | Platforms |
| --- | --- | --- | --- | --- |
| `🐳 Docker Build (validate)` | Java | `java-artifact` | `build/Dockerfile` | `linux/amd64` |
| `🐳 Docker Build (validate)` | Python | `source` | `build/python/Dockerfile` | `linux/amd64` |
| `🐳 Docker Push` | Java | `java-artifact` | `build/Dockerfile` | `linux/amd64,linux/arm64` |
| `🐳 Docker Push` | Python | `source` | `build/python/Dockerfile` | `linux/amd64` |

The required `🐳 Docker Build` context is unchanged; its summary job now aggregates the
Python build and the selected image build, and a *present* Python descriptor can only pass
when both actually succeeded.

Deploy and integration-test stay Java-only and are explicitly gated on
`build_lane == 'java'`. The Python lane ends at a published GHCR image.

## Canonical Python Dockerfile

`build/python/Dockerfile` is the Python counterpart to the canonical Java image.

Key properties:

- **Digest-pinned multi-arch base** — `mcr.microsoft.com/azurelinux/base/python:3.12`
  pinned by manifest digest (amd64 + arm64). Template-side Dependabot bumps the digest and
  template-sync propagates it; forks never author a base bump.
- **Digest-pinned uv** — copied from the official `ghcr.io/astral-sh/uv` image instead of
  a network installer script.
- **Lock-based, non-editable install** — a cached dependency layer
  (`uv sync --frozen --no-dev --no-install-project`) followed by the project install
  (`uv sync --frozen --no-dev --no-editable`). Nothing is re-resolved at image build time,
  so the image ships the dependency set CI tested.
- **UID 1000 compatibility** — the virtual environment is copied `--chown=1000:1000` and
  the image runs as `USER 1000:1000`, matching the Stack chart's `runAsUser`. No
  `/etc/passwd` entry or `useradd` is required.
- **Baked uvicorn entrypoint** — the Stack chart cannot override a container command, so
  `build/python/docker-entrypoint.sh` runs `uvicorn` from validated environment values.
- **OCI labels** — source, revision, version, vendor, licence, and base image/digest.
- **Optional HEALTHCHECK** — a no-op unless `HEALTH_PATH` is baked in; Kubernetes still
  uses the chart's probes.

### Build arguments

| Argument | Default | Notes |
| --- | --- | --- |
| `RUNTIME_EXTRAS` | `""` | Comma-separated extras (e.g. `az`); each entry is character-validated inside the build. Supplied by the workflow from `build.python.runtimeExtras` |
| `APP_MODULE` | `""` | Required ASGI target, e.g. `wdmsworker.app:app`. Supplied by the workflow from `container.appModule`; the `docker-build` action refuses a source-mode build without it |
| `APP_PORT` | `8080` | Also used by `EXPOSE` |
| `APP_HOST` | `0.0.0.0` | |
| `UVICORN_WORKERS` | `1` | |
| `UVICORN_LOG_LEVEL` | `info` | Enum enforced at runtime |
| `UVICORN_ROOT_PATH` | `""` | Deployed API prefix, e.g. `/api/wdms-worker` |
| `HEALTH_PATH` | `""` | Enables the container HEALTHCHECK |
| `IMAGE_SOURCE` / `IMAGE_REVISION` / `IMAGE_VERSION` | `""` | OCI provenance labels |

### Package index credentials

Private index credentials must be provided as a BuildKit secret. The secret mount is
optional: the pilot builds without one, and the workflows pass no secret because the
pilot's dependencies resolve from public indexes.

```bash
docker build \
  --secret id=netrc,src="$HOME/.netrc" \
  --build-arg APP_MODULE=wdmsworker.app:app \
  --build-arg RUNTIME_EXTRAS=az \
  -f build/python/Dockerfile .
```

Never pass a credential-bearing URL as a build argument:

```bash
# Prohibited: build arguments are recorded in image history
docker build --build-arg PIP_INDEX_URL=https://user:token@example.org/simple .
```

Index *policy* — which index serves which distribution — belongs in the repository-owned
`uv.toml`/`pyproject.toml`, not in the template Dockerfile.

### Constraints

- The project must be installable as a distribution. Files that are not declared as
  package data are absent at runtime, because the runtime stage copies only the virtual
  environment.
- `requires-python` must admit 3.12; MCR publishes no Azure Linux 3.13 base image.
- The full build context is copied into the builder stage. Add a `.dockerignore` to keep
  `.git` and local virtual environments out of the build.
- arm64 legs build under emulation. Validate that wheels exist for both architectures
  before enabling multi-arch pushes for a dependency-heavy service.

## Local troubleshooting

```bash
# Recreate the CI test environment
uv sync --locked --extra dev

# Quality gates
uv run ruff check src
uv run ruff format --check .
uv run mypy src

# Suites, with the same report layout CI uses
uv run pytest tests/unit --junitxml=.spi-build-reports/junit/unit-junit.xml
uv run pytest tests/service --no-subprocess
uv run pytest tests/service

# Runtime (image) dependency set
uv sync --locked --no-dev --extra az
uv run --no-dev --extra az python -c "import wdmsworker"
```

A failing `uv lock --locked` means `uv.lock` no longer matches `pyproject.toml`: run
`uv lock` and commit the result.
