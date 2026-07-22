# ADR-034: Federated Identity for Actions to Azure

## Context

- Deploy and integration-test workflows need authenticated access to Azure (AKS + Key Vault).
- Negative authorization tests need a second valid Entra token whose caller has
  no OSDU entitlements.
- Static `AZURE_CREDENTIALS` JSON secrets are long-lived credentials and a security risk — the same no-long-lived-credentials principle that replaced PATs with GitHub App tokens for in-repo automation ([ADR-029](029-github-app-authentication-strategy.md)).
- CI credentials must be isolated per service fork to bound blast radius.

## Decision

- Provision one User-Assigned Managed Identity per service fork and authenticate GitHub Actions through OIDC (`azure/login@v2`) instead of static JSON credentials. No static secrets stored in GitHub.
- Federated credential subjects required for the deploy/test path:
  - explicit `repo:${ORG}/${SERVICE}:ref:refs/heads/<branch>` subjects for
    `main`, `fork_integration`, and `fork_upstream`
  - `repo:${ORG}/${SERVICE}:pull_request` (internal PR events)
- Two further subjects are **not** granted by default (least privilege) — provision each only when it is actually exercised:
  - `repo:${ORG}/${SERVICE}:ref:refs/tags/*` — only if image push/retag moves to OIDC registry auth (the §7.4 ACR fallback). With public GHCR (ADR-033) the release re-tag uses `GITHUB_TOKEN`, so no tag-scoped Azure subject is used today.
  - `repo:${ORG}/${SERVICE}:environment:<name>` — not currently used.
- Use three repo secrets as the handoff contract from onboarding to workflows — `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (`AZURE_CLIENT_ID` is also exposed as a repo variable for use in `if:` expressions and operator-facing diagnostics).
- Provision one additional UAMI named `spi-ci-no-data-access` per Stack
  environment when the onboarded service opts into negative-authorization
  tests. It is shared by those repositories because it deliberately has no
  Azure RBAC and no OSDU entitlements; compromising it grants no positive data
  or deployment access. Services without a negative-access test do not receive
  its client ID and do not mint its token.
- The shared identity uses the same four exact pull-request/branch subjects as
  the service identity, but only for repositories whose active test profile
  requires a negative caller. Azure permits at most 20 federated credentials per
  UAMI, so this model supports five opted-in repositories before the identity
  must be sharded or flexible federation becomes generally available.
  `spi onboard` writes
  `NO_DATA_ACCESS_TESTER_CLIENT_ID`, `NO_DATA_ACCESS_TESTER_PRINCIPAL_ID`,
  `NO_DATA_ACCESS_TESTER_IDENTITY_NAME`, and `NO_DATA_ACCESS_TOKEN_ENV` as
  non-secret repository variables only for opted-in services.
- The integration-test action requests a fresh GitHub OIDC assertion and logs
  the shared identity into a temporary `AZURE_CONFIG_DIR` with
  `--allow-no-subscriptions`. It mints and masks
  the configured token env, then removes the temporary Azure CLI state without
  replacing the service identity's authenticated session. Partition, File,
  Storage, Register, Secret, and EDS-DMS use
  `NO_DATA_ACCESS_TESTER_ACCESS_TOKEN`; Workflow uses `NO_ACCESS_USER_TOKEN`,
  matching current ADME pipelines.
- Keep the ~20-step onboarding automated, split on the credential boundary:
  - **Cluster side (`osdu-spi-stack`, `spi onboard`)**: identity creation, federated credentials, AKS/KV RBAC, and the Kubernetes RoleBinding; writes the `AZURE_*` secrets to the target repo.
  - **Fork side (`osdu-spi`, extended `init.yml`)**: GHCR visibility, ruleset setup, and per-service repository variables.

## Consequences

- ✅ No long-lived Azure credential material stored in GitHub.
- ✅ Per-fork identity limits impact if one repository is compromised.
- ✅ The shared negative-test identity authenticates as a real caller while
  remaining authorization-empty, so a 403 tests entitlements rather than an
  invalid-token 401 path.
- ✅ Credential and repository setup responsibilities are explicit and automatable.
- ⚠️ Setup is operationally heavy without automation, so `spi onboard` + `init.yml` coordination is required.
- ⚠️ Subject-claim mismatches (`refs/heads`, `pull_request`, `refs/tags`) cause authentication failures that are tedious to debug — the `oidc-smoke-test.yml` operator tool exists to validate each subject in isolation.

## Alternatives Considered

- **Keep static `AZURE_CREDENTIALS` secrets** — rejected: long-lived secrets and a larger compromise surface.
- **One privileged shared identity for all service forks** — rejected: poor
  blast-radius isolation and weaker per-service boundary control. The shared
  no-data-access identity is a narrow exception because it receives neither
  deployment RBAC nor entitlements.

---

[← ADR-033](033-ghcr-as-service-image-registry.md) | :material-arrow-up: [Catalog](index.md)
