# ADR-042: Paired Loader Image from the Service Fork

## Status

Accepted (2026-09-22)

## Context

The stack seeds the data an environment configures for itself: partitions, entitlement groups, legal tags. The OSDU shared schemas are different. They are versioned with the schema service source under `deployments/shared-schemas/`, and the stack's `schema-load` Job registers them with upstream's `DeploySharedSchemas.py`, paired to the schema service's commit (stack ADR-017). That loader image is built today by upstream's Azure-only CI job, which upstream is removing. Stack ADR-033 already names a fork-built `ghcr.io/<owner>/schema-load` at the schema commit as the precondition for promoting schema to a fork canonical; nothing in the template produced one.

Schema is the only service that carries such a payload. Whatever builds it must reach the schema fork through template sync (ADR-037) without adding a workflow, job, secret, variable, or required check to the other forks.

## Decision

**Files versioned with the service that an environment must load ship as a paired image built by the fork's own CI, from the same commit as the service image, with template-owned packaging. The trigger is what the filtered checkout contains, not a descriptor field.**

### The payload arrives through the filter

The schema fork flips `deployments: strip` to `keep` in its filter config (ADR-038) and lists `deployments/shared-schemas` and `deployments/scripts/DeploySharedSchemas.py` under `expected_kept`, so an upstream rename halts the sync instead of producing an empty image. The filter classifies top-level entries only, so the whole folder arrives. The provider and helper files inside it (`scripts/azure/`, `google/`, `ibm/`, `schema-cleaner/`, the Google Cloud tooling) are not referenced by any SPI-owned file, and upstream deleting them changes nothing here.

### The template owns the packaging

`build/load.Dockerfile` copies the payload and the three neutral loader files (`DeploySharedSchemas.py`, `Utility.py`, `requirements.txt`) onto a digest-pinned Python base, preserving the `deployments/` layout the loader resolves its payload from. Its sidecar `.dockerignore` admits nothing else into the build context. `build/load-entrypoint.sh` waits for the service's `/info`, takes `BEARER_TOKEN` or exchanges the workload identity token with Entra using the standard library, and runs the loader against `/schemas/system`. The loader's exit status is the verdict; it treats an already PUBLISHED schema as loaded, so a re-run passes. Both files sync with `build/`, and Dependabot bumps the base digest in the template.

### One step in the two image jobs

`.github/actions/load-image` follows the acceptance-image action. Its first step resolves the payload and every later step is conditional on it: no payload is exit 0 with a reason, a payload whose loader file is missing is exit 2 naming the file. The image is `ghcr.io/<owner>/<service>-load`, named, tagged, and visibility-checked with the service image's scripts, pushed only from `docker-push` under the ADR-036 gate. `release.yml` retags it at the semver after the acceptance image, and `ghcr-retention.yml` prunes the service, acceptance, and load packages under one policy so the images built from one commit age out together.

### The stack pairs by commit

The stack selects the loader at the service's commit, by digest, and supplies the service URL and workload identity at run time (stack ADR-033). No script is mounted over the image.

## Consequences

### Positive

- The loader outlives upstream's Azure pipeline, and service and loader are paired by construction rather than looked up by tag.
- Ten forks see one added step that resolves a directory and stops.

### Negative

- A third canonical Dockerfile, and a Python base image family under Dependabot beside the JDK and Maven ones.
- The schema fork keeps upstream's unused provider files in its tree; a nested `deployments/scripts` classification in the filter is the follow-up if they become a review burden.

### Neutral

- Acceptance and load share the "build beside the service, skip when absent" shape. A shared step is factored when a third instance appears, not before.

## Alternatives Considered

- **Upstream's provider-neutral loader image** (`core-plus-bootstrap-schema`). Depends on a community pipeline for another distribution, its entrypoint contract changed twice in one summer, and its 17-tag retention is outside our control.
- **Fetch the schemas at run time.** Separates the payload from the service release and adds a GitLab dependency at deploy time.
- **A stack-owned generic loader.** The stack would need the payload from somewhere, which turns environment machinery into a build system.
- **Load the schemas from inside the service at startup.** A Java feature in fork-owned provider code, replica races at boot, and no CSP upstream has done it.
- **A descriptor field as the trigger.** The payload is upstream-owned and its presence is already decided by the filter; a second declaration in `.spi/service.yaml` would drift from it.
