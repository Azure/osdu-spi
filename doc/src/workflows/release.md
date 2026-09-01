# Release Management Workflow

The release workflow creates semantic versions and publishes releases for the fork. It uses Release Please to read the commit history since the last release, choose the version bump, and generate the changelog.

The system maintains correlation between fork releases and upstream OSDU versions. It also applies the released semantic version to the service image already published to public GHCR by validation.

## When It Runs

The release workflow runs on:

- **Push to main** - Automatically scans for conventional commits and creates release PRs when changes are pushed to main
- **Release PR merge** - Immediately publishes the new version and creates a GitHub release when a release PR is merged

Changes limited to `.github/**` do not trigger this workflow.

## What Happens

The release process has two phases:

### Release PR Creation Phase
Release Please reads the conventional commits since the last release, calculates the version bump (major, minor, or patch), generates the changelog entry, and opens or updates a release PR with the version and changelog changes.

### Release Publication Phase
Once the release PR is reviewed and merged, Release Please creates the git tag and GitHub release. The workflow adds an upstream-correlation tag and notes, waits for validation to publish the release commit's immutable `sha-*` image, and creates the corresponding GHCR semantic-version tag without rebuilding the image.

## Version Calculation

Release Please automatically determines version bumps based on conventional commit prefixes:

| Commit Type | Version Impact | Example |
|-------------|----------------|---------|
| `feat:` | **Minor** (0.1.0) | New features or capabilities |
| `fix:` | **Patch** (0.0.1) | Bug fixes and corrections |
| `BREAKING CHANGE:` | **Major** (1.0.0) | Breaking changes or API changes |
| `chore:`, `docs:` | **No bump** | Maintenance, documentation |

### Breaking Changes
```bash
# Triggers major version bump
feat!: redesign user authentication API

# Or in commit body
feat: add new auth system

BREAKING CHANGE: Authentication API completely redesigned
```

## When You Need to Act

### Review Release PRs
- **New release PR created** - Check the version bump and changelog
- **Upstream correlation** - Check the upstream version the release will record

### Handle Failed Releases
- **Version conflicts** - Resolve tag conflicts or duplicate versions
- **Changelog issues** - Fix formatting or missing information
- **Publication failures** - Debug artifact publishing problems

## How to Respond

### Review Release PR
1. **Check version bump** - Verify appropriate version increase
2. **Review changelog** - Ensure all important changes are documented
3. **Validate correlation** - Confirm upstream version relationship
4. **Approve and merge** - Release will be published automatically

### Fix Version Issues

If an unpublished release PR proposes the wrong version, correct the contributing commits or manifest and update the PR. If a release is already published, use a follow-up conventional commit; the next push to `main` runs Release Please again. The workflow has no manual trigger.

### Update Changelog Manually
```bash
# Edit CHANGELOG.md if needed
git checkout release-please--branches--main
# Make edits to CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs: update changelog format"
git push
```

## Configuration

### Release Type

The repository uses Release Please's `simple` release type. Version state is stored in `.release-please-manifest.json`; the generated release PR updates the changelog and manifest rather than language-specific package files.

### Release Configuration
Located in `.release-please-config.json`:
```json
{
  "release-type": "simple",
  "changelog-sections": [
    {"type": "feat", "section": "Features"},
    {"type": "fix", "section": "Bug Fixes"},
    {"type": "chore", "section": "Miscellaneous", "hidden": true}
  ]
}
```

## Upstream Correlation

### Version Tracking
Each release maintains correlation with upstream versions through:
- **Release notes** - Document corresponding upstream version
- **Correlation tags** - Add `<release-tag>-upstream-<upstream-tag>`
- **Container tags** - Add `ghcr.io/<owner>/<service>:<version>` to the existing release-commit image

### Example Correlation
```
## [1.2.3] - 2025-01-15

### Features
- Updated from upstream OSDU v1.5.2 (commit: abc123)
- Added Azure-specific authentication improvements
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No release PR created" | Ensure conventional commits exist since last release |
| "Version calculation wrong" | Check commit message format, use `feat!:` for breaking |
| "Changelog missing entries" | Verify commit messages follow conventional format |
| "Release failed" | Check GitHub release permissions and tag conflicts |
| "Correlation tracking missing" | Update release notes with upstream version info |
| "Release image source did not appear" | Inspect the validation workflow's Docker push for the same `main` commit |

## Best Practices

### Commit Messages
```bash
# Good - triggers minor version
feat: add user preference management

# Good - triggers patch version
fix: resolve authentication timeout issue

# Good - triggers major version
feat!: redesign storage API interface

# Bad - no version bump
update some stuff
```

### Release Timing
- **Continuous** - Every eligible push to `main` updates or publishes the Release Please release
- **Release PR** - Merge the generated PR when the version and changelog are ready

## Integration

### With Other Workflows
- **Validation workflow** - Publishes immutable and branch-snapshot images for trusted `main` pushes
- **Release workflow** - Retags the release commit's image in GHCR with the semantic version

## Related

- [Conventional Commits](https://conventionalcommits.org/) - Commit message standards
- [Release Please](https://github.com/googleapis/release-please) - Official documentation
- [Semantic Versioning](https://semver.org/) - Version numbering standards
- [ADR-033: GHCR as Service Image Registry](../adr/033-ghcr-as-service-image-registry.md)