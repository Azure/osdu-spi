# ADR-036: Workflow Trust Boundaries for CI/CD

## Context

- New CI/CD jobs (`docker-push`, `deploy`, `integration-test`) hold credentials with real blast radius:
  - `docker-push` uses `packages: write` on GHCR.
  - `deploy` / `integration-test` use an Azure federated identity with AKS Cluster User, a least-privilege custom Role on the shared `osdu` namespace, and Key Vault Secrets User.
- The validate-only `docker-build` job runs with `permissions: contents: read` only (no GHCR write, no Azure login) and is therefore out of scope for this trust boundary.
- GitHub event contexts are not equally trusted; some (`pull_request_target`, external-fork PRs, dependabot PRs) can place attacker-controlled code in a context with secret access. Running the credential-bearing jobs there would expose the cluster federated identity to attacker code, risking compromise across the current service forks.

## Decision

Enforce a single trust-boundary model for credential-bearing jobs, per the event matrix below (authoritative):

| Event | Code source | Secret access | Deploy stages run? |
|---|---|---|---|
| `push` to `main` / `fork_integration` / `fork_upstream` | Repo HEAD (post-merge) | Yes | **Yes** |
| `pull_request` from internal branch (head repo == base repo) | PR HEAD | Yes | **Yes** |
| `pull_request` from external fork | PR HEAD | No (GH default) | No — would fail at `azure/login` anyway, but explicitly skipped to avoid noise |
| `pull_request_target` (base-repo context) | PR HEAD (checked out via explicit ref) | Yes | **No** — too dangerous; would let a PR exfiltrate the federated identity by running arbitrary code in a workflow with secret access |
| `dependabot[bot]` PR | PR HEAD | Limited (Dependabot secrets scope only) | No — `dependabot-validation.yml` is the dependency-update path |
| `workflow_dispatch` | Repo HEAD at chosen ref | Yes | **Yes**, but only when `inputs.force_full_pipeline == true` (the operator is the manual gate) |
| Tag push (release-please) | Tagged commit (already in `main`) | Yes | **No** — tag pushes go through `release.yml`, not `validate.yml`; `release.yml` only re-tags the existing image with the semver (via `GITHUB_TOKEN` to GHCR — no `azure/login`) and does not re-deploy. No tag-scoped Azure federated subject is exercised today; `refs/tags/*` is provisioned only if a future registry pivot (§7.4) moves image auth to OIDC. |
| Cascade workflow push to `fork_integration` | Cascade-resolved tree | Yes | Yes |

Credential-bearing jobs use this gating clause:

```yaml
if: |
  (
    needs.java-build.outputs.build_result == 'success' &&
    github.actor != 'dependabot[bot]' &&
    github.event_name != 'pull_request_target' &&
    github.event_name != 'workflow_dispatch' &&
    (github.event_name != 'pull_request' ||
     github.event.pull_request.head.repo.full_name == github.repository)
  ) || (
    github.event_name == 'workflow_dispatch' &&
    inputs.force_full_pipeline == true
  )
```

**Why the compact clause is sufficient.** This is equivalent to the longer form in design §5.5 that also checks `needs.check-initialization.outputs.initialized == 'true'` and `needs.check-repo-state.outputs.is_java_repo == 'true'`: these jobs `needs: [java-build]`, and `java-build` only emits `build_result == 'success'` when both upstream guards already held — so they are implied, not weakened. The clause is replicated verbatim on `deploy` and `integration-test` as **defense-in-depth**, rather than relying solely on skip-propagation from `docker-push`. The `workflow_dispatch && force_full_pipeline` half is the W13 operator escape hatch — the only way to force a full run when `paths-ignore` would otherwise skip a template-sync change. The `github.event_name != 'workflow_dispatch'` guard in the first half is load-bearing: without it a plain `workflow_dispatch` (e.g. the routine post-init validation run) satisfies the first half and pushes credential-bearing jobs without the `force_full_pipeline` opt-in. None of the four event guards may be dropped; dropping one is the only way to turn this into a credential-exposure path.

## Consequences

### Positive

- Cluster credentials are never exposed to attacker-controlled PR execution contexts.
- Trust assumptions are explicit and consistently applied across service forks.
- Cascade pushes keep deploy/test signal for upstream-integration risk.

### Negative

- External-fork PRs do not receive deploy/integration-test signal; maintainers must run trusted validation before merging external contributions (documented in CONTRIBUTING).
- The `if:` clause is verbose and easy to weaken accidentally when adding a new sensitive job — enforce via review template.

### Neutral

- `docker-build` continues to run broadly because it carries no sensitive credentials.
- Dependabot keeps its dedicated validation path outside cluster-credential workflows.

## Alternatives Considered

- **Allow `pull_request_target` for deploy/test** — rejected: direct credential-exfiltration risk.
- **Allow external-fork PR deploy/test** — rejected: untrusted-code boundary.
- **Move trust checks to reviewer convention only** — rejected: policy must be enforced in the workflow `if:` guard, not left to human vigilance.

---

[← ADR-035](035-azure-only-maven-profile.md) | :material-arrow-up: [Catalog](index.md)
