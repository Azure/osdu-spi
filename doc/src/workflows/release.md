# Release Management Workflow

The release management workflow automates the entire process of creating semantic versions and publishing releases for your fork, eliminating manual version management while ensuring consistent release practices. This workflow uses Google's Release Please tool to analyze your commit history, automatically determine appropriate version numbers, and generate professional changelogs that clearly communicate what changed between releases.

The system maintains correlation between your fork releases and corresponding upstream OSDU versions, providing clear traceability for compliance and auditing purposes. This is particularly valuable in enterprise environments where you need to demonstrate exactly which upstream changes are included in each of your fork releases.

## When It Runs

The release workflow operates on specific triggers to maintain consistent release cadence:

- **Push to main** - Automatically scans for conventional commits and creates release PRs when changes are pushed to main
- **Release PR merge** - Immediately publishes the new version and creates a GitHub release when a release PR is merged
- **Manual trigger** - Available on-demand via GitHub Actions for urgent releases or troubleshooting

## What Happens

The release process unfolds in two distinct phases, each handling different aspects of version management:

### Release PR Creation Phase
The workflow begins by scanning your commit history to analyze conventional commits that have been made since the last release, then calculates the appropriate version bump (major, minor, or patch) based on the types of changes detected. It generates a structured changelog that categorizes changes by type and impact, then creates a release PR containing all version updates and changelog modifications.

### Release Publication Phase
Once the release PR is reviewed and merged, the workflow immediately creates a git tag with the new version number, publishes a GitHub release using the generated changelog as release notes, triggers any additional workflows configured for artifact publishing or distribution, and sends notifications to configured channels to alert the team about the new release.

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
- **New release PR created** - Review version bump and changelog accuracy
- **Upstream correlation** - Verify relationship to upstream versions
- **Quality validation** - Ensure all tests pass before merge

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
```bash
# If wrong version was released
git tag -d v1.2.3  # Delete local tag
git push --delete origin v1.2.3  # Delete remote tag

# Manually trigger new release
# Go to Actions → Release Please → Run workflow
```

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

### Supported Project Types
- **Node.js** - Updates `package.json` version
- **Java/Maven** - Updates `pom.xml` version numbers
- **Python** - Updates `setup.py` or `pyproject.toml`
- **Multi-project** - Handles multiple packages in monorepos

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
- **Git tags** - Include upstream SHA reference
- **Changelog entries** - Note upstream integration points

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
- **Regular schedule** - Let Release Please run daily for consistency
- **Emergency releases** - Manual trigger for critical fixes
- **Coordination** - Align with upstream release cycles when possible

## Integration

### With OSDU Ecosystem
- **Upstream tracking** - Correlate with upstream OSDU version releases
- **Dependency updates** - Coordinate with other OSDU service updates
- **Testing integration** - Ensure releases work with OSDU platform versions

### Automation Triggers
- **Build workflows** - Triggered by new tags for artifact publishing
- **Deployment workflows** - Can be triggered by release events
- **Notification systems** - Team alerts for new releases

## Related

- [Conventional Commits](https://conventionalcommits.org/) - Commit message standards
- [Release Please](https://github.com/googleapis/release-please) - Official documentation
- [Semantic Versioning](https://semver.org/) - Version numbering standards