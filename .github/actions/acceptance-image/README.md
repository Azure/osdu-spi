# Acceptance Image Build

Builds the acceptance test image beside the service image (design §8, D5;
ADR-040): the suite's *source* from the same commit, with Maven dependencies
prewarmed at build time, published as
`ghcr.io/<org>/<service>-acceptance:sha-<sha>`, so "run the tests that shipped
with release X" stays one command months later:

```bash
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha>          # descriptor default: verify
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha> verify -Dtest=GetInfoApiTest
```

Arguments after the image are Maven argv tokens — the lane passes the
descriptor's `mavenArguments` array verbatim, never a shell string.

## What the image pins

The suite source and a warmed local repository — not dependency *resolution*.
The run is online by design; `dependency:go-offline` caches artifacts, not the
metadata a version range consults, so `--offline` fails wherever the upstream
graph carries ranges (`os-core-test` pulls `io.cucumber` ranges today) and a
later run can resolve a different set. Registry availability is still required.
A fork that needs a frozen set pins those ranges in its own suite pom.

## Suite selection

`resolve-suite.sh` picks the module baked into the image:

1. `.spi/service.yaml` present → the descriptor's `tests.acceptance.path`
   (validated by the resolver engine's `--contract-only` mode; a broken
   descriptor halts the build with exit 2).
2. No descriptor → the upstream default `<service>-acceptance-test`, the
   module the filter keeps (ADR-038, D8).
3. Default suite directory absent → a **clean skip**: the action reports
   `skipped=true` and builds nothing. No new required checks arm here.

A descriptor that names a suite path which is not in the checkout halts with
exit 2 instead of skipping. The default is a convention this action guesses at;
a descriptor path is an assertion the fork made, and a typo in it must never
read as "this fork has no acceptance suite".

The module must build standalone (the upstream acceptance modules are
parentless by design). The fork-owned `testing/<service>-test-azure` tree is
selectable via the descriptor where that module stands alone.

## Relationship to docker-build

Same conventions, shared scripts (ADR-028): `compute-metadata.sh`,
`compute-tags.sh`, and `set-package-visibility.sh` are called from the
sibling `docker-build` action, so tags (`sha-<12>`, branch snapshots),
lowercasing, and the public-visibility check behave identically under the
`<service>-acceptance` package name. Release retagging
(`<service>-acceptance:<version>`) is owned by `release.yml`, exactly as for
the service image.

Differences, both deliberate:

- **amd64-only.** This build RUNs Maven (`dependency:go-offline`); under
  QEMU arm64 emulation that costs many minutes per push for no consumer —
  CI runners are amd64 and Apple Silicon runs the amd64 image under
  emulation. A need for native arm64 local runs is the signal to revisit.
- **Own BuildKit cache scope** (`acceptance-image`): the suite layers share
  nothing with the service image.

## Build context

Unlike the service image — which copies only a prebuilt JAR — this build needs
repository source: `.mvn/community-maven.settings.xml` (the suite pom resolves
`${repo.releases.url}` through it) and the suite module itself. Forks inherit an
upstream-owned root `.dockerignore` that excludes `.*`, `**/*.yml` and `**/*.md`,
which would fail the `.mvn` COPY outright and silently strip yaml/markdown
resources from the suite. `build/acceptance.Dockerfile.dockerignore` — which
BuildKit prefers over the context-root file — is what keeps that context intact,
without touching the root file the service image and upstream both rely on.

## Local testing

Both commands run from the **fork checkout root** — `resolve-suite.sh` resolves
the suite directory, the descriptor, and the resolver relative to the working
directory, so running it from elsewhere always reports a skip.

```bash
# Suite resolution without Docker:
SERVICE_NAME=partition GITHUB_OUTPUT=/dev/stdout \
  .github/actions/acceptance-image/resolve-suite.sh

# Full image build:
docker build -f build/acceptance.Dockerfile --build-arg SUITE_DIR=partition-acceptance-test -t partition-acceptance:dev .
```

The regression harness lives at
`.github/local-actions/acceptance-image-tests/run-tests.sh`.
