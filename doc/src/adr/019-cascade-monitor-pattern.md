# ADR-019: Cascade Monitor Pattern

## Status
**Accepted** - 2025-10-01  

## Context

The cascade workflow needs to be triggered when upstream changes are merged into the `fork_upstream` branch. However, experience has shown that automatic triggering creates reliability and usability issues:

1. **Event Trigger Limitations**: `pull_request_target` events require workflows to exist on the target branch (`fork_upstream`), but this branch is a pure mirror without workflow files
2. **Human Control**: Teams want explicit control over when integration happens, not automatic triggering
3. **Timing Control**: Humans may want to batch multiple changes or time integrations appropriately
4. **Visibility Requirements**: Clear audit trails and progress tracking are needed throughout the cascade lifecycle
5. **Error Recovery**: Failed or missed triggers need reliable detection and recovery mechanisms

The original approach assumed automatic triggering was preferred, but this created:

- Unreliable triggering due to workflow file availability issues
- Lack of human control over integration timing
- Poor visibility into cascade progress and state
- Complex error handling for edge cases
- No comprehensive tracking of issue lifecycle

## Decision

Implement a **Human-Centric Cascade Pattern** with monitor-based safety net:

1. **Primary Path - Manual Triggering**: Humans manually trigger cascade integration after reviewing and merging sync PRs
2. **Safety Net - Monitor Detection**: `cascade-monitor.yml` detects missed triggers and automatically initiates cascades as fallback
3. **Issue Lifecycle Tracking**: Comprehensive tracking of cascade state through GitHub issues with label management
4. **cascade.yml**: Enhanced with issue tracking and progress updates throughout the cascade process
5. **Human-in-the-Loop**: Explicit human control points with clear instructions and visibility

## Rationale

### Human Control and Visibility

- **Explicit Human Decisions**: Humans control when integration happens after reviewing changes
- **Clear Instructions**: sync.yml provides explicit steps for manual cascade triggering
- **Issue Lifecycle Tracking**: Complete audit trail from sync detection to production deployment
- **Progress Visibility**: Real-time updates on cascade state through issue comments

### Reliable Safety Net

- **Monitor as Backup**: Detects when humans forget to trigger cascades
- **Automatic Recovery**: Safety net triggers missed cascades with clear documentation
- **Git-based Detection**: Uses reliable branch comparison to detect pending changes
- **No Event Dependencies**: Not dependent on GitHub event triggering limitations

### Comprehensive State Management

- **Label-based Tracking**: Issue labels track cascade state progression
- **Comment-based Updates**: Detailed progress updates in tracking issues  
- **Error State Handling**: Automated failure detection and recovery workflows
- **Completion Tracking**: Issues closed when changes reach production
- **Self-Healing Recovery**: Automatic retry system based on human intervention signals

### Improved Team Experience

- **Predictable Process**: Teams know exactly when and how to trigger cascades
- **Better Timing Control**: Can batch changes or time integrations appropriately
- **Clear Error Recovery**: Obvious next steps when things go wrong
- **Reduced Surprises**: No unexpected automatic triggers

## Alternatives Considered

### 1. Direct Push Triggers

```yaml
# In cascade.yml
on:
  push:
    branches: [fork_upstream]
```
**Pros**: Simple, immediate triggering
**Cons**: Fires on all pushes, not just sync merges; no way to filter by intent
**Decision**: Rejected due to unwanted triggers

### 2. Combined PR and Push Triggers

```yaml
# In cascade.yml (original approach)
on:
  push:
    branches: [fork_upstream, fork_integration]
  pull_request:
    types: [closed]
    branches: [fork_upstream, fork_integration]
```

**Pros**: Handles various trigger scenarios
**Cons**: Complex conditional logic; hard to debug; no error handling
**Decision**: Rejected due to complexity and reliability issues

### 3. External Webhook System

**Pros**: Maximum flexibility, external control
**Cons**: Additional infrastructure; more complex setup; maintenance overhead
**Decision**: Rejected due to complexity for minimal benefit

### 4. Scheduled Polling

```yaml
on:
  schedule:
    - cron: '*/5 * * * *'  # Every 5 minutes
```

**Pros**: Guaranteed to catch changes eventually
**Cons**: Up to 5-minute delay; inefficient; doesn't scale well
**Decision**: Rejected as primary approach (kept as backup in monitor)

## Implementation Details

### Sync Workflow Instructions

```yaml
# In sync.yml notification
**Next Steps:**
1. 🔍 **Review the sync PR** for any breaking changes or conflicts
2. ✅ **Merge the PR** when satisfied with the changes  
3. 🚀 **Manually trigger 'Cascade Integration' workflow** to integrate changes
4. 📊 **Monitor cascade progress** in Actions tab
```

### Monitor Safety Net Structure

```yaml
name: Cascade Monitor

on:
  schedule:
    - cron: '0 */6 * * *'  # Safety net detection every 6 hours
  workflow_dispatch:        # Manual health checking

jobs:
  detect-missed-cascade:
    steps:
      - name: Check for missed cascade triggers
        run: |
          # Check if fork_upstream has commits that fork_integration doesn't
          UPSTREAM_COMMITS=$(git rev-list --count origin/fork_integration..origin/fork_upstream)
          
          if [ "$UPSTREAM_COMMITS" -gt 0 ]; then
            # Find tracking issue using improved label search
            ISSUE_NUMBER=$(gh issue list \
              --label "upstream-sync" \
              --state open \
              --limit 1 \
              --json number \
              --jq '.[0].number // empty')
            
            if [ -n "$ISSUE_NUMBER" ]; then
              # Comment on issue and auto-trigger cascade as safety net
              gh workflow run "Cascade Integration" \
                --repo ${{ github.repository }} \
                -f issue_number="$ISSUE_NUMBER"
            fi
          fi
```

### Issue Lifecycle Tracking

```bash
# Cascade workflow uses provided issue number for tracking

# Issue number passed as workflow input
ISSUE_NUMBER="${{ github.event.inputs.issue_number }}"

# When cascade starts
gh issue edit "$ISSUE_NUMBER" \
  --remove-label "human-required" \
  --add-label "cascade-active"

gh issue comment "$ISSUE_NUMBER" --body "🚀 **Cascade Integration Started** - $(date -u +%Y-%m-%dT%H:%M:%SZ)
Integration workflow has been triggered and is now processing upstream changes."

# When conflicts detected
gh issue edit "$ISSUE_NUMBER" \
  --remove-label "cascade-active" \
  --add-label "cascade-blocked"

# When production PR created
gh issue edit "$ISSUE_NUMBER" \
  --remove-label "cascade-active" \
  --add-label "production-ready"

gh issue comment "$ISSUE_NUMBER" --body "🎯 **Production PR Created** - $(date -u +%Y-%m-%dT%H:%M:%SZ)
Integration completed successfully! Production PR has been created and is ready for final review."
```

### Health Monitoring Integration

The monitor also includes periodic health checks:

- **Stale Conflict Detection**: Find conflicts older than 48 hours
- **Pipeline Health Reports**: Overall cascade pipeline status
- **Escalation Management**: Automatic escalation of long-running issues

## Consequences

### Positive

- **Human Control**: Teams have explicit control over integration timing
- **Reliability**: No dependency on GitHub event triggering edge cases
- **Visibility**: Complete audit trail through issue lifecycle tracking
- **Error Recovery**: Clear path to resolution when things go wrong
- **Predictability**: Consistent, documented process for all team members
- **Safety Net**: Automatic detection and recovery of missed triggers
- **Flexibility**: Can batch changes or time integrations appropriately

### Negative

- **Manual Step Required**: Humans must remember to trigger cascades
- **Potential Delays**: Up to 6 hours delay if manual trigger is forgotten
- **Additional Complexity**: Issue lifecycle tracking adds workflow complexity
- **Learning Curve**: Team needs to understand manual trigger process
- **Monitor Dependency**: Safety net relies on monitor workflow functioning

### Neutral

- **File Count**: Adds one additional workflow file
- **Maintenance**: Two simpler workflows vs. one complex workflow
- **Testing**: Need to test both trigger detection and cascade execution

## Integration Points

### With Sync Workflow

- Sync workflow creates PRs with `upstream-sync` label
- Sync workflow creates tracking issues with explicit manual trigger instructions
- Humans review, merge PR, and manually trigger cascade

### With Cascade Workflow

- Cascade runs on `workflow_dispatch` (manual or monitor-triggered)
- Cascade updates tracking issue labels and comments throughout process
- Cascade handles conflicts, integration, and production PR creation
- Error states tracked through issue labels and comments

### With Label Management (ADR-008)

- Uses predefined labels: `upstream-sync`, `cascade-trigger-failed`, `human-required`
- Leverages existing label-based notification system
- Maintains consistency with other workflow patterns

## Monitoring and Alerting

### Success Metrics

- **Manual Trigger Adoption**: % of sync merges followed by manual cascade triggers
- **Safety Net Effectiveness**: % of missed triggers caught by monitor
- **Issue Lifecycle Completeness**: % of cascades with complete issue tracking
- **Human Response Time**: Time between sync completion and manual trigger
- **Error Recovery**: Time to resolve cascade conflicts and issues

### Failure Modes

1. **Forgotten Manual Trigger**: Monitor safety net detects and auto-triggers
2. **Monitor Workflow Failure**: Manual cascade trigger still available
3. **Issue Tracking Failure**: Cascade proceeds but with reduced visibility
4. **Cascade Integration Conflicts**: Clear conflict resolution workflow with SLA

### Health Checks

- **Daily Pipeline Status**: Monitor generates health reports
- **Stale Issue Detection**: Automatically escalates old problems
- **Cascade Pipeline Monitoring**: Overall system health visibility

## Future Enhancements

### Planned Improvements

1. **Batch Triggering**: Group multiple rapid changes into single cascade
2. **Priority Queuing**: Handle urgent vs. routine upstream changes differently
3. **Smart Scheduling**: Avoid triggers during maintenance windows
4. **Cross-Repository Coordination**: Coordinate cascades across multiple forks

### Extensibility Points

- **Custom Trigger Logic**: Easy to add new trigger conditions
- **External Integrations**: Webhook support for external systems
- **Advanced Error Handling**: Sophisticated retry and recovery strategies
- **Metrics Collection**: Detailed analytics on trigger patterns

### Automated Failure Recovery Pattern

The monitor implements a sophisticated failure recovery system that enables self-healing cascade workflows:

#### Failure State Management
```yaml
# Normal cascade state progression
upstream-sync → cascade-active → validated

# Failure state progression  
upstream-sync → cascade-active → cascade-failed + human-required
```

#### Recovery Detection Logic
```yaml
detect-recovery-ready:
  name: "🔄 Automatic Recovery - Detect Ready Retries"
  steps:
    - name: Check for recovery-ready issues
      run: |
        # Find issues with cascade-failed but NOT human-required
        RECOVERY_ISSUES=$(gh issue list \
          --label "cascade-failed" \
          --state open \
          --jq '.[] | select(.labels | contains(["cascade-failed"]) and (contains(["human-required"]) | not))')
        
        # For each recovery-ready issue
        echo "$RECOVERY_ISSUES" | jq -r '.number' | while read ISSUE_NUMBER; do
          # Update labels: cascade-failed → cascade-active
          gh issue edit "$ISSUE_NUMBER" \
            --remove-label "cascade-failed" \
            --add-label "cascade-active"
          
          # Trigger cascade retry
          gh workflow run "Cascade Integration" \
            --repo ${{ github.repository }} \
            -f issue_number="$ISSUE_NUMBER"
        done
```

#### Human Recovery Workflow

1. **Failure Occurs**: Cascade fails, tracking issue gets `cascade-failed + human-required`
2. **Failure Issue Created**: Technical details in separate high-priority issue
3. **Human Investigation**: Developer reviews failure issue and makes fixes
4. **Signal Resolution**: Human removes `human-required` label from tracking issue
5. **Automatic Retry**: Monitor detects label removal and retries cascade
6. **Success/Failure**: Either completes successfully or creates new failure issue

#### Benefits of Label-Based Recovery

- **Self-Healing**: No manual workflow triggering required
- **Clear Handoff**: Labels signal automation ↔ human transitions
- **Audit Trail**: Complete failure/recovery history in tracking issues
- **Robust Error Handling**: Multiple failure attempts tracked separately
- **Predictable Process**: Developers know exactly how to signal resolution

## Related Decisions

- [ADR-001: Three-Branch Fork Management Strategy](001-three-branch-strategy.md) - Defines the cascade target branches
- [ADR-005: Automated Conflict Management Strategy](005-conflict-management.md) - Conflict handling within cascades
- [ADR-008: Centralized Label Management Strategy](008-centralized-label-management.md) - Label-based state management
- [ADR-009: Asymmetric Cascade Review Strategy](009-asymmetric-cascade-review-strategy.md) - Review requirements for cascades

## Success Criteria

- 90%+ of sync merges followed by manual cascade triggers within 2 hours
- 100% of missed manual triggers detected by safety net within 6 hours
- Complete issue lifecycle tracking for 95%+ of cascades
- Conflict resolution SLA: 48 hours with automatic escalation
- Zero unexpected cascade triggers (only manual or safety net)
- Clear audit trail for all cascade decisions through issue tracking
- Team adoption: 100% of team members comfortable with manual trigger process

---

[← ADR-018](018-fork-resources-staging-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-020 →](020-human-required-label-strategy.md)
