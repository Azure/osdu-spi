# ADR-044: Pytest Acceptance Suites

## Status

Accepted (2026-11-02)

## Context

The descriptor (ADR-040) admits one suite type, `maven`, and the acceptance image prewarms and runs Maven. Unit, crs-catalog and crs-conversion ship their acceptance suites as pytest against a swagger-generated Python client, so none of the three can declare a suite and their lanes run deploy only. Upstream runs these suites on Azure inside a Maven image with Python added.

Python packages cannot be fetched from the public index on the networks these suites run from. They come through the Microsoft package feed proxy, which is a pull-through cache: the first fetch of an uncached file can fail and a retry succeeds.

The suites take the host of the gateway without its scheme (`VIRTUAL_SERVICE_HOST_NAME`) and build the URL themselves. No binding source yields that value.

## Decision

**A suite may be `type: pytest`. Its requirements are installed into a per-suite virtual environment when the acceptance image is built, from the Microsoft package feed proxy, and the entrypoint runs pytest from that environment.**

### Descriptor

A pytest suite names its `requirements` files, relative to the suite path (default `requirements.txt`), and optional `pytestArguments`, argv tokens as for `mavenArguments`. Each type's keys are refused on the other type. `forwards` stays Maven-only, because the forwarded CA reaches the suite through a JVM trust store.

A new fact source, `gatewayHost`, is the host and port of `base_url`.

The resolver publishes `arguments` for either type and keeps `maven_arguments`, empty for a pytest suite, so consumers of Maven suites are unchanged. The contract report carries `suite_specs`, each suite's path, type and requirements, for the image build.

### Image

One image per fork still carries every suite. When the descriptor declares a pytest suite, the build installs the distribution's `python3` and `python3-venv` on the Maven base and creates a virtual environment under `/opt/spi-venv/` for each pytest suite, named by its path with `/` as `_`, installing its requirements and pytest with `PIP_INDEX_URL` defaulting to the proxy. The install is retried as a whole, since pip does not retry an HTTP error status. Maven suites build as before and the Maven prewarm skips pytest suites.

The image carries no `CMD`. The entrypoint selects the runner by suite: pytest writes JUnit XML to `target/pytest-reports/TEST-pytest.xml`, and a Maven suite run with no argv defaults to `verify`.

### Verdict

`suite-verdict.py` reads `pytest-reports` beside the Surefire and Failsafe directories and sums every `<testsuite>`, which pytest nests under `<testsuites>`. The pass rule is unchanged: a zero exit, at least one test run, and no failures or errors.

## Consequences

### Positive

- The three Python-suite services can declare acceptance suites and gain a proving lane.
- A run needs no package index; a laptop pulls the image from GHCR only.
- Maven-only forks build the same image as before.

### Negative

- The Python version is the base image's distribution Python, 3.12 today, not a pin the fork chooses.
- A suite with steps outside pytest, such as crs-catalog's fixture cleanup in its runner script, needs those steps expressed some other way before it can declare its suite.
- `spi test` in the stack cannot run a pytest suite until it reads `arguments` and the suite type, and its report reader learns the pytest location.

## Alternatives Considered

- **Wrap pytest in a Maven module in each fork.** Hides a Python suite behind a fake `pom.xml`, repeated in three forks.
- **A separate Python image per fork.** A second image line for the stack to pair and the release to tag, for no isolation the virtual environments do not already give.
- **Run the suite's own `run-acceptance-tests.sh`.** It creates a virtual environment and installs from the public index at run time.
- **Install requirements when the suite runs.** Every run depends on the proxy, and a cold cache fails a test run instead of an image build.

---

[← ADR-043](043-fork-source-attribution-notice.md) | :material-arrow-up: [Catalog](index.md)
