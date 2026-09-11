# Service Descriptor

`.spi/service.yaml` tells the engineering system which test suites a service repository has and what each suite needs from a stack environment. The acceptance image includes every suite the file declares, and the deploy lane runs each one against the stack environment. Developers resolve the same file against their own stack. The repository owns the file: template sync never changes it, and changes to it are reviewed with the code.

This page covers writing a descriptor, checking it, and running its suites. The resolver's README beside `.github/actions/acceptance-resolver/resolve.py` is the contract the resolver checks, and [ADR-040](../adr/040-descriptor-acceptance-contract.md) records the decision behind it.

## Prerequisites

- A local clone of the service repository. Run every command on this page from its root. Template sync delivers the resolver at `.github/actions/acceptance-resolver/resolve.py`.
- Python 3. The resolver uses only the standard library.
- `jq`.
- From step 5 on, the `spi` CLI connected to a stack environment: run `spi connect --resource-group <rg> --cluster <cluster>`, then `spi status`.
- For [running suites locally](#run-suites-locally), Docker. The acceptance image is built for `linux/amd64` only; on an Apple silicon Mac it runs under emulation.

## Descriptor format

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

`service.name` is the name the stack uses for the service: the `<service>` argument given to `spi onboard`, such as `partition`. `archetype` is always `java-maven-azure`.

`tests` is a map of suites. `acceptance` is required, and it's the suite the image runs when no other is selected. Suite names are lowercase slugs. Every suite has the same fields:

| Field | Meaning |
|---|---|
| `type` | Always `maven` |
| `path` | The directory holding the suite's `pom.xml`, relative to the repository root. The image includes only the directories the suites name |
| `mavenArguments` | Maven arguments as an array of tokens, never as one shell string. Default `[verify]` |
| `timeoutMinutes` | The lane stops the suite after this many minutes. Default 25, maximum 180 |
| `bindings` | The environment variables the suite reads, each bound to a source from the table below |
| `keyVaultBindings` | Variable name to Key Vault secret name, for values that must never be in the file. The resolver validates it, but the lane doesn't supply these values yet |
| `requires`, `dependencies` | Seeded data loads, entitlement groups, and other services the suite depends on. The resolver validates them, but the gate doesn't enforce them yet |

## Single-module and reactor suites

**A single module** has its `pom.xml` at the path and runs with `[test]` or `[verify]`. Upstream's `<service>-acceptance-test` is laid out this way.

**A reactor** has a parent `pom.xml` at the path, with the Azure module beneath it. Set the path to the parent directory and select the module in the arguments: `[-pl, <service>-test-azure, -am, test]`. The image installs the reactor before it downloads dependencies, so the modules the Azure module depends on resolve from the image's local Maven repository. Upstream's `testing/` tree is laid out this way.

## Bindings

A binding maps an environment variable the suite reads to a source that supplies its value. Name the variable whatever the suite reads; the stack never sees these names. Two suites can bind the same source under different names, as the example does for the token.

| Source | Value | Use it for |
|---|---|---|
| `gateway` | The stack's base URL, with `suffix` appended if given | Service URLs. Add `suffix: /` when the suite appends paths to it |
| `partition` | The primary data partition's name | Data partition ids and tenant names |
| `openid` | The OIDC issuer the stack publishes | Suites that discover the token endpoint |
| `tenant` | The Entra tenant id | Suites that build authority URLs themselves |
| `legalTag` | The primary data partition's seeded legal tag | Storage and legal suites |
| `token` | The bearer token the caller supplies as `RESOLVER_TOKEN`: minted per run by the lane, or from `spi token` on a laptop | Access-token variables. No default allowed |
| `static` | The literal `value` | Fixed settings such as an environment label |
| `template` | The `value` with `${OTHER}` references to the suite's other bindings, rendered last; never to another `template` or a `keyvault:` binding | A URL built from the gateway and a fixed path |
| `user` | Nothing from the stack; the caller's shell supplies it, or the declared `default` | A setting only a developer changes |
| `keyvault:<name>` | The named secret, from a secrets file the caller passes to the resolver | Secrets other than access tokens. The lane doesn't supply these yet; for an access token, use `token` |

### Values and defaults

- Values from the stack, the caller, or a vault never appear in the file.
- `static` and `template` bindings carry a `value`.
- `user` and the five sources the stack publishes (`gateway`, `partition`, `openid`, `tenant`, `legalTag`) accept a `default`, used when nothing else supplies a value. `token`, `keyvault:<name>`, `static`, and `template` don't.

A variable set in the caller's environment always wins over the file. That's how a developer points a suite at a service running on their laptop without editing the descriptor.

### System properties

Bindings reach the suite as environment variables, and `mavenArguments` reach Maven unchanged, so `${env.NAME}` in an argument is never expanded. A suite that reads a value only with `System.getProperty` needs the property mapped from the environment in its `pom.xml`:

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-surefire-plugin</artifactId>
  <configuration>
    <systemPropertyVariables>
      <NAME>${env.NAME}</NAME>
    </systemPropertyVariables>
  </configuration>
</plugin>
```

A suite that runs its tests through Failsafe takes the same `systemPropertyVariables` block under `maven-failsafe-plugin`. Upstream owns the `<service>-acceptance-test` module, so a mapping it lacks belongs in an upstream merge request, not in the fork.

## Create and validate a descriptor

1. Find the variables each suite reads. Upstream suites read them with `System.getenv` or `System.getProperty`; search the suite's `src/test` for both. The Azure module's README under `testing/` usually lists them. A variable read with `System.getProperty` also needs the mapping in [System properties](#system-properties).
2. Bind each variable. Use `gateway` for the stack base URL, `partition` for the primary data partition name, and `token` for access tokens; the [table](#bindings) covers the rest. If no source fits, the suite needs something the stack doesn't publish. Open an issue on the stack instead of adding a `user` binding with a default, because a default stays in the file after the reason for it is gone.
3. Set `timeoutMinutes` from a real run's duration, plus margin.
4. Check the contract:

    ```bash
    python3 .github/actions/acceptance-resolver/resolve.py --contract-only \
      --descriptor .spi/service.yaml --report /dev/stdout
    ```

    Exit 0 prints the suites the image will include. Exit 2 names the problem.

5. Resolve the descriptor against a stack environment:

    ```bash
    spi info --json > facts.json
    export RESOLVER_TOKEN=$(spi token)
    (
      set -euo pipefail
      python3 .github/actions/acceptance-resolver/resolve.py --contract-only \
        --descriptor .spi/service.yaml --report suites.json > /dev/null
      for suite in $(jq -r '.contract.suites | keys[]' suites.json); do
        python3 .github/actions/acceptance-resolver/resolve.py --mode run --suite "$suite" \
          --descriptor .spi/service.yaml --facts facts.json \
          --env-file "$suite.env" --report "$suite-report.json"
      done
    )
    ```

    The suite names come from the contract report, the same source the lane uses. Each suite gets an env file, `<suite>.env`, and a report, `<suite>-report.json`. The subshell stops at the first resolver failure and returns its exit code without closing your terminal.

    Run mode is what the lane uses: when a binding has no value, it exits 3 and names every such binding. While iterating against a personal stack, `--mode bind` warns instead.

    An env file can contain a token. Pass it to `docker run --env-file` and never `source` it, which would run the token as shell.

6. Commit the descriptor and open a pull request. A pull request that changes only the descriptor skips the build, because Check Paths treats `.spi/` as configuration. The acceptance image is built by the first build that includes the descriptor: a change that triggers a build, pushed to the same pull request or a later one. In that build, the Docker Build job's "Acceptance Image" step fails if a declared path doesn't exist. Once the repository is onboarded, the Deploy and Test job runs each suite, and the Validation Summary comment reports one result line per suite.

## Run suites locally

Run the suites through the acceptance image, the same way the lane does. You need:

- An acceptance image built from a commit that includes the descriptor and every suite you want to run. The Docker Push job publishes one for pushes and same-repository pull requests that trigger a build, and prints its tag: `sha-` followed by the first twelve characters of the commit hash. The digest from the same job works too.
- The env files and reports from step 5, resolved from the same descriptor.

```bash
image="ghcr.io/<org>/<service>-acceptance:sha-<short-sha>"
for suite in $(jq -r '.contract.suites | keys[]' suites.json); do
  mapfile -t maven_args < <(jq -r '.contract.maven_arguments[]' "$suite-report.json")
  docker run --env-file "$suite.env" -e SUITE_DIR="$(jq -r .contract.test_dir "$suite-report.json")" \
    "$image" "${maven_args[@]}"
done
```

Each suite runs from its declared path with its declared Maven arguments, both read from its report. The arguments go through an array, as they do in the lane, so an argument such as `-Dtest=*Test` reaches Maven as one token instead of being expanded by the shell.

## Common mistakes

- **A `user` binding with a default token.** A default is stored in the repository, so a default token is a secret committed to the file. Use `token`.
- **`mavenArguments` as one string.** `"-pl x -am test"` reaches Maven as one token and fails. Write the array.
- **A path outside the suites.** The image contains only the declared directories plus `.mvn` and `.spi`. A suite that reads `../shared` passes on a laptop and fails in the image.
- **A suite name with capitals or underscores.** Names must match `^[a-z][a-z0-9-]{0,31}$`.
