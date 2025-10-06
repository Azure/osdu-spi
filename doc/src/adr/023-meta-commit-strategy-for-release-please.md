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
Implement **Meta Commit Strategy** using AIPR 1.4.0's commit range analysis capability.

### Implementation Approach
1. **Preserve Upstream History**: Merge upstream commits with `--no-edit` to maintain original attribution
2. **Generate Meta Commit**: Use AI to analyze upstream changes and create conventional commit
3. **Release Please Integration**: Meta commit drives versioning decisions while history remains intact
4. **Robust Fallback**: Default to `feat:` if AI analysis fails

### Technical Implementation
```yaml
# Capture state before sync
BEFORE_SHA=$(git rev-parse fork_upstream)

# Complete merge preserving upstream history
git merge upstream/$DEFAULT_BRANCH -X theirs --no-edit

# Generate conventional meta commit with AI analysis
META_COMMIT_MSG=$(aipr commit --from $BEFORE_SHA --context "upstream sync")

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
- ✅ Accurate conventional commit categorization via AI
- ✅ Automated semantic versioning continues
- ✅ Changelog generation remains functional

**Technical Advantages:**

- ✅ Simple 4-step implementation
- ✅ No complex git history rewriting
- ✅ Robust error handling with fallbacks
- ✅ Uses AIPR exactly as designed

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

### AI Integration

- **Tool**: AIPR 1.4.0+ with `--from <SHA>` capability
- **Analysis Scope**: Changes between last sync point and current HEAD
- **Context**: "upstream sync" helps AI categorize appropriately
- **Timeout**: 60 seconds to prevent workflow hanging

### Error Handling Strategy

```yaml
# Comprehensive fallback chain
if timeout 60s aipr commit --from $BEFORE_SHA --context "upstream sync"; then
  # Use AI-generated conventional commit
else
  # Fallback to conservative feat: message
  META_COMMIT_MSG="feat: sync upstream changes from $UPSTREAM_VERSION"
fi
```

### Validation Requirements

- Conventional commit format: `type: description` with non-empty description
- Supported types: `feat|fix|chore|docs|style|refactor|perf|test|build|ci`
- Minimum description length validation
- Graceful handling of AI service outages

## Consequences

### Positive

- **Reliable Automation**: Release Please integration works consistently
- **Preserved History**: Complete upstream commit attribution maintained
- **Enterprise Compliance**: Audit trail requirements satisfied
- **AI Enhancement**: Intelligent categorization when services available
- **Fallback Reliability**: Workflow never fails due to AI issues

### Negative

- **Mixed Commit History**: Developers see conventional + non-conventional commits
- **Additional Complexity**: Meta commit logic adds workflow steps
- **AI Dependency**: Optimal categorization requires external AI services

### Neutral

- **Release Please Behavior**: Functions exactly as designed for mixed commit repositories
- **Git History Size**: Minimal increase due to empty meta commits
- **Performance Impact**: Negligible overhead from additional commit

## Monitoring and Success Criteria

### Success Metrics

- Release Please correctly versions based on meta commits
- No workflow failures due to conventional commit validation
- AI analysis success rate > 80% (with graceful fallback)
- Complete upstream history preservation verified

### Monitoring Points

- AIPR success/failure rates in workflow logs
- Release Please version bumping accuracy
- Meta commit format compliance
- Upstream sync completion times

## Future Evolution

### Potential Enhancements

- Enhanced AI context with upstream repository analysis
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

- [AIPR 1.4.0 Documentation](https://pypi.org/project/pr-generator-agent/)
- [Release Please Documentation](https://github.com/googleapis/release-please)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [ADR-001: Three-Branch Strategy](001-three-branch-strategy.md)
- [ADR-011: Configuration-Driven Template Sync](011-configuration-driven-template-sync.md)

---

[← ADR-022](022-issue-lifecycle-tracking-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-024 →](024-sync-workflow-duplicate-prevention-architecture.md)
