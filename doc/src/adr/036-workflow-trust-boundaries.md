# ADR-036: Workflow Trust Boundaries for CI/CD

## Status

Accepted (2026-06-04)

## Context

- Two jobs in `validate.yml` hold a credential with write reach: `docker-push` with `packages: write` on GHCR, and `deploy-test` with the fork's Azure federated identity for the attached stack (ADR-041). This ADR fixes the boundary both inherit.
- The validate-only `docker-build` job runs with `permissions: contents: read` only (no GHCR write, no Azure login) and is out of scope for this boundary. It never takes the `pull_request_target` lane and never sets a checkout ref: CodeQL reports a PR-head ref in a read-only job of a `workflow_dispatch` workflow as cache poisoning in every fork (#164), and the job has no need for one.
- GitHub event contexts are not equally trusted. `pull_request_target`, external-fork PRs, and Dependabot PRs can place attacker-controlled code in a context with secret access. Running a credential-bearing job there would hand that credential to the PR author.

## Decision

Credential-bearing jobs run only in the trusted contexts below. The "runs?" column applies to `docker-push` and to `deploy-test`, which additionally skips when the fork is not onboarded or declares no suite.

| Event | Code source | Secret access | Credential-bearing job runs? |
|---|---|---|---|
| `push` to `main` or `fork_integration` | Repo HEAD (post-merge) | Yes | Yes |
| `push` to `fork_upstream` | Repo HEAD | Yes | No; a filter-mode tree has no Azure JAR to package, and the cascade PR validates the image |
| `pull_request` from an internal branch (head repo equals base repo) | PR HEAD | Yes | Yes |
| `pull_request` from an external fork | PR HEAD | No (GitHub default) | No; explicitly skipped rather than left to fail |
| `pull_request_target` | PR HEAD via explicit ref | Yes | No; a PR could exfiltrate the credential by running arbitrary code with secret access |
| `dependabot[bot]` PR | PR HEAD | Dependabot secrets scope only | No; `dependabot-validation.yml` is the dependency-update path |
| `workflow_dispatch` | Repo HEAD at chosen ref | Yes | No today. The clause reserves a `force_full_pipeline` operator override, but `validate.yml` does not yet declare that input, so the override cannot match |
| Tag push (release-please) | Tagged commit already on `main` | Yes | Not via `validate.yml`. `release.yml` re-tags the existing image with the semver through `GITHUB_TOKEN` and does not rebuild or deploy |
| Cascade push to `fork_integration` | Cascade-resolved tree | Yes | Yes |

The gate on `docker-push`:

```yaml
if: |
  (
    needs.java-build.outputs.build_result == 'success' &&
    github.actor != 'dependabot[bot]' &&
    github.event_name != 'pull_request_target' &&
    github.event_name != 'workflow_dispatch' &&
    github.ref_name != 'fork_upstream' &&
    (github.event_name != 'pull_request' ||
     github.event.pull_request.head.repo.full_name == github.repository)
  ) || (
    github.event_name == 'workflow_dispatch' &&
    inputs.force_full_pipeline == true
  )
```

The clause needs no separate `check-initialization` or `check-repo-state` guard because `java-build` reports `build_result == 'success'` only after both held. The `github.event_name != 'workflow_dispatch'` guard is what keeps a routine manual run, such as post-init validation, from pushing. The second half is reserved for a planned operator override and stays inert until `validate.yml` declares the `force_full_pipeline` input. Every credential-bearing job carries the clause itself instead of relying on skip-propagation from `docker-push`, and none of the event guards may be dropped. `deploy-gate` restates each guard as a named refusal (event, head repository, actor, branch) so the deploy lane's absence on a run is explained rather than inferred, and `dev-ci.yml` asserts the guards are present.

## Consequences

### Positive

- Registry and cluster credentials are never exposed to attacker-controlled PR execution contexts.
- Trust assumptions are explicit and identical across service forks.
- Cascade pushes keep image signal for upstream-integration risk.

### Negative

- External-fork PRs get no image push and no deploy signal. A maintainer who wants to prove such a change pushes it to a branch in the repository, which puts the reviewed code behind the boundary. CONTRIBUTING.md currently limits contributors to Microsoft employees, so no external-fork review process is documented yet.
- The `if:` clause is easy to weaken when adding a new sensitive job; review must check it against this ADR.

### Neutral

- `docker-build` runs on every event except the `pull_request_target` lane and a filter-mode `fork_upstream`. Sync PRs get their image validated on the cascade PR, and in mirror mode on the `fork_upstream` push.
- Dependabot keeps its own validation path outside credential-bearing workflows.

## Alternatives Considered

- **Allow `pull_request_target` for credential-bearing jobs**: rejected, direct credential-exfiltration risk.
- **Allow external-fork PRs**: rejected, untrusted-code boundary.
- **Trust checks by reviewer convention only**: rejected, policy is enforced in the workflow `if:` guard, not left to vigilance.

---

[← ADR-035](035-azure-only-maven-profile.md) | :material-arrow-up: [Catalog](index.md)
