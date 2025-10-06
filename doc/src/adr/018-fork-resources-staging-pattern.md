# ADR-018: Fork-Resources Staging Pattern for Specialized Template Deployment

## Status

Accepted

## Context

As the Fork Management Template evolved, we discovered a need for template resources that require specialized deployment handling beyond simple file sync or directory copying. Several scenarios emerged:

1. **Issue Templates**: Templates that should exist in fork repositories but not be overwritten by regular template sync
2. **AI/Copilot Configurations**: Settings that need to be deployed to specific locations (`.vscode/`, `.github/`) with custom handling
3. **Prompt Files**: AI prompts that need to be copied to `.github/prompts/` directory structure
4. **Security Configurations**: Copilot firewall settings that require variable configuration

The existing sync mechanisms (ADR-011, ADR-012) handle two scenarios well:

- **Direct sync**: Files that are copied as-is to the same location
- **Workflow templates**: Files in `template-workflows/` that are copied to `.github/workflows/`

However, these don't address resources that need:

- **Multi-target deployment**: Single source copied to different final locations
- **Conditional processing**: Resources deployed only during initialization or sync updates
- **Cleanup requirements**: Staging directories that shouldn't exist in fork repositories
- **Special handling**: Files requiring custom deployment logic

## Decision

We will establish `.github/fork-resources/` as a **staging area pattern** for template resources requiring specialized deployment handling.

### Architecture

```
Template Repository:
├── .github/
│   ├── fork-resources/              # Staging area (template only)
│   │   ├── ISSUE_TEMPLATE/          # → copied to .github/ISSUE_TEMPLATE/
│   │   ├── copilot-instructions.md  # → copied to .github/copilot-instructions.md
│   │   ├── copilot-firewall-config.json # → copied to .github/ + variables
│   │   ├── triage.prompt.md         # → copied to .github/prompts/
│   │   └── .vscode/                 # → copied to .vscode/
│   └── sync-config.json             # Includes fork-resources in sync rules

Fork Repository (after deployment):
├── .github/
│   ├── ISSUE_TEMPLATE/              # Final location
│   ├── copilot-instructions.md     # Final location
│   ├── prompts/                     # Final location
│   └── (no fork-resources/)        # Staging area removed
├── .vscode/                         # Final location
```

### Deployment Mechanisms

1. **Initialization Deployment** (`init-complete.yml`):
   - Copy fork-resources contents to final locations during repository setup
   - Remove fork-resources directory after copying

2. **Update Deployment** (`sync-template.yml`):
   - Sync fork-resources directory when it changes in template
   - Copy updated resources to final locations
   - Remove fork-resources directory after copying

3. **Sync Configuration** (`sync-config.json`):
   - Include `.github/fork-resources` as a synced directory
   - Enable automatic detection of fork-resources changes

### Pattern Rules

1. **Staging Only**: Fork-resources directory exists only in template repository, never in forks
2. **Specialized Logic**: Each resource type can have custom deployment logic
3. **Cleanup Required**: Deployment workflows must remove fork-resources after processing
4. **Sync Integration**: Changes to fork-resources trigger template sync workflow

## Rationale

### Why Staging Area Pattern?

**Alternative 1: Direct Sync**

- ❌ Issue templates would be overwritten by every sync update
- ❌ No way to handle multi-target deployment (`.vscode/`, `.github/prompts/`)
- ❌ Cannot implement conditional or custom deployment logic

**Alternative 2: Hardcoded Deployment**

- ❌ Not extensible for future template resources
- ❌ Would require workflow changes for each new resource type
- ❌ Difficult to maintain consistency across different resource types

**Alternative 3: Fork-Resources Staging** ✅

- ✅ Provides flexibility for specialized deployment
- ✅ Extensible pattern for future template resources
- ✅ Maintains clean separation between template staging and fork deployment
- ✅ Integrates with existing sync mechanisms

### Benefits

1. **Extensibility**: Easy to add new types of specialized template resources
2. **Consistency**: Standardized pattern for all resources requiring special handling
3. **Maintainability**: Clear separation between staging (template) and deployment (forks)
4. **Integration**: Works seamlessly with existing sync and initialization workflows

## Implementation Details

### Sync Configuration Extension

```json
{
  "sync_rules": {
    "directories": [
      {
        "path": ".github/fork-resources",
        "sync_all": true,
        "description": "Fork-specific templates and configuration that get copied during sync updates"
      }
    ]
  }
}
```

### Deployment Logic Pattern

```bash
# Copy templates to final locations
if [ -d ".github/fork-resources/ISSUE_TEMPLATE" ]; then
  mkdir -p ".github/ISSUE_TEMPLATE"
  cp -r ".github/fork-resources/ISSUE_TEMPLATE/"* ".github/ISSUE_TEMPLATE/"
  git add ".github/ISSUE_TEMPLATE/"
fi

# Remove staging area after deployment
rm -rf ".github/fork-resources"
```

## Consequences

### Positive

- **Flexible Template Deployment**: Enables sophisticated template resource handling
- **Clean Fork Repositories**: No staging artifacts in fork repositories
- **Extensible Pattern**: Easy to add new specialized template resources
- **Maintains Sync Integration**: Leverages existing template sync mechanisms

### Negative

- **Added Complexity**: More complex than direct file sync
- **Deployment Logic Required**: Each resource type needs specific deployment handling
- **Two-Stage Process**: Resources must be maintained in staging area, not final location

### Risks

- **Inconsistent Deployment**: Risk of different deployment logic for similar resources
- **Cleanup Dependency**: Deployment workflows must properly remove staging areas

## Compliance

This ADR extends:

- **ADR-011**: Adds fork-resources to configuration-driven sync rules
- **ADR-012**: Incorporates specialized deployment into template update propagation
- **ADR-017**: Generalizes the MCP integration pattern for all specialized resources

## Examples

### Current Fork-Resources

1. **Issue Templates**: `ISSUE_TEMPLATE/triage.md` → `.github/ISSUE_TEMPLATE/triage.md`
2. **Copilot Config**: `copilot-instructions.md` → `.github/copilot-instructions.md`
3. **MCP Config**: `.vscode/mcp.json` → `.vscode/mcp.json`
4. **AI Prompts**: `triage.prompt.md` → `.github/prompts/triage.prompt.md`
5. **Security Config**: `copilot-firewall-config.json` → `.github/` + repository variables

### Future Extensions

- **GitHub App Settings**: Templates for GitHub App configurations
- **Documentation Templates**: Project-specific documentation that needs custom deployment
- **Development Tools**: Additional development environment configurations

---

*This ADR establishes the architectural foundation for specialized template deployment, enabling the Fork Management Template to handle sophisticated resource distribution while maintaining clean separation between template staging and fork deployment.*

---

[← ADR-017](017-mcp-server-integration-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-019 →](019-cascade-monitor-pattern.md)
