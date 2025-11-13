# Label Management Strategy

This document describes the label management approach for the Fork Management Template repository.

## Overview

All system labels are defined in a centralized configuration file (`.github/labels.json`) and created during repository initialization. This ensures consistent label availability across all workflows.

## Label Flow

### Issue Tracking Flow
Issues follow this label progression:
```
upstream-sync → cascade-active → validated
```

### Production PR Labels
Production PRs use these labels:
```
upstream-sync + human-required (for upstream changes)
template-sync (for template updates)
```

### Duplicate Prevention
Both upstream sync and template sync workflows use labels to prevent duplicate PRs:
- `upstream-sync` - Identifies upstream synchronization PRs
- `template-sync` - Identifies template update PRs

Only one PR with each label can be open at a time. When changes are detected, the workflow updates the existing PR instead of creating a new one.

## Label Categories

### Workflow State Labels
- `cascade-active` - Currently processing through cascade pipeline
- `cascade-blocked` - Waiting on conflict resolution
- `cascade-failed` - Integration failed, automatic recovery system engaged
- `cascade-escalated` - SLA exceeded, needs attention
- `validated` - Integration validation completed successfully
- `validation-failed` - Integration validation (build/test) failed

### Issue Type Labels
- `sync-failed` - Sync workflow failures
- `sync-update` - Tracks upstream sync updates
- `conflict` - Has merge conflicts
- `needs-resolution` - Requires manual intervention
- `build-failed` - Build or test failures

### Priority Labels
- `high-priority` - High priority items
- `escalation` - Escalated issues
- `emergency` - Emergency issues requiring immediate action

### Process Labels
- `upstream-sync` - Related to upstream synchronization
- `template-sync` - Related to template repository synchronization
- `human-required` - Requires human review/action
- `release-tracking` - Tracks release activities
- `rollback` - Related to rollback operations

### Other Labels
- `initialization` - Repository initialization issues
- `dependencies` - Dependency updates and issues

## Failure Recovery Pattern

The label system enables an automated failure recovery workflow:

### Normal Flow
```
upstream-sync → cascade-active → validated
```

### Failure Flow with Recovery
```
upstream-sync → cascade-active → cascade-failed + human-required
                     ↑                      ↓
                cascade-active ← human resolves (removes human-required)
                     ↓
                validated (success) OR cascade-failed (retry cycle)
```

### Recovery Process

1. **Failure Detection**: Cascade fails → tracking issue gets `cascade-failed + human-required`
2. **Technical Issue Created**: Separate issue with `high-priority + human-required` for technical details
3. **Human Investigation**: Developer reviews failure issue and implements fixes
4. **Signal Resolution**: Human removes `human-required` label from tracking issue
5. **Automatic Retry**: Monitor detects label removal and automatically retries cascade
6. **Success or New Failure**: Either succeeds (`validated`) or fails again (new cycle)

### Key Benefits
- **Self-Healing**: System automatically retries after human intervention
- **Clear Handoffs**: Labels signal automation ↔ human transitions
- **Audit Trail**: Complete failure/recovery history in tracking issues
- **Predictable Process**: Developers know exactly how to signal resolution

## Label Colors

Colors follow GitHub's conventions:
- 🟢 Green (`0e8a16`) - Success/ready states
- 🔴 Red (`d73a4a`, `b60205`) - Errors/urgent issues
- 🟡 Yellow (`fbca04`) - Warning/needs attention
- 🔵 Blue (`0366d6`, `0075ca`) - Informational
- 🟣 Purple (`5319e7`) - Process/tracking

## Adding New Labels

To add new labels:

1. Edit `.github/labels.json`
2. Add the new label with name, description, and color
3. Labels will be created on next repository initialization

Example:
```json
{
  "name": "new-label",
  "description": "Description of the new label",
  "color": "0366d6"
}
```

## Workflow Usage

Workflows should:
1. Assume labels exist (created during init)
2. Use labels consistently as defined
3. Not create labels dynamically
4. Reference this document for label names

## Label Lifecycle

1. **Creation**: All labels created during repository initialization
2. **Usage**: Applied by workflows and users
3. **Maintenance**: Updated via `.github/labels.json` and re-initialization
4. **Deletion**: Manual cleanup if labels become obsolete

## Best Practices

1. Use descriptive label names
2. Keep descriptions concise but clear
3. Use consistent color coding
4. Document new labels in this file
5. Avoid creating duplicate or similar labels