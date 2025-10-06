# ADR-020: Human-Required Label Strategy

## Status
**Accepted** - 2025-10-01  

## Context

GitHub workflows often need to create issues and pull requests that require human attention. The traditional approach is to assign these items to specific users using the `--assignee` flag in GitHub CLI commands. However, this approach has several significant problems:

1. **Username Resolution Issues**: GitHub's GraphQL API requires exact usernames, and organization names cannot be assigned to issues
2. **Dynamic User Context**: Different workflows run in different contexts (different triggering users, repository owners)
3. **API Failures**: Invalid usernames cause workflow failures with cryptic GraphQL errors like "Could not resolve to a User with the login of 'organization-name'"
4. **Maintenance Overhead**: Hardcoded usernames become stale and need constant updates
5. **Cross-Repository Complexity**: Template repositories used across multiple instances need flexible assignment

The original implementation used patterns like:

```yaml
--assignee "${{ github.repository_owner }}"  # Organization name (invalid)
--assignee "hardcoded-username"              # Brittle and unmaintainable
```

This led to workflow failures that blocked critical automation processes.

## Decision

Replace assignee-based task management with a **Human-Required Label Strategy** that uses GitHub's label system for task visibility and workflow management:

1. **Eliminate Assignees**: Remove all `--assignee` flags from automated workflows
2. **Human-Required Label**: Use `human-required` label to mark items needing attention
3. **Label-Based Filtering**: Team members can filter on labels to find work
4. **Robust Labeling**: Labels never fail - no username resolution required
5. **Flexible Organization**: Different label combinations for different priority/types

## Rationale

### Reliability Benefits

- **No Username Resolution**: Labels don't require user validation
- **Never Fail**: Invalid labels are ignored, not workflow-blocking errors
- **Universal Compatibility**: Works across all repositories and contexts
- **Template-Friendly**: No hardcoded usernames in template repositories

### Workflow Management Benefits

- **Better Filtering**: Teams can create custom views using label combinations
- **Priority Systems**: Multiple priority labels (`high-priority`, `emergency`) 
- **Type Classification**: Label-based categorization (`conflict`, `sync-failed`, `escalation`)
- **Automated Processing**: Workflows can query and act on labels reliably

### Organizational Benefits

- **Team Flexibility**: Any team member can work on `human-required` items
- **Load Balancing**: No single person overwhelmed with assignments
- **Scalable Process**: Works regardless of team size or structure
- **Clear Ownership**: Labels indicate type and urgency without specific assignment

## Implementation Details

### Core Labels Used

From `.github/labels.json` (managed by ADR-008):
```json
{
  "name": "human-required",
  "description": "Requires human intervention or review",
  "color": "D73A49"
}
```

### Supporting Labels

- `high-priority`: Urgent items requiring immediate attention
- `conflict`: Merge conflicts requiring manual resolution
- `escalation`: Issues that have exceeded SLA timeouts
- `sync-failed`: Failed synchronization operations
- `cascade-trigger-failed`: Failed cascade workflow triggers
- `human-required`: Items that need human review/action

### Issue Lifecycle Labels (ADR-022)

- `upstream-sync`: Issues related to upstream synchronization
- `cascade-active`: Cascade integration currently in progress
- `cascade-blocked`: Cascade blocked by conflicts or issues
- `validated`: Integration complete, validation successful
- `template-sync`: Issues related to template updates

### Workflow Implementation Pattern

**Before (Problematic)**:

```yaml
# Validate assignee before creating issue
ASSIGNEE="${{ github.actor }}"
if gh api users/"$ASSIGNEE" >/dev/null 2>&1; then
  ASSIGNEE_FLAG="--assignee $ASSIGNEE"
else
  ASSIGNEE_FLAG=""
fi

gh issue create \
  --title "Issue requiring attention" \
  --body "Issue details..." \
  --label "some-label" \
  $ASSIGNEE_FLAG
```

**After (Robust with Lifecycle Tracking)**:

```yaml
# Simple, reliable issue creation with lifecycle tracking
gh issue create \
  --title "📥 Upstream Sync Ready for Review - $(date +%Y-%m-%d)" \
  --body "$NOTIFICATION_BODY" \
  --label "upstream-sync,human-required"

# Dynamic label updates during cascade lifecycle
gh issue edit "$ISSUE_NUMBER" \
  --remove-label "human-required" \
  --add-label "cascade-active"
```

### Team Workflow Integration

**GitHub Issue Filters**:

```bash
# Find all items requiring human attention
label:human-required

# High priority items only
label:human-required label:high-priority

# Conflicts needing resolution
label:human-required label:conflict

# Failed automation items
label:human-required label:sync-failed

# Cascade lifecycle tracking
label:upstream-sync label:human-required     # Needs manual cascade trigger
label:upstream-sync label:cascade-active     # Integration in progress
label:upstream-sync label:cascade-blocked    # Blocked by conflicts
label:upstream-sync label:production-ready   # Ready for production merge
```

**GitHub Project Automation**:

```yaml
# Project board rules
- label:human-required → "Needs Attention" column
- label:high-priority → "Urgent" column  
- label:conflict → "Conflicts" column
```

## Alternatives Considered

### 1. Enhanced User Validation

```yaml
# Complex validation logic
if gh api users/"${{ github.actor }}" >/dev/null 2>&1; then
  ASSIGNEE_FLAG="--assignee ${{ github.actor }}"
elif gh api users/"${{ github.repository_owner }}" >/dev/null 2>&1; then
  ASSIGNEE_FLAG="--assignee ${{ github.repository_owner }}"
else
  ASSIGNEE_FLAG="--assignee $(gh api /repos/:owner/:repo/collaborators --jq '.[0].login')"
fi
```

**Pros**: Maintains assignment approach

**Cons**: Complex, fragile, still fails in edge cases, API rate limiting

**Decision**: Rejected due to complexity and unreliability

### 2. Configuration-Based Assignment

```yaml
# Store usernames in repository variables
--assignee "${{ vars.DEFAULT_ASSIGNEE }}"
```
**Pros**: Configurable per repository

**Cons**: Still requires username validation; manual setup; maintenance overhead

**Decision**: Rejected due to maintenance burden

### 3. External Assignment Service

**Pros**: Could handle complex assignment logic

**Cons**: Additional infrastructure; complexity; single point of failure

**Decision**: Rejected as over-engineering

### 4. Hybrid Approach (Assignment + Labels)

```yaml
# Try assignment, fall back to labels
if [[ -n "${{ vars.DEFAULT_ASSIGNEE }}" ]]; then
  --assignee "${{ vars.DEFAULT_ASSIGNEE }}"
fi
--label "human-required"
```

**Pros**: Best of both worlds

**Cons**: Still susceptible to assignment failures; increased complexity

**Decision**: Rejected in favor of label-only simplicity

## Migration Strategy

### Phase 1: Add Labels (Completed)

- Add `human-required` label to all new issue/PR creation
- Keep existing assignee logic temporarily
- Monitor for assignment failures

### Phase 2: Remove Assignees (Completed)

- Remove all `--assignee` flags from workflows
- Simplify issue/PR creation logic
- Update error handling to remove validation

### Phase 3: Team Adoption

- Update team documentation for label-based workflows
- Create GitHub saved searches for common queries
- Configure project boards with label-based automation

### Phase 4: Enhanced Labeling

- Add priority and category labels as needed
- Implement advanced filtering strategies
- Automate label lifecycle management

## Consequences

### Positive

- **Reliability**: Workflows never fail due to username issues
- **Simplicity**: Cleaner, simpler workflow code
- **Flexibility**: Teams can organize work however they prefer
- **Scalability**: Works across any size team or organization
- **Maintainability**: No hardcoded usernames to maintain
- **Template-Friendly**: Works identically across all repository instances

### Negative

- **No Direct Assignment**: Individual accountability requires discipline
- **Team Process Change**: Teams must adapt to label-based workflows
- **Notification Changes**: No automatic assignment notifications
- **Filter Learning**: Team members need to learn effective label filtering

### Neutral

- **Different Workflow**: Change in process, not necessarily better/worse
- **GitHub Native**: Uses GitHub features rather than external solutions
- **Audit Trail**: Labels provide visibility into issue classification

## Team Workflow Recommendations

### Individual Workflows

```bash
# Daily work queue - check for high priority items
https://github.com/org/repo/issues?q=is:open+label:human-required+label:high-priority

# Weekly triage - review all human-required items  
https://github.com/org/repo/issues?q=is:open+label:human-required

# Conflict resolution focus
https://github.com/org/repo/issues?q=is:open+label:conflict+label:human-required
```

### Project Board Setup

- **Column: "Needs Attention"** → `label:human-required`
- **Column: "High Priority"** → `label:high-priority`
- **Column: "Conflicts"** → `label:conflict`
- **Column: "In Progress"** → Remove `human-required` when started

### Notification Setup

```yaml
# Team notification rules
- Watch repository for issues with specific labels
- Slack/Teams integration based on label filters
- Email notifications for high-priority items
```

## Integration with Existing Systems

### Label Management (ADR-008)

- Leverages centralized label definitions
- New labels added to `.github/labels.json` during initialization
- Consistent across all repository instances

### Workflow Patterns

- Sync workflow: Uses `upstream-sync,human-required` for manual cascade triggering with duplicate prevention
- Cascade workflow: Uses lifecycle labels (`cascade-active`, `cascade-blocked`, `production-ready`)
- Monitor workflow: Uses `human-required` for trigger failures
- Template sync: Uses `template-sync,human-required` for template updates

### External Integrations

- **Project Boards**: Automatic card movement based on labels
- **Slack/Teams**: Filter notifications by label combinations
- **GitHub Apps**: Query issues by label patterns

## Monitoring and Success Metrics

### Key Metrics

- **Issue Resolution Time**: Time to close `human-required` issues
- **Label Distribution**: Frequency of different label combinations
- **Team Engagement**: Number of team members working on labeled issues
- **Escalation Rate**: `human-required` items that become `high-priority`

### Success Indicators

- Zero workflow failures due to assignment issues
- Consistent issue resolution times
- Team adoption of label-based filtering
- Reduced manual workflow maintenance

### Failure Detection

- Issues with `human-required` label open > 7 days
- High accumulation of `high-priority` items
- Team members not engaging with labeled items

## Future Enhancements

### Planned Improvements

1. **Smart Labeling**: Automatic priority assignment based on issue content
2. **SLA Automation**: Automatic escalation when items exceed time thresholds
3. **Load Balancing**: Round-robin assignment simulation via label metadata
4. **Advanced Filtering**: Saved searches for common workflow patterns

### Integration Opportunities

- **GitHub Projects**: Enhanced automation based on label patterns
- **External Tools**: Integration with ticketing systems via labels
- **Analytics**: Dashboards showing team workflow efficiency

## Related Decisions

- [ADR-008: Centralized Label Management Strategy](008-centralized-label-management.md) - Defines how labels are managed
- [ADR-019: Cascade Monitor Pattern](019-cascade-monitor-pattern.md) - Uses human-required labels for trigger failures
- [ADR-022: Issue Lifecycle Tracking Pattern](022-issue-lifecycle-tracking-pattern.md) - Defines lifecycle label usage
- Sync Workflow Updates - Implements label-based task management
- Cascade Workflow Updates - Uses labels for conflict management

## Success Criteria

- 100% workflow reliability (no assignment-related failures)
- Team adopts label-based filtering within 2 weeks
- Average resolution time for `human-required` issues ≤ 48 hours
- Zero maintenance overhead for user assignment management
- Template repository works identically across all instances
- Clear audit trail for all automated task creation

---

[← ADR-019](019-cascade-monitor-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-021 →](021-pull-request-target-trigger-pattern.md)
