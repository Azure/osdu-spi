# ADR-004: Release Please for Automated Version Management

## Status
**Accepted** - 2025-10-01

## Context
Fork repositories need automated version management that can handle both local changes and upstream integration while maintaining semantic versioning and clear changelog documentation. The versioning system must:

- Support semantic versioning based on commit message conventions
- Generate meaningful changelogs that distinguish local vs upstream changes
- Maintain release tags that reference both local and upstream versions
- Automate the release process without manual intervention
- Integrate with the three-branch fork management strategy

Traditional versioning approaches for forks often struggle with distinguishing between local changes and upstream integration, leading to unclear changelogs and confusing version histories.

## Decision
Adopt Google's Release Please action for automated version management with Conventional Commits, configured to:

1. **Conventional Commits**: Enforce commit message format for automated version determination
2. **Automated Changelog**: Generate changelogs from commit messages with custom formatting
3. **Semantic Versioning**: Automatically determine version bumps based on commit types
4. **Release Tags**: Create tags with upstream version references
5. **Release Notes**: Publish GitHub releases with comprehensive change documentation

## Rationale

### Release Please Benefits
1. **Industry Standard**: Widely adopted by Google and open-source community
2. **Conventional Commits**: Standardized commit message format enables automation
3. **Semantic Versioning**: Automatic version determination based on change types
4. **Changelog Generation**: Automatically generates and maintains CHANGELOG.md
5. **GitHub Integration**: Native GitHub releases with proper tagging
6. **Flexible Configuration**: Customizable for fork-specific requirements

### Conventional Commits Alignment
1. **Clear Intent**: Commit messages explicitly declare change types
2. **Automated Processing**: Enables automated version determination
3. **Team Communication**: Improves commit message quality and consistency
4. **Breaking Changes**: Clear marking of breaking changes for major version bumps
5. **Feature Tracking**: Easy identification of new features vs bug fixes

### Fork-Specific Adaptations
1. **Upstream References**: Release tags include upstream version information
2. **Change Attribution**: Changelog distinguishes between local and upstream changes
3. **Integration Tracking**: Clear documentation of upstream integration points
4. **Version Correlation**: Maintains relationship between fork and upstream versions

## Alternatives Considered

### 1. Manual Version Management
- **Pros**: Complete control, simple implementation
- **Cons**: Error-prone, time-consuming, inconsistent, requires human intervention
- **Decision**: Rejected due to automation requirements

### 2. Semantic Release
- **Pros**: Popular, flexible, extensive plugin ecosystem
- **Cons**: Node.js dependency, complex configuration, less GitHub native
- **Decision**: Rejected in favor of GitHub-native solution

### 3. Custom Versioning Script
- **Pros**: Full customization, fork-specific logic
- **Cons**: Maintenance overhead, testing requirements, reinventing established patterns
- **Decision**: Rejected due to maintenance complexity

### 4. GitVersion or Similar Tools
- **Pros**: Powerful versioning logic, branch-based versioning
- **Cons**: Complex configuration, learning curve, less automation-friendly
- **Decision**: Rejected due to complexity and automation requirements

## Consequences

### Positive
- **Automated Releases**: No manual intervention required for version management
- **Consistent Versioning**: Semantic versioning ensures predictable version progression
- **Clear Changelogs**: Automated changelog generation with meaningful categorization
- **GitHub Integration**: Native GitHub releases with proper asset management
- **Team Productivity**: Eliminates manual release tasks and potential errors
- **Audit Trail**: Complete version history with clear change attribution

### Negative
- **Commit Message Discipline**: Team must follow Conventional Commits format
- **Limited Flexibility**: Version determination is constrained by commit message rules
- **GitHub Dependency**: Tied to GitHub's release mechanism
- **Learning Curve**: Team needs to understand Conventional Commits format

## Implementation Details

### Conventional Commits Format
```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New features (minor version bump)
- `fix`: Bug fixes (patch version bump)
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test additions or modifications
- `chore`: Maintenance tasks
- `BREAKING CHANGE`: Breaking changes (major version bump)

### Release Please Configuration
```yaml
# .github/workflows/release.yml
- uses: googleapis/release-please-action@v3
  with:
    release-type: simple
    package-name: fork-management-template
    changelog-types: |
      [
        {"type":"feat","section":"Features","hidden":false},
        {"type":"fix","section":"Bug Fixes","hidden":false},
        {"type":"chore","section":"Miscellaneous","hidden":false},
        {"type":"upstream","section":"Upstream Integration","hidden":false}
      ]
```

### Fork-Specific Enhancements
- **Upstream Tags**: Release tags include reference to upstream version
- **Change Attribution**: Commits marked with source (local vs upstream)
- **Integration Notes**: Special handling for upstream integration commits
- **Version Correlation**: Changelog includes upstream version references

### Validation Workflow Integration
The validate.yml workflow enforces Conventional Commits format:
```yaml
- name: Validate Commit Messages
  uses: wagoid/commitlint-github-action@v5
  with:
    configFile: .commitlintrc.json
```

## Success Criteria
- Releases are generated automatically based on commit messages
- Changelog accurately reflects all changes with clear categorization
- Version numbers follow semantic versioning principles
- Release tags include upstream version references where applicable
- Team can easily identify what changed between releases
- Breaking changes are clearly identified and documented
- No manual intervention required for standard release process

## Related Decisions

- [ADR-029: GitHub App Authentication Strategy](029-github-app-authentication-strategy.md) - Authentication mechanism for release automation

---

[← ADR-003](003-template-repository-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-005 →](005-conflict-management.md)
