# Docker Build Action

Builds a service container image — from Maven JAR artifacts (Java) or from source plus the committed lockfile (Python) — and optionally pushes it to GHCR with SHA/branch tags and a public-visibility flip.

## Purpose

This action produces the canonical service image the engineering system syncs to every fork (ADR-037); services do not supply their own CI Dockerfile. A `build_mode` input selects how the image content arrives:

| `build_mode` | Image content | Dockerfile | Used by |
|--------------|---------------|-----------|---------|
| `java-artifact` (default) | Downloads the `build-artifacts` artifact from a preceding job and `COPY`s the resolved JAR (`JAR_FILE`) | `build/Dockerfile` | Java/Maven lane |
| `source` | Builds the checked-out tree plus `uv.lock`; **no artifact download and no JAR resolution** | `build/python/Dockerfile` | Python/uv lane |

It never runs Maven or uv itself. A single `push` input selects between two modes so one action can back both jobs in `validate.yml` (W5a):

- `push: 'false'` — build only. Validates that the Dockerfile compiles. **No GHCR login happens**, and the built image is kept only in the BuildKit/buildx cache (it is not pushed, nor loaded into the runner's Docker image store).
- `push: 'true'` — build, log in to GHCR, push, compute branch tags, and flip the package public.

> **`push` defaults to `'true'`.** The caller must set `push: 'false'` explicitly on the validate-only `docker-build` job; otherwise it will attempt a credentialed push.

## How It Fits

```
java-build   (uploads build-artifacts) → docker-build (build_mode: java-artifact)
python-build (source + uv.lock)        → docker-build (build_mode: source)
```

`validate.yml` (W5a) calls this action as two jobs:

| Job | `push` | Permissions | Trust boundary |
|-----|--------|-------------|----------------|
| `🐳 Docker Build` | `'false'` | `contents: read` | Runs on every event, including external-fork PRs |
| `🐳 Docker Push` | `'true'` | `packages: write` | Gated by the §5.5 `if:` clause (no `pull_request_target`, external-fork, or `dependabot[bot]`) — the gate lives on the **job**, not in this action |

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image_name` | **Yes** | — | Short service name (e.g. `partition`); set from `vars.SERVICE_NAME` |
| `build_mode` | No | `java-artifact` | `java-artifact` downloads the JAR artifact and resolves `JAR_FILE`; `source` builds the checked-out tree and skips both steps |
| `dockerfile_path` | No | `build/Dockerfile` | Dockerfile path relative to the repo root (ADR-037). In `source` mode the default resolves to `build/python/Dockerfile` |
| `build_context` | No | `.` | Docker build context directory |
| `registry` | No | `ghcr.io` | Container registry host |
| `org` | No | _(repo owner)_ | Registry org/owner; falls back to the workflow `github.repository_owner` at runtime when omitted |
| `jar_artifact_name` | No | `build-artifacts` | Name of the artifact containing the built JARs (java-artifact mode) |
| `jar_file` | No | — | Conventional path/glob of the service Spring Boot JAR (`validate.yml` passes `provider/<SERVICE_NAME>-azure/target/*-spring-boot.jar`, from `SERVICE_TARGET_JAR` or `SERVICE_NAME`). If it matches no file the action auto-discovers the Azure JAR (deviant modules like `entitlements-v2-azure`); `SERVICE_TARGET_JAR` only disambiguates a service that builds more than one. Ignored in `source` mode |
| `app_module` | Source mode | — | ASGI target baked into the Python image (`wdmsworker.app:app`), from the descriptor's `container.appModule`. Re-validated before it becomes a build argument |
| `runtime_extras` | No | — | Comma-separated extras installed into the runtime image (e.g. `az`), from `build.python.runtimeExtras` |
| `platforms` | No | — | Explicit platform list (e.g. `linux/amd64`). Empty keeps the Java defaults: amd64 on validate-only, amd64+arm64 on push |
| `build_args` | No | — | Optional extra `--build-arg` values (newline-separated `KEY=VALUE`). The JAR is passed via `jar_file` (resolved), not here. **Never pass `GITHUB_TOKEN` or any index credential here** — build arguments are recorded in image history |
| `push` | No | `'true'` | `'true'` logs in, pushes, tags, and flips visibility; `'false'` builds only |
| `github_token` | No | — | Token for GHCR login + visibility flip. Consumed only on the push path |

## Outputs

| Output | Description |
|--------|-------------|
| `image_repository` | Full registry path, e.g. `ghcr.io/<org>/<service>` (always set) |
| `image_digest` | `sha256:…` digest of the pushed image (prefix already included). **Empty string when `push != 'true'`** |
| `image_tags` | Comma-separated tags (log use only) — deploy stages must use `image_digest`, not a tag |

## Tagging Strategy

| Tag | When |
|-----|------|
| `:sha-<short-sha>` | Always (12-char SHA; immutable, browsable) |
| `:<branch>-snapshot` | `push: 'true'` on a protected branch (`main`, `fork_integration`, `fork_upstream`) |
| `:<version>` | Applied by `release.yml` (W7), **never** by this action |

## Security Model

- `push: 'false'` skips the GHCR login step entirely — the `GITHUB_TOKEN` is never used for registry auth in build-only mode, and the visibility flip is skipped.
- The build step never receives `GITHUB_TOKEN` as a `--build-arg` or env var; the token reaches only the login and visibility-flip steps.
- **No credential is ever a build argument.** Build arguments are recorded in image history, so a private package index is configured through the Python Dockerfile's optional BuildKit `netrc` secret mount instead. The pilot registry is public and the workflows pass no secret.
- Source-mode values come from the fork-owned service descriptor, which constrains them by schema; `prepare-build-args.sh` re-validates `app_module`, `runtime_extras`, `platforms` and the OCI revision/version before they reach a `--build-arg` (defence in depth against a descriptor-shaped injection).
- The visibility flip is idempotent (skips when already public) and **soft-fail** — a permission error logs a warning with a `gh workflow run settings-apply.yml` remediation hint but never fails the build.
- The trust boundary (ADR-036) lives on the `docker-push` **job** in `validate.yml`, not in this action.

## Platforms

By default the `push: 'true'` (release) path builds multi-arch for `linux/amd64` and `linux/arm64`; the `arm64` leg is emulated via QEMU on the amd64 runner. Because the canonical Java Dockerfile (ADR-037) has no `RUN` steps, emulation cost is limited to the arm64 base-layer pull plus the arch-independent JAR copy — so arm64 is still fully validated before release. The `push: 'false'` (validate-only) path builds `linux/amd64` only.

A caller may pin the list with `platforms`. The Python lane passes `linux/amd64` for both jobs: the source-mode image installs dependencies inside the build, so an emulated arm64 leg would compile every non-wheel dependency under QEMU. QEMU is set up only when the effective platform list contains a non-amd64 entry.

`provenance: false` keeps the pushed manifest a clean index (no `unknown/unknown` attestation entry), so a bare `docker pull` resolves natively on Apple Silicon and amd64 alike — without it, a single-arch build still publishes as an index and `docker pull` fails to match on arm64.

## Digest Usage

Deploy references are composed as `${image_repository}@${image_digest}`. The digest already includes the `sha256:` prefix — **do not** prepend it again, or the reference becomes `@sha256:sha256:…` and the kubelet fails to pull.

## Scripts

| Script | Role |
|--------|------|
| `compute-metadata.sh` | Lowercases `registry/org/image_name`; emits `short_sha` |
| `compute-tags.sh` | Emits `image_tags` (comma) + `docker_tags` (newline, for build-push) |
| `resolve-jar.sh` | Resolves the service JAR: honours the conventional/override path, else auto-discovers the Azure Spring Boot JAR (deviant modules). java-artifact mode only |
| `prepare-build-args.sh` | Validates `build_mode`/`platforms`/source-mode values and emits the Dockerfile, effective platform list, QEMU requirement and `--build-arg` set |
| `set-package-visibility.sh` | Org/user-aware, idempotent, soft-fail GHCR public flip |

## Local Testing

Each script writes to `$GITHUB_OUTPUT` when set and echoes `key=value` to stdout, so it runs standalone:

```bash
GITHUB_SHA=abc123def4567 GITHUB_OUTPUT=/dev/stdout \
  ./compute-metadata.sh ghcr.io my-org partition

GITHUB_OUTPUT=/dev/stdout \
  ./compute-tags.sh ghcr.io/my-org/partition abc123def456 main true

BUILD_MODE=source APP_MODULE=wdmsworker.app:app RUNTIME_EXTRAS=az \
  PLATFORMS=linux/amd64 GITHUB_OUTPUT=/dev/stdout ./prepare-build-args.sh

GITHUB_TOKEN=*** ./set-package-visibility.sh my-org partition
```

The full action cannot be exercised in this template repository: a change under `.github/` is treated as config-only by the build's path check, so no Maven/Docker build runs here. End-to-end runtime proof happens on a downstream service fork.

## Related

- ADR-010 (YAML-safe shell scripting), ADR-013 (reusable actions), ADR-028 (script extraction), ADR-033 (GHCR registry), ADR-036 (workflow trust boundaries), ADR-037 (canonical service Dockerfile)
