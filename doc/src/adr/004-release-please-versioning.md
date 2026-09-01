# ADR-004: Release Please for Automated Version Management

## Status
**Accepted** - 2025-10-01

## Context
Fork repositories need automated version management that handles both local changes and upstream integration while keeping semantic versioning and a readable changelog. The versioning system must derive versions from commit messages, distinguish local from upstream changes in the changelog, tag releases with a reference to the upstream version, and run without manual intervention.

Versioning a fork by hand tends to blur local and upstream changes, leaving unclear changelogs and version histories.

## Decision
Adopt Google's Release Please with Conventional Commits:

1. **Conventional Commits**: Commit message format determines the version bump (`feat` minor, `fix` patch, `BREAKING CHANGE` major).
2. **Automated Changelog**: Release Please generates `CHANGELOG.md` from commit messages, grouped by type.
3. **Upstream Attribution**: Upstream integrations enter the changelog under their own `upstream` type. How those commits are produced is covered by ADR-023.
4. **Upstream-Correlated Tags**: Each release also gets a tag that records the upstream version it contains.
5. **GitHub Releases**: Releases are published as GitHub releases from the Release Please PR.

## Alternatives Considered

### 1. Manual Version Management
Complete control, but error-prone and requires a human on every release. Rejected.

### 2. Semantic Release
Popular with a large plugin ecosystem, but a Node.js dependency with more configuration and less GitHub-native behavior. Rejected in favor of Release Please.

### 3. Custom Versioning Script
Full customization, but reinvents an established tool and has to be maintained and tested. Rejected.

### 4. GitVersion or Similar Tools
Powerful branch-based versioning, but complex configuration and less suited to fully automated flows. Rejected.

## Consequences
The team must follow Conventional Commits, which validate.yml enforces on PR titles. Version determination is constrained to what commit types express, and releases are tied to GitHub's release mechanism.

## Implementation Details

### Release Please Configuration
`release.yml` runs `googleapis/release-please-action` (pinned to a v4 release). Configuration lives in `.release-please-config.json`: `release-type: simple`, tags with a `v` prefix, minor bumps before 1.0, and changelog sections for each commit type including an `⬆️ Upstream Changes` section for the `upstream` type.

### Upstream-Correlated Tags
The `tag-with-upstream` job in `release.yml` runs after a release is created. It fetches the upstream repository's tags, resolves the upstream version, and pushes a second tag of the form `<release-tag>-upstream-<upstream-version>`.

### Commit Message Validation
`validate.yml` checks PR titles for Conventional Commits format using `amannn/action-semantic-pull-request`. Upstream sync PRs and release PRs are exempt.

## Related Decisions

- [ADR-023: Meta-Commit Strategy for Release Please](023-meta-commit-strategy-for-release-please.md) - How upstream integrations become `upstream`-typed commits
- [ADR-029: GitHub App Authentication Strategy](029-github-app-authentication-strategy.md) - Authentication mechanism for release automation

---

[← ADR-003](003-template-repository-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-005 →](005-conflict-management.md)
