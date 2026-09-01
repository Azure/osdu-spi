# ADR-023: Meta Commit Strategy for Release Please Integration

## Status
Accepted

## Context
Fork management requires synchronizing upstream commits that don't follow conventional commit format with Release Please automation that requires conventional commits for versioning decisions. This creates a fundamental conflict between preserving upstream commit history and maintaining automated release management.

### Problem Analysis
- **Upstream Reality**: OSDU and other upstream repositories use varied commit message formats
- **Release Please Requirement**: Needs conventional commits (`feat:`, `fix:`, etc.) for semantic versioning
- **History Preservation**: Enterprise debugging requires complete commit attribution and traceability
- **Validation Conflict**: Conventional commit validation fails on non-conventional upstream commits

### Solutions Considered
1. **Squash Merge**: Combine all upstream changes into single conventional commit
2. **Commit Message Transformation**: Rewrite upstream commit messages to conventional format
3. **Meta Commit Strategy**: Preserve upstream commits + add conventional meta commit for Release Please
4. **Manual Release Management**: Bypass automation for upstream changes

## Decision
Implement **Meta Commit Strategy**, classifying the bump with a deterministic rule over the
upstream commit range.

> **Revised 2026-09-01 (#162).** This ADR originally delegated classification to `aipr commit`.
> That call crashed on every run and the `feat:` fallback fired every time, so every sync forced
> a minor bump regardless of content; the reference fork shipped v1.1.0 → v1.2.0 with no patch
> release ever. A published version number is a contract: the same range must always yield the
> same bump, and a wrong bump must be a fixable bug rather than a sampling artifact.

### Implementation Approach
1. **Preserve Upstream History**: Merge upstream commits with `--no-edit` to maintain original attribution
2. **Generate Meta Commit**: Classify the upstream range by rule; max severity wins
3. **Release Please Integration**: Meta commit drives versioning decisions while history remains intact
4. **Conservative Default**: Non-conventional upstream commits classify as `fix:` (patch), never `feat:`

### Technical Implementation
```yaml
# Capture state before sync
BEFORE_SHA=$(git rev-parse fork_upstream)

# Complete merge preserving upstream history
git merge upstream/$DEFAULT_BRANCH -X theirs --no-edit

# Classify by rule: breaking > feat > fix, defaulting to fix.
# `!` is only meaningful on a subject; the BREAKING CHANGE footer lives in the body.
RANGE="$BEFORE_SHA..HEAD"
if grep -qE '^[a-z]+(\([^)]*\))?!:' <<<"$(git log --format=%s "$RANGE")" \
   || grep -qE '^BREAKING[ -]CHANGE:' <<<"$(git log --format=%b "$RANGE")"; then
  META_COMMIT_MSG="feat!: sync upstream changes from $UPSTREAM_VERSION"
elif grep -qE '^feat(\([^)]*\))?:' <<<"$(git log --format=%s "$RANGE")"; then
  META_COMMIT_MSG="feat: sync upstream changes from $UPSTREAM_VERSION"
else
  META_COMMIT_MSG="fix: sync upstream changes from $UPSTREAM_VERSION"
fi

# Add meta commit for Release Please
git commit --allow-empty -m "$META_COMMIT_MSG"
```

## Rationale

### Why Meta Commit Strategy is Optimal

**Enterprise Requirements Met:**

- ✅ Complete OSDU commit history preserved for debugging
- ✅ Full git blame/bisect capability maintained  
- ✅ Regulatory audit trail compliance
- ✅ Individual commit attribution intact

**Automation Requirements Met:**

- ✅ Release Please works seamlessly with meta commits
- ✅ Reproducible, auditable conventional commit categorization
- ✅ Automated semantic versioning continues
- ✅ Changelog generation remains functional

**Technical Advantages:**

- ✅ Simple 4-step implementation
- ✅ No complex git history rewriting
- ✅ Robust error handling with fallbacks
- ✅ No external tool or API dependency

### Why Not Other Solutions

**Squash Merge Rejected:**

- ❌ Loses granular OSDU history critical for debugging
- ❌ Makes cherry-picking and selective reverts impossible
- ❌ Breaks enterprise traceability requirements

**Commit Transformation Rejected:**

- ❌ Complex implementation with high failure risk
- ❌ May break git signatures and upstream attribution
- ❌ Difficult to maintain reliability across edge cases

**Manual Release Rejected:**

- ❌ Loses automation benefits
- ❌ Introduces human error potential
- ❌ Doesn't scale with frequent upstream syncs

## Implementation Details

### Classification Rule

- **Scope**: Commit messages between the last sync point and the generated tree
- **Precedence**: a subject `!` or a `BREAKING CHANGE:` body footer → major; any `feat:` subject → minor; otherwise patch
- **Determinism**: No network call, no timeout, no fallback path

### Error Handling Strategy

The rule has no failure mode: an empty or wholly non-conventional range classifies as `fix:`,
which bumps patch. There is nothing to time out and nothing to fall back to.

### Validation Requirements

- Conventional commit format: `type: description` with non-empty description
- Supported types: `feat|fix|chore|docs|style|refactor|perf|test|build|ci`
- Non-conventional upstream commits classify as `fix:`; there is no failure path

## Consequences

### Positive

- **Reliable Automation**: Release Please integration works consistently
- **Preserved History**: Complete upstream commit attribution maintained
- **Enterprise Compliance**: Audit trail requirements satisfied
- **Reproducible Versioning**: The same commit range always yields the same bump
- **No External Dependency**: No API key, no network call, nothing to time out

### Negative

- **Mixed Commit History**: Developers see conventional + non-conventional commits
- **Additional Complexity**: Meta commit logic adds workflow steps
- **Coarse Categorization**: A rule cannot read intent the way a reviewer can; an upstream repo that does not use conventional commits will always classify as patch

### Neutral

- **Release Please Behavior**: Functions exactly as designed for mixed commit repositories
- **Git History Size**: Minimal increase due to empty meta commits
- **Performance Impact**: Negligible overhead from additional commit

## Monitoring and Success Criteria

### Success Metrics

- Release Please correctly versions based on meta commits
- No workflow failures due to conventional commit validation
- Complete upstream history preservation verified

### Monitoring Points

- Bump classification emitted in workflow logs on every sync
- Release Please version bumping accuracy
- Meta commit format compliance
- Upstream sync completion times

## Future Evolution

### Potential Enhancements

- Custom conventional commit type mappings for specific file patterns
- Integration with upstream release notes for better categorization
- Advanced conflict resolution strategies for complex merges

### Migration Strategy

- Current implementation is additive (no breaking changes)
- Can be disabled by reverting to simple merge if needed
- Compatible with existing Release Please configurations
- No impact on existing fork instances

---

## References

- [Release Please Documentation](https://github.com/googleapis/release-please)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [ADR-001: Three-Branch Strategy](001-three-branch-strategy.md)
- [ADR-011: Configuration-Driven Template Sync](011-configuration-driven-template-sync.md)

---

[← ADR-022](022-issue-lifecycle-tracking-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-024 →](024-sync-workflow-duplicate-prevention-architecture.md)
