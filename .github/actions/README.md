# GitHub Actions Components

This directory contains reusable GitHub Actions components used across our workflows. We follow GitHub's recommended patterns for organizing different types of actions.

## Directory Structure

```
.github/
├── actions/              # Composite and local actions
│   ├── pr-status/       # PR Status Comment action
│   │   ├── action.yml   # Action definition (required name)
│   │   └── README.md    # Action-specific documentation
│   └── README.md        # This file
└── workflows/           # Reusable and standard workflows
    ├── build.yml        # Main build workflow
    ├── validate.yml     # Validation workflow
    └── java-build.yml   # Reusable Java build workflow
```

## Types of Components

### Composite Actions
Located in subdirectories of `.github/actions/`, each with an `action.yml` file:
- Must be in a directory with an `action.yml` file (GitHub requirement)
- Can include additional resources (scripts, docs, etc.)
- Suitable for publishing as standalone actions
- Example: `pr-status/` for standardized PR comments

### Reusable Workflows
Located directly in `.github/workflows/` with `.yml` extension:
- Can be called from other workflows
- Define inputs and outputs
- Example: `java-build.yml` for standardized Java builds

## Current Components

### PR Status Action (`pr-status/`)
- **Purpose**: Standardize PR status comments across workflows
- **Type**: Composite action
- **Usage**: Called by workflows to post consistent status updates

### Java Build Workflow (`java-build.yml`)
- **Purpose**: Standardize Java project detection and building
- **Type**: Reusable workflow
- **Usage**: Called by other workflows that need Java build capabilities

## Conventions

1. **Composite Actions**:
   - Use folder with `action.yml`
   - Include action-specific README
   - Follow GitHub's composite action structure

2. **Reusable Workflows**:
   - Direct `.yml` files in workflows directory
   - Clear input/output definitions
   - Focused on specific reusable tasks

## Adding New Components

### New Composite Action
1. Create a new directory: `.github/actions/action-name/`
2. Add `action.yml` with action definition
3. Include README.md for documentation
4. Add any additional resources needed

### New Reusable Workflow
1. Add `.yml` file to `.github/workflows/`
2. Define workflow_call trigger
3. Document inputs and outputs
4. Follow existing patterns for consistency

## Best Practices

1. **Documentation**: Each component should be well-documented
2. **Single Responsibility**: Each component should do one thing well
3. **Reusability**: Design for reuse across workflows
4. **Versioning**: Consider future compatibility when making changes
5. **Testing**: Test components thoroughly before reuse 