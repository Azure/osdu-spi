# ADR-041: Borrow, Prove, Restore Lane

## Status

Accepted (2026-09-10)

## Context

`docker-push` publishes a digest-addressed service image per trusted commit, and ADR-040 gives each fork a descriptor and the template a resolver that turns it into a suite's environment. The stack side now ships everything the lane borrows: an ephemeral pin surface with ownership-checked reset, `spi onboard` writing one federated credential per fork against the environment's deploy identity, `spi status --json` as the deployability gate, and `spi token` for the same identity from a laptop. The [Borrow, Prove, Restore design](../architecture/deploy_test.md) fixed the transaction shape; what remained was the CI lane itself and the questions a prototype on the partition fork answered before this record was written.

Those questions were: when the lane runs and who may trigger it, how a run explains the lane's absence, which CLI release proves an environment, how a fork with more than one suite ships them, and what the required check is once the lane exists.

## Decision

**The deploy lane is one credentialed job, `deploy-test`, that borrows the attached stack for the image `docker-push` just published, proves it with every suite the descriptor declares, and restores the canonical image whatever happened. It runs on pushes to `main` and `fork_integration` and on the fork's own pull requests, behind a gate job that always reports, and the summary job that reports it is the required check.**

### Pull requests are proven before they merge

The lane runs on a same-repository pull request and again on the push after merge. The two runs are not redundant: the merge is a new build with a new digest, and the push run proves the digest that becomes canonical.

Write access to the fork is the trust boundary. A pull request from another repository runs without an OIDC token, so it cannot mint the deploy identity whatever the workflow says, and the gate names that refusal rather than leaving it to fail. The `spi-stack` GitHub environment admits every branch; a branch list there would only keep the lane off the fork's own pull requests. A maintainer who wants a human pause before a borrow adds required reviewers to the environment, which holds the job at its first credentialed step with no workflow change. The ADR-036 clause is carried in full by the gate, as named refusals for event, head repository, actor, and branch.

### Absence is explained

`deploy-gate` runs after `docker-push` on every run and writes one line to the run summary: the cluster it is about to borrow, or the reason it will not. The reasons are the trust refusals above, a fork not yet onboarded (missing any of `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `SPI_STACK_RESOURCE_GROUP`, `SPI_STACK_CLUSTER`), no `.spi/service.yaml`, no image pushed, or a descriptor that declares no suite. `deploy-test` runs only when the gate decided to borrow.

### The CLI is the environment's release

The lane installs the latest `spi` release to reach the environment, then reads `environment.stackVersion` from `spi status --json` and reinstalls that exact release when it names one. An environment tracking a branch, such as a personal stack on `main`, keeps the latest release. No fork carries a stack version.

### One image carries every suite

`tests` in the descriptor is a map of named suites of one shape; `acceptance` is required and is the run-time default. The acceptance image bakes every declared suite path, with each suite's dependencies prewarmed and a multi-module suite installed first so its sibling modules resolve. `SUITE_DIR` selects the suite at run time, and the resolver's `--suite` selects which bindings to resolve. The lane runs one `docker run` per suite under the suite's own timeout and fails if any suite fails.

### The summary is the required check

`validation-summary` replaces the Docker Build reporter job as the always-reporting required check. It fails when any build, push, or deploy job failed or was cancelled, passes on skips, and writes one table of every job, its result, and the gate's reason. Code quality stays advisory. The same ruleset serves every fork: a fork that is not onboarded skips the lane and the summary stays green, so no per-fork filtering of required checks is needed.

### The test caller

The positive-path caller is the environment's deploy identity, the same principal the lane logs in as, minted for the audience `spi info --json` publishes as `azure.token_audience`. The bearer reaches the resolver as `RESOLVER_TOKEN` and lands in every binding with `source: token`, so a suite may call the variable whatever it likes and a developer supplies the same input from `spi token`. The negative-path identity the stack provisions is not yet exercised by a suite.

### Not yet wired

Two parts of the descriptor contract (ADR-040) are validated and reported by the resolver but not enforced by the lane. `keyvault:` bindings are not materialized: the lane passes no `--secrets` file, so a suite that declares one fails as env-not-ready ([#175](https://github.com/Azure/osdu-spi/issues/175)). `requires.loads`, `requires.groups`, and `dependencies` are not compared with the status facts before the borrow, because the stack does not yet publish seeded loads ([osdu-spi-stack#133](https://github.com/Azure/osdu-spi-stack/issues/133), [#176](https://github.com/Azure/osdu-spi/issues/176)). No shipped descriptor uses either yet.

## Consequences

### Positive

- A broken change is caught on its pull request, against the real stack, before it reaches `main`.
- A run that did not deploy says why in one line, on the run and in the summary table.
- The same workflow, ruleset, and image serve a fork with one suite and a fork with several, and a personal stack as well as the shared one.
- The lane never installs from a branch, so a fork's proof is reproducible against the release its environment runs.

### Negative

- Every same-repository pull request borrows the shared environment. The per-service concurrency group queues them, so a busy fork waits; the gate's refusals and the suite timeouts keep the wait explainable.
- Renaming the required check changes every fork's ruleset, which `settings-apply` reconciles on its cadence. In between, the old name still reports on `main` because the build job now carries it; a skipped build counts as passing there, and a failed build fails the old check as before.

### Neutral

- `fork_upstream` never enters the lane: filter-mode builds carry no Azure image.
- The lane runs suites on the runner against the gateway, as design decision D6 chose. An in-cluster path for developers is a stack-side concern.

## Alternatives Considered

- **A maintainer-authorized gate for outside pull requests**, as an earlier prototype used with `pull_request_target`. Rejected: it runs untrusted code with the deploy identity and makes a label the only thing between a contributor and the cluster. A maintainer who wants to prove an outside change pushes it to a repository branch.
- **The lane on pushes only.** Rejected: it proves a change after it has landed, which is backwards for a lane whose purpose is to keep a broken change off `main`.
- **One image per suite.** Rejected: two images to tag, retain, and match to a commit for no gain; the select stage already ships only the declared suites.
- **A repository variable naming the stack version.** Rejected: a value that is stale the moment the environment upgrades, on every fork.
- **Stripping the deploy check from the ruleset on forks that are not onboarded.** Rejected: the gate makes the skip visible and the summary green, so the ruleset can be the same everywhere.

---

[← ADR-040](040-descriptor-acceptance-contract.md) | :material-arrow-up: [Catalog](index.md)
