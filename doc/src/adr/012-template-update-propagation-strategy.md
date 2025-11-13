# ADR-012: Template Update Propagation Strategy

## Status
**Accepted** - 2025-10-01  

## Context

Following the implementation of configuration-driven template synchronization (ADR-011), we needed a strategy for actually propagating template updates to existing forked repositories. The sync configuration defined *what* should be synchronized, but we needed to define *how* and *when* template updates reach forked repositories.

**Requirements for Template Update System:**

- **Automatic Updates**: Template improvements should reach forks without manual intervention
- **Selective Syncing**: Only template infrastructure should be updated, not project-specific content
- **Change Visibility**: Teams should see exactly what template changes are being applied
- **Review Process**: Updates should go through pull request review before being applied
- **Conflict Handling**: System should detect and handle potential conflicts gracefully
- **Version Tracking**: Track which template version each fork is synchronized to

**Challenges to Address:**

- **Bootstrap Problem**: How do forked repositories get the template sync capability initially?
- **Change Detection**: How to identify which template changes are relevant to forks?
- **Update Scheduling**: When should template updates be checked and applied?
- **Conflict Resolution**: How to handle cases where template changes conflict with local modifications?

## Decision

Implement **Template Update Propagation** through a dedicated `template-sync.yml` workflow that:

### 1. **Template Sync Workflow**: `template-sync.yml`

- **Triggers**: Daily schedule (8 AM UTC) + manual dispatch
- **Function**: Detects template changes and creates update PRs
- **Scope**: Only files defined in sync configuration (ADR-011)
- **Output**: Pull requests with AI-enhanced descriptions of changes

### 2. **Two-Repository Architecture**

- **Template Repository**: Source of truth for infrastructure improvements
- **Fork Repositories**: Receive template updates via template-sync workflow
- **Separation**: Template management stays in template, project automation goes to forks
- **Human-Centric Flow**: Template updates include instructions for manual cascade triggering

### 3. **Change Detection and Propagation**

```yaml
# Track last synced template commit
.github/.template-sync-commit

# Compare template changes since last sync
git diff $LAST_SYNC_COMMIT..$TEMPLATE_COMMIT template/main -- [sync_paths]

# Create PR for template updates
PR: "🔄 Sync template updates YYYY-MM-DD"
```

### 4. **Intelligent Sync Scope**

- **Configuration-Driven**: Uses `.github/sync-config.json` to determine what to sync
- **Selective Updates**: Only syncs files defined in sync rules
- **Change-Based**: Only creates PRs when relevant template changes exist
- **Self-Updating**: The sync configuration itself can be updated via template sync
- **Manual Integration Instructions**: Sync creates issues with explicit cascade trigger guidance

## Rationale

### Solving the Template Drift Problem

1. **Automatic Propagation**: No manual work required to get template improvements
2. **Consistent Infrastructure**: All forks maintain current template infrastructure
3. **Security Updates**: Security improvements in template automatically reach forks
4. **Feature Adoption**: New workflow features automatically available to teams

### Pull Request-Based Update Process

1. **Review Opportunity**: Teams can review template changes before accepting
2. **Change Visibility**: Clear documentation of what's being updated and why
3. **Conflict Detection**: PR process reveals any conflicts with local modifications
4. **Rollback Capability**: Changes can be reverted if they cause issues

### Weekly Schedule Benefits

1. **Predictable Updates**: Teams know when to expect template update PRs
2. **Batched Changes**: Multiple template improvements delivered together
3. **Non-Disruptive**: Updates arrive at consistent, predictable times
4. **Manual Override**: Can run template sync manually when needed

## Implementation Details

### Template Sync Workflow Structure

#### Trigger Configuration
```yaml
on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8 AM UTC
  workflow_dispatch:      # Manual trigger available
```

#### Change Detection Process
```yaml
- name: Check for template updates
  run: |
    # Get the latest commit from template main branch
    TEMPLATE_COMMIT=$(git rev-parse template/main)
    
    # Check last synced commit
    LAST_SYNC_COMMIT=$(cat .github/.template-sync-commit)
    
    # Get sync configuration from template
    git show template/main:.github/sync-config.json > temp-sync-config.json
    
    # Build list of paths to check for changes
    SYNC_PATHS=$(jq -r '.sync_rules.directories[] | .path' temp-sync-config.json)
    
    # Check for changes in configured paths
    CHANGES=$(git diff --name-only $LAST_SYNC_COMMIT..$TEMPLATE_COMMIT template/main -- $SYNC_PATHS)
```

#### Selective File Synchronization
```yaml
- name: Sync template files
  run: |
    # Sync directories
    DIRECTORIES=$(jq -r '.sync_rules.directories[] | .path' temp-sync-config.json)
    for dir in $DIRECTORIES; do
      if [[ changes detected in $dir ]]; then
        rm -rf "$dir"
        git archive template/main "$dir" | tar -x
        git add "$dir"
      fi
    done
    
    # Sync individual files
    FILES=$(jq -r '.sync_rules.files[] | .path' temp-sync-config.json)
    for file in $FILES; do
      if [[ changes detected in $file ]]; then
        git show template/main:"$file" > "$file"
        git add "$file"
      fi
    done
    
    # Sync essential workflows
    WORKFLOWS=$(jq -r '.sync_rules.workflows.essential[] | .path' temp-sync-config.json)
    for workflow in $WORKFLOWS; do
      if [[ changes detected in $workflow ]]; then
        git show template/main:"$workflow" > "$workflow"
        git add "$workflow"
      fi
    done
```

#### Issue Creation with Manual Instructions
```yaml
# Template updates now create tracking issues similar to upstream sync
- name: Create template update notification
  run: |
    NOTIFICATION_BODY="## 📋 Template Updates Ready for Review
    
    New template infrastructure updates are available for integration.
    
    **Update Details:**
    - **PR:** $PR_URL
    - **Template Version:** $TEMPLATE_COMMIT
    - **Changed Files:** $(git diff --name-only main...$SYNC_BRANCH | wc -l) files
    - **Changes:** Template infrastructure improvements
    
    **Next Steps:**
    1. 🔍 **Review the template update PR** for infrastructure changes
    2. ✅ **Merge the PR** when satisfied with the updates
    3. 🚀 **Manually trigger 'Cascade Integration' workflow** if changes affect workflows
    4. 📊 **Monitor integration progress** in Actions tab
    
    **Timeline:**
    - Template sync detected: $(date -u +%Y-%m-%dT%H:%M:%SZ)
    - Action required: Human review, merge, and potential cascade trigger"
    
    gh issue create \
      --title "📋 Template Updates Ready for Review - $(date +%Y-%m-%d)" \
      --body "$NOTIFICATION_BODY" \
      --label "template-sync,human-required"
```

### Bootstrap Strategy

#### Initial Template Sync Capability

- **Template sync workflow included in essential workflows** (ADR-011)
- **Copied during repository initialization** via `init-complete.yml`
- **Self-updating capability** - template sync can update itself

#### Auto-Bootstrap for Existing Repositories

**Problem**: Repositories created before template sync implementation lack tracking files.

**Solution**: Auto-bootstrap detection and initialization:

```bash
# Detect missing or empty tracking file
if [ -f "$LAST_SYNC_FILE" ] && [ -s "$LAST_SYNC_FILE" ]; then
  LAST_SYNC_COMMIT=$(cat "$LAST_SYNC_FILE")
else
  # Auto-bootstrap: find earliest .github commit as baseline
  BASELINE_COMMIT=$(git log template/main --reverse --oneline -- .github/ | head -1 | cut -d' ' -f1)
  
  # Create tracking file immediately
  echo "$BASELINE_COMMIT" > .github/.template-sync-commit
  LAST_SYNC_COMMIT="$BASELINE_COMMIT"
fi
```

**Benefits**:

- **Seamless Migration**: Existing repositories can adopt template sync without manual intervention
- **Smart Baseline**: Uses earliest template infrastructure commit, not arbitrary date
- **Immediate Tracking**: Creates tracking file during detection to prevent future bootstrap issues
- **Comprehensive Updates**: First sync includes all template improvements since baseline

#### Template Repository Configuration
```json
{
  "sync_rules": {
    "workflows": {
      "essential": [
        ".github/workflows/template-sync.yml"  // Included in essential workflows
      ]
    }
  }
}
```

### Version Tracking System

#### Commit Tracking File

```bash
# .github/.template-sync-commit contains SHA of last synced template commit
echo "$TEMPLATE_COMMIT" > .github/.template-sync-commit
git add .github/.template-sync-commit
```

#### Template Version References

- **Each sync PR documents template commit range**
- **Git history shows template update progression**
- **Easy to identify which template features are available**

### Duplicate Prevention Pattern

Following the same architectural pattern as upstream sync (ADR-024), template-sync implements duplicate prevention to avoid creating multiple open PRs for template updates (detailed in ADR-031):

#### Problem Addressed
Without duplicate prevention, the daily template-sync schedule creates a new PR every day when changes exist, even if a previous PR is still open. This results in:
- Multiple open template-sync PRs simultaneously (6+ PRs in production)
- Repository clutter and notification fatigue
- Confusion about which PR contains the latest changes

#### Solution Implementation
- **PR Detection**: Checks for existing open PRs with `template-sync` label targeting `main` branch
- **Branch Reuse**: Updates existing sync branches instead of creating new ones
- **Force Push Strategy**: Force-pushes updates to existing branches when template advances
- **PR Updates**: Updates PR title to show "(Updated YYYY-MM-DD)", regenerates description, adds update comments
- **Single Active PR**: Only one template-sync PR open at any time

#### Decision Matrix
```
| Existing PR | Template Changed | Action                    |
|-------------|------------------|---------------------------|
| No          | Yes              | Create new PR             |
| Yes         | No               | No action needed          |
| Yes         | Yes              | Update existing branch/PR |
| No          | No               | No action needed          |
```

#### Benefits
- **Eliminates duplicate PRs** - Core problem solved
- **Consistent pattern** - Same approach as upstream sync
- **Clean repository** - No accumulation of stale PRs
- **Reduced noise** - Single PR per template update cycle
- **Clear progression** - Updated PRs show complete history

See [ADR-031: Template Sync Duplicate Prevention Pattern](031-template-sync-duplicate-prevention.md) for complete implementation details.

## Alternatives Considered

### 1. **Push-Based Updates from Template**

- **Pros**: Immediate propagation, centralized control
- **Cons**: Requires write access to all forks, security concerns
- **Decision**: Rejected due to security and access complexity

### 2. **Manual Update Process**

- **Pros**: Full control, simple implementation
- **Cons**: Relies on teams remembering to update, inconsistent adoption
- **Decision**: Rejected due to poor adoption rates

### 3. **Webhook-Based Real-Time Updates**

- **Pros**: Immediate updates when template changes
- **Cons**: Complex setup, potential for update spam
- **Decision**: Rejected in favor of predictable scheduled updates

### 4. **Git Submodule for Template Infrastructure**

- **Pros**: Native Git functionality
- **Cons**: Complex for teams, doesn't handle selective syncing
- **Decision**: Rejected due to user experience complexity

### 5. **Daily Template Sync Schedule**

- **Pros**: More frequent updates
- **Cons**: Potential for too many PRs, disruption to team workflow
- **Decision**: Rejected in favor of weekly schedule

## Consequences

### Positive

- **Automatic Template Benefits**: Teams automatically get template improvements
- **Reduced Maintenance**: Minimal manual work required to stay current with template
- **Consistent Infrastructure**: All repositories maintain current best practices
- **Security Currency**: Security improvements automatically propagate
- **Feature Adoption**: New capabilities automatically available to teams
- **Change Visibility**: Clear PRs and issues showing exactly what's being updated
- **Review Process**: Teams can review and test template changes before merging
- **Human Control**: Explicit guidance on when workflow changes need cascade integration

### Negative

- **Additional PRs and Issues**: Daily template update PRs and tracking issues require team attention
- **Manual Integration Steps**: Workflow changes may require manual cascade triggering
- **Potential Conflicts**: Template changes might conflict with local modifications
- **Update Lag**: Template improvements take up to a day to reach all forks
- **Dependency on Template**: Forks depend on template repository being available
- **Learning Curve**: Teams need to understand when template changes require cascade integration

### Mitigation Strategies

- **AI-Enhanced Descriptions**: Clear PR descriptions explain what's changing and why
- **Explicit Instructions**: Issues provide clear guidance on when cascade integration is needed
- **Selective Syncing**: Only essential infrastructure updated, not project code
- **Manual Override**: Can run template sync immediately when critical updates needed
- **Conflict Detection**: PR process reveals conflicts before they're merged
- **Documentation**: Clear guidance on handling template update PRs and cascade integration

## Success Criteria

- ✅ **Template improvements reach all forked repositories within one week**
- ✅ **Teams receive clear, actionable PR descriptions for template updates**
- ✅ **No manual intervention required for routine template updates**
- ✅ **Template update PRs have high merge rate (>90%)**
- ✅ **Security updates propagate to forks within 24 hours (manual trigger)**
- ✅ **Teams can easily review and understand template changes**
- ✅ **Template drift problem is eliminated across all repositories**
- ✅ **Existing repositories auto-bootstrap template sync without manual setup**
- ✅ **Auto-bootstrap creates comprehensive update PRs covering all missing template features**

## Monitoring and Analytics

### Template Update Metrics

- **Sync Success Rate**: Percentage of successful template sync PRs
- **Update Lag Time**: Time from template change to fork merge
- **Conflict Rate**: Frequency of template update conflicts
- **Adoption Rate**: Percentage of template update PRs that get merged

### Health Indicators

- **Template Sync Workflow Failures**: Alert on sync workflow failures
- **Large Sync Gaps**: Alert when forks fall behind template by significant margin
- **Conflict Trends**: Monitor increasing conflict rates as indicator of template design issues

## Future Evolution

### Potential Enhancements

1. **Smart Scheduling**: Adjust sync frequency based on template change rate
2. **Priority Updates**: Immediate sync for security-critical template changes
3. **Conflict Resolution**: Automated conflict resolution for common scenarios
4. **Selective Sync**: Per-repository customization of which template features to sync
5. **Rollback Capability**: Automated rollback of problematic template updates

### Integration Opportunities

- **Security Scanning**: Integration with security tools to prioritize security-related template updates
- **Testing Integration**: Automated testing of template updates before creating PRs
- **Analytics Dashboard**: Visibility into template update health across organization

## Related ADRs

- **ADR-011**: Configuration-Driven Template Synchronization (provides the foundation for this strategy)
- **ADR-013**: Reusable GitHub Actions Pattern (enables consistent PR creation)
- **ADR-031**: Template Sync Duplicate Prevention Pattern (prevents duplicate template-sync PRs)
- **ADR-024**: Sync Workflow Duplicate Prevention Architecture (upstream sync pattern that inspired ADR-031)
- **ADR-003**: Template Repository Pattern (original template architecture, extended by this decision)

---

[← ADR-011](011-configuration-driven-template-sync.md) | :material-arrow-up: [Catalog](index.md) | [ADR-013 →](013-reusable-github-actions-pattern.md)
