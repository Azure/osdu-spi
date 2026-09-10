# Acceptance Image Build

Builds the test-suite image beside the service image (design §8, D5;
ADR-040, ADR-041): every suite the descriptor declares, as *source* from the
same commit with Maven dependencies prewarmed at build time, published as
`ghcr.io/<org>/<service>-acceptance:sha-<sha>`, so "run the tests that shipped
with release X" stays one command months later:

```bash
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha>          # acceptance suite, default argv: verify
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha> verify -Dtest=GetInfoApiTest
docker run --env-file .env -e SUITE_DIR=testing ghcr.io/<org>/partition-acceptance:sha-<sha> -pl partition-test-azure -am test
```

`SUITE_DIR` is a `tests.<name>.path` from the descriptor and defaults to the
acceptance suite; the entrypoint refuses a path that is not baked in.

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

`resolve-suite.sh` picks the modules baked into the image:

1. `.spi/service.yaml` present → every `tests.<name>.path` the descriptor
   declares, acceptance first (validated by the resolver engine's
   `--contract-only` mode; a broken descriptor halts the build with exit 2).
2. No descriptor → the upstream default `<service>-acceptance-test`, the
   module the filter keeps (ADR-038, D8).
3. Default suite directory absent → a **clean skip**: the action reports
   `skipped=true` and builds nothing.

A descriptor that names a suite path which is not in the checkout halts with
exit 2 instead of skipping. The default is a convention this action guesses at;
a descriptor path is an assertion the fork made, and a typo in it must never
read as "this fork has no acceptance suite".

## Suite verdict

`suite-verdict.py` decides whether one suite run passed. The deploy lane copies
the suite directory out of the container after `docker run` returns and hands
the script the exit code and that directory. It reads every `TEST-*.xml` under a
`surefire-reports` or `failsafe-reports` directory, at any depth, so a
multi-module suite counts its submodules. A pass needs a zero exit, at least one
test that was not skipped, and no failures or errors. The console is never
consulted: `-q` hides Maven's summary lines and `-Dmaven.test.failure.ignore`
turns a failing suite into a zero exit.

Each suite resolves its own dependency graph. A suite that is a Maven reactor
(the upstream `testing/` tree, whose provider module depends on a sibling core
module) is installed without tests first so the sibling resolves, then warmed
like the others.

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

Unlike the service image, which copies only a prebuilt JAR, this build needs
repository source: `.mvn/community-maven.settings.xml` (the suite pom resolves
`${repo.releases.url}` through it), the descriptor, and the suite modules.
Forks inherit an upstream-owned root `.dockerignore` that excludes `.*`, which
would strip `.mvn` and `.spi`; `build/acceptance.Dockerfile.dockerignore`,
which BuildKit prefers over the context-root file, keeps that context intact
without touching the root file the service image and upstream both rely on.

The whole checkout enters the build context, but only the declared suites,
`.mvn`, and `.spi` reach the final image: a first stage copies them out, so the
service source never ships and scanners see only what the suites resolve.

## Local testing

Both commands run from the **fork checkout root** — `resolve-suite.sh` resolves
the suite directory, the descriptor, and the resolver relative to the working
directory, so running it from elsewhere always reports a skip.

```bash
# Suite resolution without Docker:
SERVICE_NAME=partition GITHUB_OUTPUT=/dev/stdout \
  .github/actions/acceptance-image/resolve-suite.sh

# Full image build (space-separated suite paths, the first is the run-time default):
docker build -f build/acceptance.Dockerfile --build-arg "SUITE_DIRS=partition-acceptance-test testing" -t partition-acceptance:dev .
```

The regression harness lives at
`.github/local-actions/acceptance-image-tests/run-tests.sh`.
