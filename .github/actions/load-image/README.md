# Load Image Build

Builds the shared-schemas loader image beside the service image (ADR-042):
the OSDU shared schemas under `deployments/shared-schemas/` and upstream's
provider-neutral loader, from the same commit as the service image, published
as `ghcr.io/<org>/<service>-load:sha-<sha>`. The stack's `schema-load` Job runs
it at the schema service's commit, and a developer can run the same load by
hand:

```bash
docker run -e SCHEMA_URL=https://<host>/api/schema-service/v1 -e BEARER_TOKEN=<token> \
  ghcr.io/<org>/schema-load:sha-<sha>
docker run -e SCHEMA_URL=... -e BEARER_TOKEN=... ghcr.io/<org>/schema-load:sha-<sha> -e   # loader argv pass-through
```

Arguments after the image are appended to `DeploySharedSchemas.py` verbatim.

## Trigger

`resolve-payload.sh` decides whether the image can build. Only the schema
service carries a payload today, and the decision reads files, not the
repository name:

1. `deployments/shared-schemas/` absent (every fork but schema) → a **clean
   skip**: `skipped=true`, reason on the step summary, exit 0. No login, no
   Docker, no token demanded.
2. Payload present and `deployments/scripts/{DeploySharedSchemas.py,
   Utility.py, requirements.txt}` all present → build.
3. Payload present but a loader file missing → exit 2 naming the file. That
   is an upstream rename, and the fork's filter `expected_kept` entries catch
   the same rename earlier, on the sync (ADR-038).

The paths are hard-coded in the script, `build/load.Dockerfile`, and its
sidecar dockerignore alike; there is no override input, because the three
would drift.

## What the image contains

Only the payload and the three loader files, on a digest-pinned
`python:3.12-slim` base, under a non-root user. `build/load.Dockerfile.dockerignore`
starts from `*` and re-admits exactly the copied paths, so the provider folders
under `deployments/scripts/` (`azure/`, `google/`, `ibm/`, `schema-cleaner/`)
and the service source never enter the build context. Upstream deleting its
Azure scripts changes nothing here.

The `deployments/` layout is preserved because `Utility.path_to_deployments()`
resolves the payload relative to the loader's own file.

## Entrypoint

`build/load-entrypoint.sh`:

1. Waits for `${SCHEMA_URL}/info` to answer 200, up to `WAIT_SECONDS`
   (default 2700).
2. Uses `BEARER_TOKEN` when set. Otherwise exchanges the workload identity
   token (`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_FEDERATED_TOKEN_FILE`,
   as the AKS webhook injects them) at Entra's v1 endpoint for
   `TOKEN_RESOURCE` (default `https://management.azure.com/`), with the
   standard library only. The v1 endpoint is deliberate: the services read
   `appid`, which v2 tokens omit.
3. Runs `DeploySharedSchemas.py -u ${SCHEMA_URL}/schemas/system`. The loader's
   exit status is the verdict; it treats an already PUBLISHED schema as loaded,
   so a re-run against a loaded service passes.

## Relationship to docker-build and acceptance-image

Same conventions, shared scripts (ADR-028): `compute-metadata.sh`,
`compute-tags.sh`, and `set-package-visibility.sh` from the sibling
`docker-build` action, so tags (`sha-<12>`, branch snapshots), lowercasing, and
the public-visibility check behave identically under the `<service>-load`
package name. Release retagging (`<service>-load:<version>`) is owned by
`release.yml` and pruning by `ghcr-retention.yml`, both alongside the
acceptance image.

Unlike the acceptance image, push builds cover `linux/amd64,linux/arm64` like
the service image: the image is pure Python, so the emulated arm64 leg costs
seconds, and the Job runs on the same node pool as the service. Own BuildKit
cache scope (`load-image`).

## Local testing

From the fork checkout root:

```bash
# Payload resolution without Docker:
GITHUB_OUTPUT=/dev/stdout .github/actions/load-image/resolve-payload.sh

# Full image build:
docker build -f build/load.Dockerfile -t schema-load:dev .
```

The regression harness lives at
`.github/local-actions/load-image-tests/run-tests.sh`.
