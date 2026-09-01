# Acceptance Resolver

The resolver behind ADR-040. It joins the fork-owned service descriptor
(`.spi/service.yaml`, schema v3) with the stack's facts envelope
(`spi info --json`, `apiVersion: spi.osdu.dev/v1`) and caller-supplied Key
Vault secret values into the environment map an acceptance suite runs with —
an `.env` file suitable for `docker run --env-file` (Maven does not read this file directly).

This document is the resolver's contract. The source vocabulary, precedence,
exit codes, and report schema below are frozen: descriptors in every service
fork, the deploy lane, and the developer loop all depend on them, so changes
here are breaking changes.

## Boundaries

- **The resolver never calls Azure or the cluster.** Facts and secret values
  arrive as files. The caller saves `spi info --json` to disk and, when the
  descriptor names Key Vault secrets, fetches those values (e.g. one
  `az keyvault secret show` per name in the `secret_names` output) into a
  JSON file of name → value. Fetch only when `keyvault_name` is non-empty:
  an empty name beside a non-empty `secret_names` means the environment has
  not published its vault — skip the fetch and let `run` mode refuse with
  typed misses naming each secret and the unpublished fact.
- **Standard library only.** No `pip install` at runtime. The resolved
  environment must be a function of the descriptor, the facts, the secrets
  file, and the caller's explicit environment — never of the runner image.
- **Deterministic.** Same inputs produce a byte-identical env file: sorted
  names, no timestamps.
- **Secrets stay out of the report.** The JSON report carries secret *names*
  only. The env file is the single delivery artifact for values, written
  owner-only (0600).

## Invocation

```
python3 resolve.py --mode {bind|run}
                   --descriptor .spi/service.yaml
                   --facts <spi-info.json>
                   --env-file <out.env>
                   [--secrets <name-to-value.json>]
                   [--expect-gateway <url>]
                   [--expect-partition <name>]
                   [--report <path>]

python3 resolve.py --contract-only
                   --descriptor .spi/service.yaml
                   [--report <path>]
```

The composite `action.yml` wraps exactly the first invocation.
`--contract-only` validates the descriptor and reports the contract fields
(suite path, Maven argv, requires, secret names) with no facts, no
resolution, and no env file — it is how the build lane reads the descriptor
where no environment exists (e.g. selecting the suite module the acceptance
image bakes). Descriptor violations exit 2 exactly as in the full modes.

## Modes: two audiences

| Mode | Audience | Missing answer |
| --- | --- | --- |
| `bind` | A developer iterating against a personal stack | Warn, omit the entry, still write the env file, exit 0 |
| `run` | The CI lane about to execute the suite | Refuse: exit 3 naming every unresolved binding; no env file, and a stale one at the path is removed |

## Source vocabulary (closed)

A binding's `source` must be one of the following. Anything else exits 2
naming the offending key — the resolver refuses to guess.

| Source | Resolves to |
| --- | --- |
| `gateway` | `base_url` from facts, trailing slash stripped, then `suffix` appended |
| `partition` | The primary entry's `name` in `partitions[]` |
| `openid` | `azure.openid_issuer` — the OIDC v2.0 issuer URL, published explicitly by the stack, never derived from the tenant id here |
| `tenant` | `azure.tenant_id` |
| `legalTag` | The primary entry's `legal_tag` in `partitions[]` (legal tags are partition-scoped) |
| `keyvault:<name>` | The value of that secret from the caller's secrets file; the vault itself is named by `azure.keyvault` in facts |
| `static` | The declared `value`, verbatim |
| `template` | The declared `value` with `${NAME}` references to other bindings, rendered after everything else resolves; may only reference non-template, non-secret bindings |
| `user` | Nothing — the caller's environment must supply it (or a declared `default`) |

`openid` and `legalTag` are agreed with the stack
([osdu-spi-stack#131](https://github.com/Azure/osdu-spi-stack/issues/131)) but
not yet published; until the envelope carries them, bindings on them resolve
as env-not-ready. The fact locations live in one table (`FACT_PATHS` /
`PARTITION_FACT_KEYS`), so an envelope rename is a one-line change.

## Resolution precedence

Per variable: **explicit process environment → source resolution → declared
`default`.** An explicit environment value wins verbatim — no suffix is
appended — which is what lets a developer point one variable at localhost
without forking the contract. `template` sources render last, from the
already-resolved map.

A variable set to the **empty string** counts as unset, deliberately: CI
materializes empty strings from undefined workflow variables, and a blank
override silently erasing a live fact is exactly the failure mode typed
refusals exist to prevent. An intentionally empty value is expressible in
the contract itself (`default: ""`).

## The agreement point

Where the caller and the facts could both answer the same question, one owns
it and the other asserts agreement. If `--expect-gateway` or
`--expect-partition` is passed **and** facts publish that value, a mismatch is
a typed infra error (exit 4) — never a silent preference. Gateway comparison
ignores trailing slashes.

A caller that knows its target SHOULD pass the expect flags: the CI lane
knows exactly what it pinned where, so it asserts both and injects no
per-binding overrides, which makes the cross-check govern in CI. The
developer loop may omit them — there, per-binding explicit environment wins
by design.

## Guard rails

- **Reserved environment names** are rejected at validation: exact names
  (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
  `AZURE_FEDERATED_TOKEN_FILE`, plus process basics such as `PATH`, `HOME`,
  `LD_PRELOAD`, `MAVEN_OPTS`) and prefixes (`ACTIONS_`, `GITHUB_`, `RESOLVER_`, `RUNNER_`,
  `SPI_STACK_`).
- **`mavenArguments` is an argv array.** Each token must be free of
  whitespace and control characters; consumers pass the decoded array
  directly to Maven and never evaluate it as a shell string.
- **Secret values can never live in the descriptor**: `keyvault:` sources
  take no `default` and no `value`; `keyVaultBindings` map to secret names
  only.
- **Resolved values must be env-file safe**: a control character in any
  resolved value (facts included) is a typed infra error, because
  `docker run --env-file` cannot carry it.

## Exit codes

| Code | Category | Meaning |
| --- | --- | --- |
| 0 | — | Resolved (bind mode may carry warnings) |
| 2 | `descriptor` | Contract violation: unknown key or source, reserved name, bad shape. The descriptor author must fix the file. |
| 3 | `env-not-ready` | Run mode: a required answer is missing (unpublished fact, unsupplied secret, unset `user` variable). Deploy gates report this, tests never start. |
| 4 | `infra` | The environment answered wrongly: facts envelope unreadable, wrong `apiVersion`, or malformed (wrong-typed values, non-mapping nodes, more than one primary partition), agreement mismatch, unsafe value. Only an *absent* fact reads as env-not-ready. |

## Report schema (v1)

Written to `--report` (and always attempted, even on failure):

```json
{
  "engine_version": "1.0.0",
  "report_schema": 1,
  "mode": "bind",
  "service": "partition",
  "contract": {
    "test_type": "maven",
    "test_dir": "partition-acceptance-test",
    "maven_arguments": ["verify"],
    "timeout_minutes": 25,
    "requires": {"loads": [], "groups": []},
    "dependencies": []
  },
  "key_vault": {"vault": "kv-name-from-facts", "secret_names": []},
  "agreement_checked": ["gateway"],
  "resolved_names": ["MY_TENANT", "PARTITION_BASE_URL"],
  "missing": [{"name": "LEGAL_TAG", "reason": "fact 'legalTag' is not published by this environment"}],
  "error": null
}
```

On failure `error` carries `{category, code, detail}` and the exit code
follows the category.

## The descriptor, by example

```yaml
# .spi/service.yaml — fork-owned, reviewed with the code, survives any stack rehome
schemaVersion: 3
service: { name: partition, archetype: java-maven-azure }
tests:
  acceptance:
    type: maven
    path: partition-acceptance-test     # upstream-maintained module, kept by the filter
    mavenArguments: [verify]
    bindings:                           # symbols, never values — resolved against facts per run
      PARTITION_BASE_URL:  { source: gateway, suffix: / }
      MY_TENANT:           { source: partition }
      TEST_OPENID_PROVIDER_URL: { source: openid }
      LEGAL_TAG:           { source: legalTag }
      CLIENT_TENANT:       { source: tenant }
      INTEGRATION_TESTER_TOKEN: { source: user }   # minted per run, never stored
      SEARCH_URL:          { source: template, value: "${PARTITION_BASE_URL}api/search/v2/" }
    keyVaultBindings: {}                # env name -> Key Vault secret NAME, resolved at run time
    requires:                           # checked against published load facts by the deploy gate
      loads: []
      groups: []
    dependencies: []                    # sibling services this suite calls
    timeoutMinutes: 25
```

The formal contract is `service-descriptor.schema.json` beside this file. The
descriptor accepts a fixed YAML subset (block and flow mappings/lists, quoted
or plain scalars, comments — no anchors, no multi-line scalars, no tabs),
parsed by the engine itself so the contract never depends on the runner image.

## Local testing

```bash
cd .github/actions/acceptance-resolver

# facts from a live stack…
spi info --json > /tmp/info.json
# …or any saved fixture
python3 resolve.py --mode bind --descriptor /path/to/.spi/service.yaml \
                   --facts /tmp/info.json --env-file /tmp/acceptance.env \
                   --report /tmp/report.json
cat /tmp/acceptance.env

# explicit env always wins — point one variable at a laptop service
PARTITION_BASE_URL=http://localhost:8080/ python3 resolve.py --mode bind ...
```

The regression harness lives at
`.github/local-actions/acceptance-resolver-tests/run-tests.sh` and runs
against fixture facts — no cluster, no Azure calls.
