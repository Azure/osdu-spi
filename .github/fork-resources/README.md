# OSDU <Service> Service for Azure

[![Release](https://img.shields.io/github/v/release/Azure/osdu-spi-<service>)](https://github.com/Azure/osdu-spi-<service>/releases)
[![Validate](https://github.com/Azure/osdu-spi-<service>/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Azure/osdu-spi-<service>/actions/workflows/validate.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> [!NOTE]
> Shared service code comes from the [OSDU community upstream](<upstream-url>); the [OSDU documentation](<docs-url>) covers the API.

<One or two sentences: what the service does for a caller. No implementation detail.>

## At a glance

| | |
|---|---|
| API base path | `/api/<service>/v1/` |
| Swagger UI | `/api/<service>/v1/swagger` |
| Health | `:<management-port>/actuator/health` |
| Depends on | <Partition, Entitlements, ...> |
| Azure resources | <Cosmos DB, Storage, Service Bus, Redis, Key Vault, ...> |
| Deployed by | [OSDU SPI Stack](https://github.com/Azure/osdu-spi-stack) (`software/stacks/osdu/services/<service>.yaml`) |

## Repository layout

[CONTRIBUTING.md](CONTRIBUTING.md) explains where each kind of change belongs.

| Path | Owner | Contents |
|---|---|---|
| `<service>-core/` | OSDU upstream | Shared service code |
| `provider/<service>-azure/` | This repository | Azure provider |
| `<service>-acceptance-test/` | OSDU upstream | End-to-end suite run against a deployed environment |
| `testing/<service>-test-azure/` | This repository | Legacy Azure integration tests |
| `.spi/service.yaml` | This repository | How CI deploys and tests the service on SPI Stack |

## Build

Requires Java 17 and Maven 3.6.3+. OSDU dependencies resolve from the public community registry through the settings file in `.mvn`:

```bash
mvn --settings .mvn/community-maven.settings.xml -P core,azure clean install
```

The runnable jar lands at `provider/<service>-azure/target/<artifact>-*-spring-boot.jar`.

## Configuration

SPI Stack sets the service's environment from two places: the shared `osdu-config` ConfigMap and the service's own entry in [`services/<service>.yaml`](https://github.com/Azure/osdu-spi-stack/blob/main/software/stacks/osdu/services/<service>.yaml). Those files are the contract; the tables below list what <Service> actually reads from them.

<List only variables the provider reads: trace each through `provider/<service>-azure/src/main/resources/application.properties`, and confirm values against a running deployment.>

**Shared, from `osdu-config`:**

| Variable | Purpose |
|---|---|
| `AZURE_TENANT_ID` | Entra tenant |
| `AAD_CLIENT_ID` | Application ID that caller tokens are issued for |
| `KEYVAULT_URI` | Central Key Vault |
| <...> | |

**Specific to <Service>**, from `services/<service>.yaml`:

| Variable | Value on SPI Stack | Purpose |
|---|---|---|
| `SERVER_SERVLET_CONTEXTPATH` | `/api/<service>/v1/` | API base path |
| `AZURE_ISTIOAUTH_ENABLED` | `true` | Trust the mesh's token validation |
| `AZURE_PAAS_WORKLOADIDENTITY_ISENABLED` | `true` | Authenticate to Azure with workload identity |
| `PARTITION_SERVICE_ENDPOINT` | `http://partition/api/partition/v1` | Per-partition resource lookup |
| <...> | | |

The service authenticates to Azure with workload identity, which injects `AZURE_CLIENT_ID` and a federated token; there are no client secrets. Per-partition resources are resolved at request time through the Partition service.

## Test

| Suite | Where | Runs in CI | Run it yourself |
|---|---|---|---|
| Unit | `<service>-core`, `provider/<service>-azure` | Pull requests (Java Build) | `mvn ... install` from [Build](#build) |
| Acceptance | [`<service>-acceptance-test`](<service>-acceptance-test/README.md) | Pull requests, against SPI Stack (Deploy and Test) | `spi test <service>` |
| Integration | `testing/<service>-test-azure` | <Yes / No> | <How, or why not> |

CI runs these on pull requests from this repository that change code. Documentation-only changes skip the build, and pull requests from forks build without deploying.

**Acceptance** proves a change on real infrastructure before it merges. It calls the deployed service through the gateway as a privileged test identity, and the bindings in `.spi/service.yaml` supply its inputs. Against an environment you are connected to:

```bash
spi test <service>                   # the image and suite the environment is running
spi test <service> --source .        # this checkout's suite and descriptor
```

**Integration** <state whether it runs against SPI Stack, and if not, what it needs that the stack does not issue.>

To call the API by hand, `spi token` mints a bearer token:

```bash
curl -H "Authorization: Bearer $(spi token)" -H "data-partition-id: <partition>" \
  https://<gateway>/api/<service>/v1/<endpoint>
```

## Deploy

For a pull request from this repository that changes code, CI publishes the service image and its test suite image, `osdu-spi-<service>-acceptance`, to GHCR, and the Deploy and Test lane borrows an SPI Stack environment, runs the new image there, proves it with the acceptance suite, and restores the environment's own image. When that lane runs and passes, the change is proven on real infrastructure before it merges; the Validation Summary on the pull request shows whether it ran. This repository does not own infrastructure; SPI Stack does.

To try a build by hand on an environment you are connected to, pin it by digest and release the pin when done:

```bash
spi service pin <service> --image ghcr.io/azure/osdu-spi-<service>@sha256:<digest>
spi service reset <service>
```

## Service notes

<Optional. Azure-specific behavior a reader needs that the upstream docs do not cover: reserved names, data model, feature flags the stack overrides and why. Delete the section if there is nothing.>

## License

Copyright © Microsoft Corporation

Licensed under the [Apache License 2.0](LICENSE).
