# Acceptance Image Build

Builds the test-suite image beside the service image (design §8, D5;
ADR-040, ADR-041): every suite the descriptor declares, as *source* from the
same commit with its dependencies prewarmed at build time (Maven artifacts, or a
virtual environment for a pytest suite), published as
`ghcr.io/<org>/<service>-acceptance:sha-<sha>`, so "run the tests that shipped
with release X" stays one command months later:

```bash
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha>          # acceptance suite, default argv: verify
docker run --env-file .env ghcr.io/<org>/partition-acceptance:sha-<sha> verify -Dtest=GetInfoApiTest
docker run --env-file .env -e SUITE_DIR=testing ghcr.io/<org>/partition-acceptance:sha-<sha> -pl partition-test-azure -am test
```

`SUITE_DIR` is a `tests.<name>.path` from the descriptor and defaults to the
acceptance suite; the entrypoint refuses a path that is not baked in.

Arguments after the image are argv tokens for the suite's runner: Maven, or
pytest for a suite of type `pytest` (ADR-044). The lane passes the resolver's
`arguments` array verbatim, never a shell string. A Maven suite run with no
arguments runs `verify`.

A pytest suite runs `python -m pytest` from its virtual environment under `/opt/spi-venv/`
(the suite path with `/` as `+`), built at
image build time from the suite's `requirements` files through the Microsoft
package feed proxy (`PIP_INDEX_URL`). The install is retried, because the proxy
is a pull-through cache whose first fetch of an uncached file can fail.

## What the image pins

The suite source and a warmed local repository — not dependency *resolution*.
The run is online by design; the prewarm caches artifacts, not the
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
`surefire-reports`, `failsafe-reports` or `pytest-reports` directory, at any
depth, so a multi-module suite counts its submodules, and sums each
`<testsuite>` in it, since pytest nests them under `<testsuites>`. A pass needs a zero exit, at least one
test that was not skipped, and no failures or errors. The console is never
consulted: `-q` hides Maven's summary lines and `-Dmaven.test.failure.ignore`
turns a failing suite into a zero exit.

Each suite resolves its own dependency graph. A suite that is a Maven reactor
(the upstream `testing/` tree, whose provider module depends on a sibling core
module) is installed without tests first so the sibling resolves, then warmed
like the others.

The surefire and failsafe test providers (`surefire-junit4`,
`surefire-junit-platform`) are not part of that graph: each plugin fetches its
provider only when a run selects test classes. So the prewarm also runs
`verify` once with `-Dtest` and `-Dit.test` set to a method filter that selects
every class and no method. Each pom keeps its own plugin version and the
provider it would load at run time is fetched. `-DskipTests` cannot do this,
because a skipped plugin never loads a provider. The filter cannot go in an
excludes file: surefire and failsafe older than 3.0.0-M6 reject a method filter
there, and several upstream suites pin 3.0.0-M3 or M5.
`failIfNoSpecifiedTests=false` keeps a module with no test classes from failing
the build. A plain test class runs no method, but a suite runner
(`@RunWith(JUnitPlatform.class)`, a JUnit Platform `@Suite`, Cucumber) does not
apply the filter to its children. So the pass also sets
`-Dcucumber.execution.dry-run=true`. Surefire and failsafe hand it to the forked
JVM as a system property, which Cucumber 5 and later read through both the JUnit 4
runner (`@RunWith(Cucumber.class)`) and the JUnit Platform engine. Scenarios are
matched to steps but no hook or step body runs, so nothing calls a service. An
older Cucumber runner (`info.cukes`) does not read the property, but under the
JUnit 4 provider the method filter already removes its scenarios. Anything else
that runs, or errors, without the suite's environment is ignored there, and the
reports that pass leaves are deleted.

## Forward trust store

`forward-truststore.sh` builds the trust store for a suite that declares
`forwards`. In-cluster services such as Elasticsearch sign with a private CA,
and a test client that trusts only the JVM store rejects it. The script reads
the chain each forwarded port serves on `127.0.0.1`, keeps the CA certificates,
and imports them into a copy of the suite image's own JDK `cacerts` with the
image's `keytool`. The deploy lane mounts the result read-only at `/spi-trust`
and sets `JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=/spi-trust/cacerts`,
which every JVM in the container reads, surefire's forked test JVM included.
`CONTAINER_ENGINE=podman` runs the image with Podman instead of Docker; a rootless
Podman gets `--userns=keep-id` so the container can write the mounted directory.
`--host-jdk` in place of the image builds the store from the host JDK for a suite
Maven runs on the host.

```bash
# With a port-forward open on 9200:
.github/actions/acceptance-image/forward-truststore.sh ghcr.io/<org>/<svc>-acceptance@sha256:... /tmp/trust 9200
```

## Relationship to docker-build

Same conventions, shared scripts (ADR-028): `compute-metadata.sh`,
`compute-tags.sh`, and `set-package-visibility.sh` are called from the
sibling `docker-build` action, so tags (`sha-<12>`, branch snapshots),
lowercasing, and the public-visibility check behave identically under the
`<service>-acceptance` package name. Release retagging
(`<service>-acceptance:<version>`) is owned by `release.yml`, exactly as for
the service image.

Differences, both deliberate:

- **amd64-only.** This build RUNs Maven (`dependency:resolve`); under
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
# A fork whose pom declares Java 25 adds --build-arg JAVA_VERSION=25 (the default is 17).
```

The regression harness lives at
`.github/local-actions/acceptance-image-tests/run-tests.sh`.
