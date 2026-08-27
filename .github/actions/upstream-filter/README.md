# Upstream Filter Engine

The engine behind ADR-038. It transforms a checkout of the verbatim upstream tip
into the generated `fork_upstream` tree, verifies generated trees, stamps
fork-owned pom versions during the cascade, and seeds the fork-owned Azure trees
at initialization.

This document is the engine's contract. The modes, exit codes, halt codes,
report schema, and `Filter-Rev` formula below are frozen: workflows, fixtures,
and commit trailers all depend on them, so changes here are breaking changes.

## Boundaries

- **The engine never touches git.** It reads and writes files inside a directory
  it is pointed at. Archive extraction, scratch-index serialization, and commit
  creation live in workflow shell beside this action, not here.
- **Standard library only.** No `pip install` at runtime. The generated tree
  must be a function of the engine, the config, and the upstream tree, never of
  the runner image.
- **Deterministic.** Same inputs produce byte-identical output. The engine emits
  no timestamps and walks directories in sorted order.

## Invocation

```
python3 upstream_filter.py --mode {generate|verify|stamp|seed}
                           --config <upstream-filter.yml>
                           --checkout <dir>
                           [--seed-source <dir>]      # seed mode only
                           [--report <path>]          # JSON report also goes to stdout
```

The composite `action.yml` wraps exactly this invocation.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Operational error (bad arguments, unreadable paths). A bug in the caller, not a classification result. |
| 2 | **Halt.** The engine refuses to guess. The sync fails and opens a `sync-failed,human-required` issue. |

## Modes

### `generate`

Transforms the checkout in place into the generated `fork_upstream` tree:

1. `provider/` and `devops/` are removed wholesale. The Azure provider is
   fork-owned and seeded separately; every other provider is discarded
   automatically, never silently kept.
2. Every other top-level entry is classified by the config's `top_level` map
   (`keep` | `strip`). An unclassified entry halts.
3. Every entry under `testing/` is classified by the `testing` map
   (`keep` | `strip` | `fork`). `strip` and `fork` entries are removed from the
   generated tree; `fork` marks the entry as fork-owned rather than discarded.
4. Root pom `<profile>` blocks are classified by the `profiles` map
   (`keep` | `strip` | `inject`). `strip` and `inject` blocks are removed;
   the `inject` profile is then re-inserted verbatim from
   `inject_root_pom_azure_profile`, immediately before `</profiles>`.
5. Dangling `<module>` entries in the root pom and `testing/pom.xml` are pruned
   by derivation: any module whose target path no longer exists is removed.
   This is safe because the file pass halts on unknowns, so a missing path can
   only mean a deliberate strip.
6. `inject_testing_pom_azure_module` is inserted verbatim immediately before
   `</modules>` in `testing/pom.xml`.
7. `.fossa.yml` modules under `analyze.modules` are classified by the
   `fossa_modules` map (`keep` | `strip`). The Azure module entry is
   deliberately `strip`: the fork strips `.gitlab-ci.yml` and runs no FOSSA
   analysis of its own.
8. The verification battery below runs as a post-condition.

Injection is verbatim: the stored blocks are inserted byte-for-byte as they
appear in the config. Modules referenced only by injected blocks dangle on the
generated tree by design and are exempt from module resolution; they resolve
after the cascade merge, where the fork-owned directories exist.

### `verify`

Runs the verification battery without mutating anything. Valid only against a
generated tree (a `fork_upstream` candidate); the fork-owned trees present on
`fork_integration` or `main` would correctly fail it.

- **Negative**: no stripped path, profile, or FOSSA module survives, and
  `provider/` and `devops/` are absent.
- **Positive**: every `expected_kept` path exists and every `expected_absent`
  path is absent, so an upstream rename fails loud instead of passing as an
  empty diff.
- **Classification re-run**: every present entry still classifies without
  unknowns, the new-module alarm.
- **Module resolution**: every surviving `<module>` resolves to an existing
  path, with the injected entries as the one deliberate exemption.
- **Injection presence**: the inject-verdict profile appears exactly once as
  live XML in the root pom, and every injected testing module is a live
  `<module>` entry in `testing/pom.xml`. A tree that lost its injections
  cannot verify.

### `stamp`

Runs on `fork_integration` after the cascade merge, where the upstream version
bump and the fork-owned poms first coexist. Reference versions are read from the
merged upstream-owned poms: the root `pom.xml` version, the `testing/pom.xml`
version, and `testing/<service>-test-core`'s own version. Every upstream-derived
version string in the fork-owned poms (`provider/<service>-azure/**/pom.xml`,
`testing/<service>-test-azure/**/pom.xml`) is rewritten to its reference value.

The mode is defined by its post-condition, not a site list: **after stamping, no
pre-bump version string survives anywhere in the fork-owned poms**, and the
engine halts if one does. A partial stamp is worse than a failed build, because
Maven accepts a child whose version differs from its parent and would ship an
Azure JAR carrying old coordinates inside a bumped reactor.

If the same pre-bump string would need to become two different values, the
engine halts (`STAMP_AMBIGUOUS`) rather than guessing.

### `seed`

Copies `provider/<service>-azure` and `testing/<service>-test-azure` from
`--seed-source` (a checkout of the newest upstream commit that still contains
them) into the checkout. Halts if a source tree is missing or lacks a
`pom.xml`, or if a target already exists.

`seed-source.sh` materializes that checkout: it resolves each tree
independently (upstream can delete them in different commits), preferring the
ref's tip and otherwise walking the deletion commit's parents, because
simplified history returns nothing for a path deleted through a merge. It
composes both trees into one directory through a scratch index and reports the
per-tree source commits.

## Halt codes

| Code | Raised when |
| --- | --- |
| `CONFIG_MISSING` | The config file does not exist. The sync fails closed; there is no fallback to the old merge path. |
| `CONFIG_INVALID` | The config fails schema validation. |
| `UNKNOWN_TOP_LEVEL` | A top-level entry has no verdict. |
| `UNKNOWN_TESTING_ENTRY` | An entry under `testing/` has no verdict. |
| `UNKNOWN_PROFILE` | A root pom profile id has no verdict. |
| `UNKNOWN_FOSSA_MODULE` | A module under `analyze.modules` has no verdict. |
| `FOSSA_UNPARSEABLE` | `.fossa.yml` exists but does not match the expected `analyze.modules` shape. |
| `FOSSA_TARGET_MISSING` | A kept FOSSA module's target path does not exist. |
| `STRIPPED_PATH_SURVIVES` | A path, profile, or FOSSA module with a strip verdict is still present after generation. |
| `EXPECTED_KEPT_MISSING` | An `expected_kept` path is absent from the generated tree. |
| `EXPECTED_ABSENT_PRESENT` | An `expected_absent` path is present in the generated tree. |
| `MODULE_UNRESOLVED` | A surviving, non-injected `<module>` points at a missing path. |
| `INJECT_TARGET_MISSING` | A pom lacks the `</profiles>` or `</modules>` anchor an injection needs. |
| `INJECT_MISSING` | A configured injection is absent: the inject profile is not present exactly once in the root pom, or an injected testing module is missing from `testing/pom.xml`. |
| `STAMP_REF_MISSING` | A reference pom (root, testing, test-core) is missing or carries no version. |
| `STAMP_NO_FORK_POMS` | Stamp mode found no fork-owned poms to stamp. |
| `STAMP_AMBIGUOUS` | One pre-bump version string maps to two different reference values. |
| `STAMP_INCOMPLETE` | A pre-bump version string survives after stamping. |
| `SEED_SOURCE_MISSING` | A seed-source tree is missing or lacks a `pom.xml`. |
| `SEED_TARGET_EXISTS` | A seed target already exists in the checkout. |

## Report

Every run prints a JSON report to stdout and, with `--report`, writes the same
bytes to a file. The report carries no timestamps.

```json
{
  "schema": 1,
  "mode": "generate",
  "engine_version": "1.0.0",
  "service": "partition",
  "config_sha256": "<full sha256 of the config bytes>",
  "filter_rev": "1.0.0+<first 12 hex of config_sha256>",
  "ok": true,
  "halts": [{"code": "...", "detail": "..."}],
  "counts": {"initial_files": 421, "kept_files": 88, "discarded_files": 333},
  "discarded": ["..."],
  "stamp": {"references": {"root": "..."}, "rewrites": [{"pom": "...", "from": "...", "to": "..."}]},
  "seeded": ["..."]
}
```

`counts`/`discarded` appear for generate, `stamp` for stamp, `seeded` for seed.
The `discarded` list records removals at the granularity they were classified
(a stripped directory is one entry, not one entry per file).

## `Filter-Rev`

```
Filter-Rev: <engine_version>+<sha256(config bytes)[:12]>
```

Recorded as a trailer on every generated commit together with `Upstream-Sha`.
The pair identifies the engine version and the effective per-service
configuration, so any generated tree can be reproduced exactly from its inputs.

## Config: `.github/upstream-filter.yml`

Fork-owned, seeded at init from `.github/fork-resources/` with `<service>`
substitution, then maintained by ordinary PR on the fork's `main`. `main` is its
only durable home: `integration-cleanup.yml` resets `fork_integration` after
every release, so a copy there is derived, not durable.

Initialization prefers a config already present on the fork's `main` over the
template: committing a complete `.github/upstream-filter.yml` before replying
to the initialization issue is the escape hatch for services whose module
prefix or layout deviates from the conventional shape. `sync-template.yml`
plants the file on forks that lack one and never overwrites an existing copy.

Each category is a single mapping from name to verdict. A name appears exactly
once, so keep and strip can never disagree.

`service` is the Maven module prefix, not necessarily the repository name: the
`entitlements` repository's modules are `entitlements-v2-*`, so its config would
say `service: entitlements-v2`. Everything path-shaped derives from it:
`provider/<service>-azure`, `testing/<service>-test-azure`, and the cascade's
survival assertion all read this key.

```yaml
service: partition

top_level:                # every top-level entry except provider/, devops/, testing/
  pom.xml: keep
  partition-core: keep
  partition-core-plus: strip
  .gitlab-ci.yml: strip

testing:                  # every entry under testing/
  pom.xml: keep
  partition-test-core: keep
  partition-test-azure: fork
  partition-test-aws: strip

profiles:                 # every root pom profile id
  core: keep
  azure: inject
  aws: strip

fossa_modules:            # every module name under analyze.modules
  partition-core: keep
  partition-azure: strip

expected_kept:
  - pom.xml
  - partition-core
  - testing/partition-test-core

expected_absent:
  - provider
  - devops
  - partition-core-plus

inject_root_pom_azure_profile: |
  <profile>
    <id>azure</id>
    ...
  </profile>

inject_testing_pom_azure_module: |
  <module>partition-test-azure</module>
```

`inject_root_pom_azure_profile` may be non-empty only when a `profiles` entry
carries the `inject` verdict; a non-empty block with no `inject` verdict halts
with `CONFIG_INVALID`.

The file is parsed by a small fixed-schema reader, not a general YAML parser.
The accepted subset: top-level `key: value`, `key:` introducing a two-space
indented block of `name: verdict` pairs or `- item` list entries, and `key: |`
literal blocks whose lines are de-indented by exactly two spaces. Comments start
with `#`, on their own line or inline after a value; an inline `#` needs
preceding whitespace. Literal block content is never comment-stripped. Nothing
deeper nests. An empty indented block (`key:` followed by
nothing) is valid: it yields an empty list for list-typed keys such as
`expected_kept` and `expected_absent`, and an empty map for the others.

## Testing

The fixture corpus and harness live at `.github/local-actions/upstream-filter-tests/`,
a path excluded from template sync and removed at fork initialization. The
harness drives every halt code plus idempotence (generate applied to its own
output is a byte-level no-op) and determinism (repeated runs are byte-identical)
and runs as a required check on template `main`: the gate precedes the payload,
because merging this directory distributes it to every fork's next nightly sync.
