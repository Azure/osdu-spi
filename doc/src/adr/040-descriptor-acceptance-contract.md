# ADR-040: Descriptor-Owned Acceptance Contract with Runtime Fact Discovery

## Status

Accepted (2026-08-31)

## Context

The engineering system builds and pushes a digest-addressed service image per commit, but nothing yet deploys that image or runs the acceptance suite against a live platform. Every OSDU acceptance test needs the same answers first: where the service is, how to authenticate, and which tenant, partition, and legal tag to use. Upstream keeps those answers in four providers' pipelines. The filter transform (ADR-038) removes those pipelines, so the tests are in the repository and the knowledge of how to run them is not.

Three constraints decide where that knowledge may live. The target environment, `osdu-spi-stack`, is torn down and rebuilt weekly, so any environment value copied into a repository goes stale. Workflows sync from the template to every service fork and on to customer mirror forks (ADR-039) that point at their own stack, so nothing environment-specific can be baked in. And the same tests must run against a personal stack during development with no CI in the path.

The stack repository ships a versioned discovery contract: `spi info --json` and `spi status --json` publish endpoints, tenant, partitions, and the Key Vault name under `apiVersion: spi.osdu.dev/v1`. The arbitration with prior efforts is recorded in the [Borrow, Prove, Restore design](../architecture/deploy_test.md), whose decisions D2, D3, and D10 this ADR implements.

## Decision

**Each service fork owns a declarative acceptance contract, `.spi/service.yaml` at schema version 3, and the template owns the one resolver that joins it, per run, with the stack's facts envelope and Key Vault secret values to produce the environment a suite runs with. Nothing environment-shaped is ever pushed into a repository.**

### The descriptor is fork-owned and symbolic

`.spi/service.yaml` declares what the suite needs, never where anything is: which Maven module is the suite, environment bindings drawn from a closed source vocabulary (`gateway | partition | openid | tenant | legalTag | keyvault:<name> | static | template | user`), Key Vault secret names (never values), required data loads and entitlement groups (`requires.loads` and `requires.groups`), sibling-service dependencies, and a timeout. The contract is branch-versioned: a test change and the declaration it needs are reviewed in the same PR, and running the tests that shipped with a given release stays a one-command operation later.

The vocabulary is closed in both directions. An unknown source kind, an unknown key, or a reserved environment name (exact names such as `AZURE_CLIENT_ID`, and the prefixes `ACTIONS_`, `GITHUB_`, `RESOLVER_`, `RUNNER_`, `SPI_STACK_`) is a hard failure naming the offending key. The resolver refuses to guess, as the upstream filter does (ADR-038). Maven arguments are an array of argv tokens passed directly to Maven, never a shell string. The descriptor cannot select identity, cluster, namespace, or workflow behavior, and it cannot carry a secret value: `keyvault:` bindings take no default and no literal.

`.spi/` is listed in the exclusions of `sync-config.json` beside the other fork-owned files, so template sync never delivers or overwrites it. The JSON Schema, `service-descriptor.schema.json`, travels with the resolver action instead.

### The resolver is template machinery with one authority per answer

The resolver lives at `.github/actions/acceptance-resolver/`, a composite action wrapping a standard-library-only Python engine, extracted per ADR-028 so it runs identically in CI, on a laptop, and in the fixture harness. It never calls Azure or the cluster: the caller hands it a saved `spi info --json` envelope, validated against `apiVersion: spi.osdu.dev/v1`, and, when secrets are named, a file mapping secret names to values.

Resolution precedence per variable is explicit process environment, then facts, then declared default, with `template` sources rendering last. An explicit environment value wins verbatim, which lets a developer point one variable at localhost without forking the contract. Fact locations live in one table, so an envelope rename is a one-line change. Two agreed keys, `openid` and the primary partition's `legal_tag`, are not yet published by the stack and resolve as typed env-not-ready until they land ([osdu-spi-stack#131](https://github.com/Azure/osdu-spi-stack/issues/131)).

Where the caller and the facts could both answer the same question, one owns it and the other asserts agreement. If the caller passes an expected gateway or partition and the facts publish it too, a mismatch is a typed infra error, never a silent preference.

Failure is typed and fail-closed, serving two audiences. `bind` mode, the developer loop, warns on missing answers and still writes the env file. `run` mode, the CI lane, refuses with every unresolved binding named. Exit codes separate descriptor violations (2), environment not ready (3), and infra contradictions (4), so a deploy gate can report "environment not seeded" in seconds instead of a mystery test failure.

### Consumers today

Two places already read the descriptor ahead of the deploy lane. The `acceptance-image` action packages the declared suite module as a `<service>-acceptance` image beside the service image in `validate.yml`, and `release.yml` runs the resolver's suite lookup before tagging that image with the release version. Both skip when a fork has no descriptor.

## Consequences

### Positive

- A weekly environment rebuild costs no repository-side reconciliation across forks and mirrors. The repository holds a pointer and an identity; everything else is read per run.
- Acceptance requirements are reviewed with the code that needs them, and stored variables can no longer assert an environment that no longer exists.
- The same contract serves CI, a personal stack, and an offline run; the harness proves the resolver against fixture facts with no cluster and no Azure calls.
- Customer mirror forks (ADR-039) inherit the machinery unchanged. The resolver arrives through the mirror, and their own stack publishes the same facts contract.

### Negative

- A new schema is a new maintenance surface. Vocabulary growth (a new fact kind, a new archetype) requires a template contract change, deliberately.
- Until the stack publishes the two agreed fact keys, descriptors binding `openid` or `legalTag` resolve as env-not-ready. Correct, but visible.
- Each service fork must author one descriptor before it can join the deploy lane.

### Neutral

- The resolver validates the descriptor on every invocation. The JSON Schema file is the published reference and editor tooling can use it, but enforcement lives in the engine.
- The `.spi/` exclusion documents ownership; template sync is allow-list based and never delivered the path anyway.

## Alternatives Considered

- **Acceptance configuration in repository variables** (a prior prototype's transport). Rejected: not branch-versioned, not reviewable with test changes, and its environment values went stale on every rebuild. Its sticky `DEPLOY_VALIDATED` boolean kept asserting a canary against an environment that no longer existed.
- **One free-form Maven command string.** Rejected: shell splitting mixes goals, profiles, and exclusions with no closed data contract, and a descriptor that can carry a shell string can carry an injection.
- **Folding resolution into the `spi` CLI.** Rejected: it couples test semantics to the environment's release cadence and adds a version-skew axis between what a branch declares and what the installed CLI understands. The CLI stays the sole authority on facts; the template stays the sole authority on resolution.
- **GitHub Environments as configuration storage.** Rejected: environments are for identity protection, not config transport; values stored there are as stale as repository variables and invisible to the developer loop.

---

[← ADR-039](039-customer-tier-mirror-sync.md) | :material-arrow-up: [Catalog](index.md)
