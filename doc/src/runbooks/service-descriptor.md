# Service Descriptor

`.spi/service.yaml` tells the engineering system which test suites a fork ships and what each suite needs from a stack environment. The acceptance image bakes every suite the file declares, the deploy lane runs each one against the borrowed environment, and a developer resolves the same file against a personal stack. The file is fork-owned: template sync never touches it, and it is reviewed with the code.

This page is how to write one. The resolver's README beside `.github/actions/acceptance-resolver/resolve.py` is the contract it is checked against, and [ADR-040](../adr/040-descriptor-acceptance-contract.md) is the decision behind it.

## Shape

```yaml
schemaVersion: 3
service:
  name: partition
  archetype: java-maven-azure
tests:
  acceptance:
    type: maven
    path: partition-acceptance-test
    mavenArguments: [test]
    timeoutMinutes: 15
    bindings:
      HOST: { source: gateway }
      DATA_PARTITION_ID: { source: partition }
      PRIVILEGED_USER_TOKEN: { source: token }
  integration:
    type: maven
    path: testing
    mavenArguments: [-pl, partition-test-azure, -am, test]
    timeoutMinutes: 20
    bindings:
      ENVIRONMENT: { source: static, value: dev }
      PARTITION_BASE_URL: { source: gateway, suffix: / }
      MY_TENANT: { source: partition }
      INTEGRATION_TESTER_ACCESS_TOKEN: { source: token }
```

`service.name` is the service as the stack knows it, the name `spi onboard` was given. `archetype` is always `java-maven-azure`.

`tests` is a map of suites. `acceptance` is required and is the suite the image runs when no other is selected. Suite names are lowercase slugs. Every suite has the same fields:

| Field | Meaning |
|---|---|
| `type` | Always `maven` |
| `path` | The directory holding the suite's `pom.xml`, relative to the repository root. The image bakes exactly the directories the suites name |
| `mavenArguments` | Maven argv tokens, passed as an array and never as a shell string. Default `[verify]` |
| `timeoutMinutes` | The lane kills the suite past this. Default 25, maximum 180 |
| `bindings` | The environment variables the suite reads, each bound to a source below |
| `keyVaultBindings` | Variable to Key Vault secret name, for values that must never be in the file. Declared and validated today, not yet materialized by the lane |
| `requires`, `dependencies` | Seeded loads, entitlement groups, and sibling services the suite depends on. Declared and validated today, not yet enforced by the gate |

## Two suite shapes

**A single module** has its `pom.xml` at the path and runs with `[test]` or `[verify]`. Upstream's `<service>-acceptance-test` is this shape.

**A reactor** has a parent `pom.xml` at the path and the Azure module beneath it. Name the path as the parent and select the module in the arguments: `[-pl, <service>-test-azure, -am, test]`. The image installs the reactor before it prewarms dependencies, so the sibling modules the Azure module depends on resolve offline. Upstream's `testing/` tree is this shape.

## Bindings

A binding names the variable the suite reads and the symbol it takes its value from. The value itself is never in the file. The sources:

| Source | Value | Use it for |
|---|---|---|
| `gateway` | The environment's base URL, with `suffix` appended if given | Every service URL. Add `suffix: /` when the suite concatenates paths onto it |
| `partition` | The primary data partition's name | Partition ids and tenant names |
| `openid` | The OIDC issuer the stack publishes | Suites that discover the token endpoint |
| `tenant` | The Entra tenant id | Suites that build authority URLs themselves |
| `legalTag` | The primary partition's seeded legal tag | Storage and legal suites |
| `token` | The bearer the caller minted: the lane's per-run mint, or `spi token` on a laptop | Every access-token variable. No default is allowed |
| `static` | The literal `value` | Fixed settings such as an environment label |
| `template` | The `value` with `${OTHER}` references to other bindings, rendered last | A URL built from the gateway and a fixed path |
| `user` | Nothing; the caller's shell supplies it, or the declared `default` | A knob only a developer sets |
| `keyvault:<name>` | That secret from the stack's vault | Not yet delivered by the lane; prefer `token` |

Name the variable whatever the suite reads. The stack never learns these names; only the source is shared vocabulary. Two suites may bind the same source under different names, as the example does for the token.

An explicit variable in the caller's environment always wins over the file. That is how a developer points a suite at a service on their laptop without editing the descriptor.

## Write it

1. Find the variables. Upstream suites read them through `System.getProperty` or `System.getenv`; grep the suite's `src/test` for both. The Azure module's README under `testing/` usually lists them.
2. Bind each one. A URL is `gateway`, an id is `partition`, a token is `token`. If none of the sources fits, the suite wants something the stack does not publish; open an issue on the stack rather than a `user` binding with a default, because a default outlives the reason it was added.
3. Set the timeout from a real run, plus margin.
4. Check the contract:

    ```bash
    python3 .github/actions/acceptance-resolver/resolve.py --contract-only \
      --descriptor .spi/service.yaml --report /dev/stdout
    ```

    Exit 0 prints the suites the image will bake. Exit 2 names the violation.

5. Resolve it against a real environment:

    ```bash
    spi info --json > facts.json
    export RESOLVER_TOKEN=$(spi token)
    python3 .github/actions/acceptance-resolver/resolve.py --mode run --suite acceptance \
      --descriptor .spi/service.yaml --facts facts.json --env-file acceptance.env
    ```

    Run mode is what the lane uses: it refuses with exit 3 and names every binding it could not answer. Bind mode warns instead, for iterating against a personal stack.

6. Run the suite as the lane will, through the image:

    ```bash
    docker run --env-file acceptance.env ghcr.io/<org>/<service>-acceptance:<sha>
    docker run --env-file integration.env -e SUITE_DIR=testing ghcr.io/<org>/<service>-acceptance:<sha> -pl <service>-test-azure -am test
    ```

    The env file is data for `docker run`, never a file to source: sourcing it would evaluate a token as shell.

7. Open the pull request. The Docker Build job's "Acceptance Image" step proves the image bakes every declared path, and once the fork is onboarded the Deploy and Test job runs each suite and reports one verdict line per suite on the pull request.

## Common mistakes

- **A `user` binding with a default token.** A default is stored in the repository, which makes it a secret in the file. Use `token`.
- **`mavenArguments` as one string.** `"-pl x -am test"` is one token to Maven and fails. Write the array.
- **A path outside the suites.** The image ships only the declared directories plus `.mvn` and `.spi`. A suite that reaches for `../shared` fails inside the image although it passed on a laptop.
- **A suite name with capitals or underscores.** Names are `^[a-z][a-z0-9-]{0,31}$`.
