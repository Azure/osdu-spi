# ADR-005: Automated Conflict Management Strategy

## Status
**Accepted** - 2025-10-01

## Context
When synchronizing with upstream repositories, merge conflicts are inevitable due to modifications made in the fork. The system needs to handle conflicts in a way that:

- Prevents automatic merging of conflicted code
- Provides clear visibility into conflicts and their resolution requirements
- Maintains the stability of the main branch during conflict resolution
- Enables systematic resolution of conflicts without blocking other development
- Tracks conflict resolution decisions for future reference

Traditional approaches often result in conflicts being resolved directly on main branches, leading to instability, or conflicts being ignored, leading to drift from upstream.

## Decision
Implement an automated conflict management strategy that:

1. **Conflict Detection**: Automatically detect merge conflicts during upstream synchronization
2. **Isolation Strategy**: Use the `fork_integration` branch for conflict resolution
3. **Issue Creation**: Create GitHub Issues for each conflict requiring resolution
4. **Pull Request Workflow**: Create separate PRs for conflict resolution and integration
5. **Manual Resolution**: Require human review for all conflict resolutions
6. **Documentation**: Maintain clear records of conflict resolution decisions

## Rationale

### Automated Detection Benefits
1. **Early Warning**: Conflicts identified immediately during sync process
2. **Visibility**: Team is notified of conflicts through issues and PRs
3. **Prevention**: Prevents conflicted code from reaching main branch
4. **Systematic**: Consistent handling of all conflicts regardless of complexity
5. **Audit Trail**: Complete record of when conflicts occurred and how they were resolved

### Fork Integration Branch Strategy
1. **Isolation**: Conflicts resolved in dedicated branch without affecting main
2. **Safety**: Main branch remains stable during conflict resolution process
3. **Flexibility**: Multiple conflicts can be resolved independently
4. **Testing**: Conflict resolutions can be tested before integration
5. **Rollback**: Easy to abandon problematic conflict resolutions

### Issue-Driven Process
1. **Accountability**: Clear ownership of conflict resolution tasks
2. **Discussion**: Platform for discussing resolution strategies
3. **Documentation**: Permanent record of resolution decisions and rationale
4. **Tracking**: Progress tracking and resolution status visibility
5. **Knowledge Transfer**: Future conflicts can reference previous resolution patterns

## Alternatives Considered

### 1. Automatic Conflict Resolution
- **Pros**: No manual intervention, faster integration
- **Cons**: Risk of incorrect resolutions, loss of context, potential data loss
- **Decision**: Rejected due to safety and quality concerns

### 2. Conflict Resolution on Main Branch
- **Pros**: Simpler workflow, direct resolution
- **Cons**: Destabilizes main branch, blocks other development, risky
- **Decision**: Rejected due to stability requirements

### 3. Feature Branch per Conflict
- **Pros**: Complete isolation of each conflict
- **Cons**: Branch proliferation, complex tracking, overhead
- **Decision**: Rejected due to management complexity

### 4. Manual Conflict Detection
- **Pros**: Human judgment in conflict identification
- **Cons**: Inconsistent, delays in detection, human error prone
- **Decision**: Rejected due to automation requirements

## Consequences

### Positive
- **Stability**: Main branch protected from conflicts during resolution
- **Visibility**: Clear tracking of all conflicts and their resolution status
- **Quality**: Human review ensures appropriate conflict resolution
- **Documentation**: Permanent record of resolution decisions for future reference
- **Systematic**: Consistent handling regardless of conflict complexity
- **Safe**: Multiple review points before conflicts reach production

### Negative
- **Manual Overhead**: Requires human intervention for all conflicts
- **Potential Delays**: Conflicts must be resolved before upstream integration
- **Process Complexity**: Multiple branches and PRs for conflict resolution
- **Learning Curve**: Team must understand conflict resolution workflow

## Implementation Details

### Current Architecture (2025)

The conflict management strategy is now integrated with the **Cascade Monitor Pattern** (ADR-019) and uses the **Human-Required Label Strategy** (ADR-020):

1. **Sync Workflow**: Creates clean PRs to `fork_upstream` when possible
2. **Cascade Monitor**: Detects merged sync PRs and triggers cascade
3. **Cascade Workflow**: Handles conflict detection and resolution during integration

### Conflict Detection in Cascade Workflow
```yaml
# In cascade.yml - Phase 1: Upstream to Integration
- name: Merge upstream into fork_integration
  id: merge_upstream
  run: |
    # Merge fork_upstream into fork_integration
    echo "Merging upstream changes into fork_integration..."
    CONFLICTS_FOUND=false
    
    if git merge origin/fork_upstream --no-edit; then
      echo "✅ Clean merge of upstream changes achieved"
    else
      # Check if there are unresolved conflicts
      if git status --porcelain | grep -q "^UU\|^AA\|^DD"; then
        echo "::warning::Merge conflicts detected"
        CONFLICTS_FOUND=true
        
        # List conflicted files
        echo "Conflicted files:"
        git diff --name-only --diff-filter=U | tee conflicted_files.txt
        
        # Create conflict resolution issue
        CONFLICT_BODY="Upstream merge conflicts detected in fork_integration branch.
        
        **Conflicted Files:**
        \`\`\`
        $(cat conflicted_files.txt)
        \`\`\`
        
        **Next Steps:**
        1. Checkout the fork_integration branch locally
        2. Resolve conflicts in the listed files
        3. Commit and push the resolution
        4. The cascade will automatically continue once conflicts are resolved
        
        **SLA:** 48 hours for resolution"
        
        gh issue create \
          --title "🚨 Cascade Conflicts: Manual Resolution Required - $(date +%Y-%m-%d)" \
          --body "$CONFLICT_BODY" \
          --label "conflict,cascade-blocked,high-priority,human-required"
        
        echo "conflicts=true" >> $GITHUB_OUTPUT
        exit 1
      else
        echo "✅ Merge completed with automatic resolution"
      fi
    fi
    
    echo "conflicts=false" >> $GITHUB_OUTPUT
```

### Current Conflict Resolution Process (2025)
1. **Trigger**: Cascade monitor detects sync PR merge to `fork_upstream`
2. **Attempt Integration**: Cascade workflow attempts merge to `fork_integration`
3. **Conflict Detection**: Automated detection of merge conflicts during cascade
4. **Issue Creation**: Issue created with `conflict,cascade-blocked,human-required` labels
5. **Manual Resolution**: Developer resolves conflicts directly in `fork_integration` branch
6. **Automatic Continuation**: Once resolved, cascade automatically continues to main
7. **SLA Management**: Conflicts older than 48 hours are automatically escalated
8. **Cleanup**: Issues closed when conflicts resolved and cascade completes

### Label-Based Management (ADR-020)
- **Primary Label**: `human-required` - Indicates manual intervention needed
- **Type Label**: `conflict` - Identifies the type of issue  
- **Status Label**: `cascade-blocked` - Shows pipeline is blocked
- **Priority Label**: `high-priority` - Indicates urgency level

### Conflict Categorization
- **Code Conflicts**: Overlapping changes in source files
- **Configuration Conflicts**: Changes to build files, dependencies
- **Documentation Conflicts**: README, documentation updates
- **Deletion Conflicts**: Files deleted in upstream or fork

### Resolution Guidelines
- **Preserve Fork Intent**: Maintain the purpose of fork-specific changes
- **Adopt Upstream Improvements**: Integrate beneficial upstream changes
- **Document Decisions**: Explain resolution rationale in PR description
- **Test Thoroughly**: Ensure resolution doesn't break functionality
- **Consistent Patterns**: Follow established resolution patterns for similar conflicts

## Success Criteria
- No conflicted code ever reaches the main branch
- All conflicts are detected automatically during sync process
- Conflict resolution issues are created with actionable information
- Average conflict resolution time is under 48 hours
- Resolution decisions are clearly documented for future reference
- Team can handle conflicts without blocking regular development work
- Conflict resolution patterns become consistent over time

---

[← ADR-004](004-release-please-versioning.md) | :material-arrow-up: [Catalog](index.md) | [ADR-006 →](006-two-workflow-initialization.md)