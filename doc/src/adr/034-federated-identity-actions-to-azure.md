# ADR-034: Federated Identity for Actions to Azure

## Context

- Deploy and integration-test workflows need authenticated access to Azure (AKS + Key Vault).
- Static `AZURE_CREDENTIALS` JSON secrets are long-lived credentials and a security risk — the same no-long-lived-credentials principle that replaced PATs with GitHub App tokens for in-repo automation ([ADR-029](029-github-app-authentication-strategy.md)).
- CI credentials must be isolated per service fork to bound blast radius.

## Decision

- Provision one User-Assigned Managed Identity per service fork and authenticate GitHub Actions through OIDC (`azure/login@v2`) instead of static JSON credentials. No static secrets stored in GitHub.
- Federated credential subjects required for the deploy/test path:
  - `repo:${ORG}/${SERVICE}:ref:refs/heads/*` (branch-push and internal-PR deploys)
  - `repo:${ORG}/${SERVICE}:pull_request` (internal PR events)
- Two further subjects are **not** granted by default (least privilege) — provision each only when it is actually exercised:
  - `repo:${ORG}/${SERVICE}:ref:refs/tags/*` — only if image push/retag moves to OIDC registry auth (the §7.4 ACR fallback). With public GHCR (ADR-033) the release re-tag uses `GITHUB_TOKEN`, so no tag-scoped Azure subject is used today.
  - `repo:${ORG}/${SERVICE}:environment:<name>` — only if the deploy job adopts the `environment:` job key for gating.
- Use three repo secrets as the handoff contract from onboarding to workflows — `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (`AZURE_CLIENT_ID` is also exposed as a repo variable for use in `if:` expressions and operator-facing diagnostics).
- Keep the ~20-step onboarding automated, split on the credential boundary:
  - **Cluster side (`osdu-spi-stack`, `spi onboard`)**: identity creation, federated credentials, AKS/KV RBAC, and the Kubernetes RoleBinding; writes the `AZURE_*` secrets to the target repo.
  - **Fork side (`osdu-spi`, extended `init.yml`)**: GHCR visibility, ruleset setup, and per-service repository variables.

## Consequences

- ✅ No long-lived Azure credential material stored in GitHub.
- ✅ Per-fork identity limits impact if one repository is compromised.
- ✅ Credential and repository setup responsibilities are explicit and automatable.
- ⚠️ Setup is operationally heavy without automation, so `spi onboard` + `init.yml` coordination is required.
- ⚠️ Subject-claim mismatches (`refs/heads`, `pull_request`, `refs/tags`) cause authentication failures that are tedious to debug — the `oidc-smoke-test.yml` operator tool exists to validate each subject in isolation.

## Alternatives Considered

- **Keep static `AZURE_CREDENTIALS` secrets** — rejected: long-lived secrets and a larger compromise surface.
- **One shared identity for all service forks** — rejected: poor blast-radius isolation and weaker per-service boundary control.

---

[← ADR-033](033-ghcr-as-service-image-registry.md) | :material-arrow-up: [Catalog](index.md)
