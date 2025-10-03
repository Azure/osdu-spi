# ADR-008: Centralized Label Management Strategy

## Status
Accepted

## Context
The Fork Management Template uses GitHub labels extensively to track workflow states, issue types, and PR statuses across multiple automated workflows. Initially, each workflow created its own labels when first run:

- `sync.yml` created sync-related labels
- `init.yml` created initialization labels
- `dependabot-validation.yml` created dependency labels
- The new `cascade.yml` workflow requires additional state-tracking labels

This distributed approach led to several issues:
1. Labels didn't exist until workflows ran, potentially breaking automation
2. No single source of truth for label definitions
3. Inconsistent label colors and descriptions
4. Difficult to maintain and document label usage
5. New workflows couldn't rely on labels existing

## Decision
We will implement a centralized label management strategy where:

1. All system labels are defined in `.github/labels.json`
2. The initialization workflow creates all labels during repository setup
3. Workflows assume labels exist and do not create them
4. Label documentation is maintained in `doc/label-strategy.md`

## Consequences

### Positive
- **Reliability**: All labels exist from repository initialization
- **Consistency**: Single source of truth for label definitions
- **Maintainability**: Easy to add, update, or remove labels
- **Documentation**: Clear reference for label usage
- **Automation**: Workflows can depend on label existence
- **Visibility**: Complete label set visible from day one

### Negative
- **Initial Setup**: Slightly longer initialization process
- **Migration**: Existing repositories need manual label sync
- **Coupling**: Workflows depend on initialization running first

### Neutral
- **Versioning**: Label changes tracked in git history
- **Customization**: Users can modify labels.json for their needs

## Implementation

### Label Configuration File
```json
{
  "labels": [
    {
      "name": "cascade-active",
      "description": "Currently processing through cascade pipeline",
      "color": "0e8a16"
    }
    // ... more labels
  ]
}
```

### Initialization Workflow Update
```yaml
- name: Create all system labels
  run: |
    labels=$(cat .github/labels.json | jq -r '.labels[] | @base64')
    for label in $labels; do
      # Create each label from configuration
    done
```

### Workflow Usage Pattern
```yaml
# Workflows now assume labels exist
gh pr create --label "cascade-active,upstream-sync"
```

## Related
- [ADR-002: GitHub Actions Workflow Automation](002-github-actions-automation.md)
- [ADR-007: Initialization Workflow Bootstrap Process](007-initialization-workflow-bootstrap.md)
- [Label Management Strategy](../label-strategy.md)
- [Cascade Workflow Specification](../cascade-workflow.md)
---

[← ADR-007](007-initialization-workflow-bootstrap.md) | :material-arrow-up: [Catalog](index.md) | [ADR-009 →](009-asymmetric-cascade-review-strategy.md)
