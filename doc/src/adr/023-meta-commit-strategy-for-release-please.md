# ADR-023: Meta Commit Strategy for Release Please Integration

## Status
Accepted

## Context
Upstream OSDU commits do not follow conventional commit format. Release Please needs a conventional commit to decide a version bump. Preserving upstream history and keeping automated versioning therefore conflict.

Solutions considered:

1. **Squash merge**: combine all upstream changes into one conventional commit
2. **Commit message transformation**: rewrite upstream messages into conventional format
3. **Meta commit**: keep upstream commits and add one conventional commit on top for Release Please
4. **Manual release management**: bypass automation for upstream changes

## Decision
Implement the **meta commit strategy**, classifying the bump with a deterministic rule over the upstream commit range.

> **Revised 2026-09-01 (#162).** This ADR originally delegated classification to `aipr commit`.
> That call crashed on every run and the `feat:` fallback fired every time, so every sync forced
> a minor bump regardless of content; the reference fork shipped v1.1.0 → v1.2.0 with no patch
> release ever. A published version number is a contract: the same range must always yield the
> same bump, and a wrong bump must be a fixable bug rather than a sampling artifact.

### How it works

1. **Upstream history is preserved.** `sync.yml` does not merge upstream. It generates the filtered tree (ADR-038) as a merge-shaped commit whose first parent is the previous `fork_upstream` tip and whose second parent is the upstream tip, so `git log`, `git blame`, and attribution carry through unchanged.
2. **The range is classified by rule.** Commit subjects and bodies between the previous `fork_upstream` tip and the upstream tip are scanned, and the most severe marker wins.
3. **A meta commit carries the classification.** `git commit-tree` writes an empty commit on the generated tree whose message is the conventional subject; Release Please reads that commit.
4. **The default is patch.** A range with no conventional markers classifies as `fix:`, never `feat:`.

### Classification rule

This grep is the implementation in `.github/template-workflows/sync.yml`:

```bash
# Classify by rule: breaking > feat > fix, defaulting to fix.
# `!` is only meaningful on a subject; the BREAKING CHANGE footer lives in the body.
UPSTREAM_SUBJECTS=$(git log --format=%s "$BEFORE_SHA..$commit")
UPSTREAM_BODIES=$(git log --format=%b "$BEFORE_SHA..$commit")
if grep -qE '^[a-z]+(\([^)]*\))?!:' <<<"$UPSTREAM_SUBJECTS" \
   || grep -qE '^BREAKING[ -]CHANGE:' <<<"$UPSTREAM_BODIES"; then
  META_COMMIT_MSG="feat!: sync upstream changes from $UPSTREAM_VERSION"$'\n\n'"BREAKING CHANGE: upstream $UPSTREAM_VERSION contains a breaking change"
elif grep -qE '^feat(\([^)]*\))?:' <<<"$UPSTREAM_SUBJECTS"; then
  META_COMMIT_MSG="feat: sync upstream changes from $UPSTREAM_VERSION"
else
  META_COMMIT_MSG="fix: sync upstream changes from $UPSTREAM_VERSION"
fi
```

A major bump writes a `BREAKING CHANGE:` footer into the meta commit body as well as the `!` on the subject, so Release Please recognises it under either convention. Subjects and bodies are read into variables first because `grep -q` short-circuits and the resulting SIGPIPE would invert the test under `pipefail`.

- **Scope**: commit messages between the last sync point and the generated tree
- **Precedence**: a subject `!` or a `BREAKING CHANGE:` body footer bumps major; any `feat:` subject bumps minor; otherwise patch
- **Determinism**: no network call, no timeout, no fallback path; an empty or wholly non-conventional range classifies as `fix:`

## Alternatives

**Squash merge** loses granular upstream history and makes selective reverts impossible. **Commit transformation** rewrites upstream messages, which breaks signatures and attribution and has many edge cases. **Manual release** loses the automation and does not scale with daily syncs.

## Consequences

Developers see conventional and non-conventional commits side by side. A rule cannot read intent: an upstream repository that never uses conventional commits will always classify as patch, and a wrong bump has to be fixed by hand before the release PR merges. The bump chosen is printed in the sync workflow log on every run.

## References

- [Release Please Documentation](https://github.com/googleapis/release-please)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [ADR-001: Three-Branch Strategy](001-three-branch-strategy.md)
- [ADR-011: Configuration-Driven Template Sync](011-configuration-driven-template-sync.md)
- [ADR-038: Upstream Filter Transform](038-upstream-filter-transform.md) - The generated, merge-shaped commit this meta commit sits on

---

[← ADR-022](022-issue-lifecycle-tracking-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-024 →](024-sync-workflow-duplicate-prevention-architecture.md)
