# ADR-046: Fleet Release and Bill of Materials

## Status

Accepted (2026-11-04)

## Context

Each service fork releases on its own through release-please, and nothing records which fork versions were released together. ADME needs that record as a bill of materials. Version tags can be moved, and before the release retag read the release commit, a release created on a later push could pair a version tag with images built from another commit. The correlation tag a fork release carries reads the live upstream head at release time, so it is not a reliable source for what upstream commit the release contains. A coordinated major version across the fleet was rejected: `release-as` in the synced release-please config also forces osdu-spi's own release, stays in effect until removed, and misses forks onboarded later.

## Decision

**A fleet release is a `fleet-YYYY.MM.DD` release in osdu-spi with `bom.json` attached, built by the dispatched `fleet-release.yml` from each fork's latest release. Service versions stay whatever release-please gave each fork.**

- **Forks** come from the `forks:` list in osdu-spi-stack (ADR-045). A fork with no release, or not ready, is recorded with null fields and an `excluded` reason, so one fork never holds the marker back.
- **Readiness** is checked against a template target frozen at dispatch. The effective target is the newest osdu-spi commit at or before it that touched a path `sync-config.json` syncs, because a docs-only template commit never produces a sync. A fork is ready when the `.github/.template-sync-commit` at its release tag contains the effective target.
- **Images** are recorded by digest for the service image and, when present, its `-acceptance` and `-load` images, read at the version tag. A fork whose version tag does not point at the image built from its release commit is excluded.
- **`upstreamSha`** comes from the nearest generated commit on the release tag's first-parent history that carries an `Upstream-Sha` trailer. If the nearest step brings in generated commits with more than one distinct value, the run fails.
- **`toolchain`** is a neutral map of the pins found in the build files at the tag, so other archetypes (ADR-044) add keys rather than fields.
- **Publishing** builds the whole BOM first. A release that already exists with identical `bom.json` is a no-op; any difference fails the run. A fleet release is never edited, deleted, or marked latest.

The BOM records what was released and which stack version was current. It does not record what any environment runs: the stack deploys each fork's `main-snapshot` digest, not its release tag.

## Consequences

### Positive

- A fork added to the stack's list appears in the next BOM with no edit.
- ADME reads one immutable file per fleet release.

### Negative

- `upstreamRepository` needs the release app to read each fork's `UPSTREAM_REPO_URL` variable; without that it is null.
- `stack` is the stack's latest release when the BOM is built, so a backdated BOM records today's stack version.
- A private `-acceptance` or `-load` package reads as absent and is not recorded.

## Alternatives Considered

- **`release-as: 2.0.0` through template sync.** Forces the template's own release, stays until removed, and the next scheduled sync can overtake the cleanup.
- **Require the exact template head.** Never clears after a docs-only template commit.
- **Record version tags instead of digests.** Tags can be moved.

---
