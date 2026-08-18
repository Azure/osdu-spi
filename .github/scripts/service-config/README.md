# Service Configuration (`service-config`)

Template-owned tooling for the fork-owned service descriptor `.spi/service.yaml`
([ADR-039](../../../doc/src/adr/039-fork-owned-service-descriptor.md)).

This directory is synced to every fork by template-sync. Forks do not edit it; they edit
`.spi/service.yaml`, which template-sync never touches.

| File | Purpose |
| --- | --- |
| `schema.json` | Schema version 1: closed archetype enum, closed key set, forbidden privileged keys |
| `descriptor.py` | Strict standard-library parser (YAML subset), validator and resolver |
| `read_service_config.py` | Workflow/settings entry point: emits the `read-service-config` output contract or JSON |
| `generate_descriptor.py` | Initialization detection and generation; halts on ambiguous/unsupported repositories |
| `generate_codeowners.py` | Seeds or verifies the `/.spi/` CODEOWNERS rule |

## Why a checked-in parser

GitHub-hosted runners guarantee a standard-library `python3`, not PyYAML or `yq`. The parser
accepts only what a descriptor needs — block mappings, scalar sequences, single-line flow
sequences, quoted/plain scalars, booleans and integers — and rejects anchors, aliases, tags, block
scalars, multiple documents, tabs and nulls. Parsing is therefore deterministic, dependency-free
and fails closed on anything unusual.

## Output contract

`read_service_config.py --format github` writes exactly these keys and nothing else:

```text
descriptor_present  schema_version  archetype     service_name  dockerfile_profile
unit_test_type      has_coverage    build_lane    lane_implemented  fallback
```

Job outputs never carry shell commands, credentials or deployment targets.

Exit codes: `0` when the descriptor is valid or absent, `1` when a present descriptor is invalid
(the required `🐳 Docker Build` check then fails closed).

## Usage

```bash
# Resolve for workflows
python3 read_service_config.py --root . --service-name partition \
  --format github --output "$GITHUB_OUTPUT" --summary "$GITHUB_STEP_SUMMARY"

# Machine-readable, value-free diagnostics (used by settings-apply)
python3 read_service_config.py --root . --format json --redact

# Initialization
python3 generate_descriptor.py --root . --service-name partition
python3 generate_codeowners.py --path CODEOWNERS --owners "@my-org/engineering-system"
```

## Adding an archetype

1. Add the archetype to `schema.json` with its `lane`, `laneImplemented` flag and defaults.
2. Add the statically declared build job to `build.yml` and `validate.yml` (expressions are not
   allowed in `uses:`), gated on `needs.read-service-config.outputs.build_lane`.
3. Add the lane to `docker-build-required`'s `needs` so the required check reflects it.
4. Extend `generate_descriptor.py` detection and the tests under `tests/`.

Until step 2 exists, a descriptor declaring that archetype fails the required check closed —
never a green skip.
