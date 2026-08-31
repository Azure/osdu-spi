# Acceptance Image Build

Builds the acceptance test image beside the service image (design §8, D5;
ADR-040): the suite's *source* from the same commit, with Maven dependencies
pre-resolved at build time, published as
`ghcr.io/<org>/<service>-acceptance:sha-<sha>`. "This release passed
acceptance" stays a re-runnable claim months later:

```bash
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha>          # descriptor default: verify
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha> verify -Dtest=GetInfoApiTest
```

Arguments after the image are Maven argv tokens — the lane passes the
descriptor's `mavenArguments` array verbatim, never a shell string.

## Suite selection

`resolve-suite.sh` picks the module baked into the image:

1. `.spi/service.yaml` present → the descriptor's `tests.acceptance.path`
   (validated by the resolver engine's `--contract-only` mode; a broken
   descriptor halts the build with exit 2).
2. No descriptor → the upstream default `<service>-acceptance-test`, the
   module the filter keeps (ADR-038, D8).
3. Suite directory absent → a **clean skip**: the action reports
   `skipped=true` and builds nothing. No new required checks arm here.

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

## Local testing

```bash
cd .github/actions/acceptance-image

# Suite resolution without Docker:
SERVICE_NAME=partition GITHUB_OUTPUT=/dev/stdout ./resolve-suite.sh

# Full image build from a fork checkout:
docker build -f build/acceptance.Dockerfile --build-arg SUITE_DIR=partition-acceptance-test -t partition-acceptance:dev .
```

The regression harness lives at
`.github/local-actions/acceptance-image-tests/run-tests.sh`.
