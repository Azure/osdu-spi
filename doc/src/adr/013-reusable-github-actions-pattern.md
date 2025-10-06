# ADR-013: Reusable GitHub Actions Pattern for PR Creation

## Status

**Accepted** - 2025-10-01

## Context

During implementation of template synchronization workflows (ADR-011, ADR-012), we identified significant code duplication in PR creation logic across multiple workflows. Each workflow that created pull requests had to implement:

**Duplicated PR Creation Logic:**

- **LLM Detection**: Check for available Azure Foundry API keys
- **aipr Integration**: Generate AI-enhanced PR descriptions when possible
- **Fallback Handling**: Use provided description when AI generation fails
- **Diff Size Management**: Skip AI generation for large diffs to avoid token limits
- **PR Creation**: Create GitHub pull request with proper parameters
- **Output Management**: Return PR URL and number for further processing

**Workflows with Similar PR Creation Needs:**

- **`sync.yml`**: Creates upstream synchronization PRs with vulnerability analysis
- **`template-sync.yml`**: Creates template update PRs with change summaries  
- **Future workflows**: Additional automation requiring AI-enhanced PR descriptions

**Problems with Code Duplication:**

- **Maintenance Burden**: Changes to PR creation logic required updates in multiple places
- **Inconsistency Risk**: Implementations could drift apart over time
- **Testing Complexity**: Each workflow implementation needed separate testing
- **Feature Lag**: Improvements to one workflow didn't benefit others

## Decision

Implement **Reusable GitHub Actions Pattern** for common PR creation functionality:

### 1. **Custom Composite Action**: `.github/actions/create-enhanced-pr/action.yml`

- **Centralized Logic**: Single implementation of PR creation with AI enhancement
- **Configurable Parameters**: Flexible inputs for different use cases
- **Consistent Interface**: Standardized inputs and outputs across workflows
- **AI Integration**: Built-in aipr integration with Azure Foundry

### 2. **Standardized AI Enhancement Pipeline**

```yaml
# Automatic LLM detection and configuration
- Azure Foundry (primary)
- Template fallback when Azure unavailable

# Intelligent diff size management
- Skip AI generation for diffs >20,000 lines
- Configurable diff size limits
- Graceful degradation to fallback content
```

### 3. **Flexible Configuration Interface**

```yaml
uses: ./.github/actions/create-enhanced-pr
with:
  github-token: ${{ secrets.GH_TOKEN }}
  base-branch: main
  head-branch: feature-branch
  pr-title: "feat: add new feature"
  fallback-description: "Basic PR description"
  use-vulns-flag: 'true'  # Enable security analysis
  additional-description: "Extra content to append"
```

### 4. **Comprehensive Output Interface**

```yaml
outputs:
  pr-url: "https://github.com/owner/repo/pull/123"
  pr-number: "123"
  used-aipr: "true"  # Indicates if AI enhancement was used
```

## Rationale

### Benefits of Reusable Actions Pattern

1. **DRY Principle**: Single implementation eliminates code duplication
2. **Consistent Behavior**: All workflows use identical PR creation logic
3. **Centralized Improvements**: Enhancements benefit all consuming workflows
4. **Easier Testing**: Single action to test instead of multiple workflow implementations
5. **Reduced Maintenance**: Changes only need to be made in one place
6. **Standardized Interface**: Common parameters and behavior across workflows

### AI Enhancement Centralization

1. **Consistent AI Integration**: Same aipr configuration across all workflows
2. **Azure Foundry Primary**: Standardized on Azure Foundry with template fallback
3. **Configuration Management**: Centralized handling of API keys and parameters
4. **Error Handling**: Unified approach to AI generation failures
5. **Performance Optimization**: Shared diff size management and token limit handling

### Workflow Simplification

1. **Reduced Complexity**: Workflows focus on their core logic, not PR creation details
2. **Clear Separation**: PR creation concerns separated from business logic
3. **Easier Debugging**: Issues with PR creation isolated to single action
4. **Improved Readability**: Workflows more focused and easier to understand

## Implementation Details

### Action Interface Design

#### Required Inputs

```yaml
inputs:
  github-token:        # GitHub token for API access
  base-branch:         # Target branch for PR
  head-branch:         # Source branch for PR
  pr-title:           # Title for the PR
  fallback-description: # Description to use if AI generation fails
```

#### Optional Inputs

```yaml
inputs:
  azure-api-key:       # Azure Foundry API key
  azure-api-base:      # Azure Foundry endpoint
  azure-api-version:   # Azure Foundry API version
  max-diff-lines:      # Maximum diff size for AI processing (default: 20000)
  use-vulns-flag:      # Enable vulnerability analysis (default: true)
  target-branch-for-aipr: # Branch for aipr analysis (defaults to base-branch)
  additional-description: # Extra content to append to description
```

#### Comprehensive Outputs

```yaml
outputs:
  pr-url:              # Complete URL to created PR
  pr-number:           # PR number for further processing
  used-aipr:           # Boolean indicating if AI enhancement was used
```

### LLM Provider Detection

#### Provider Detection Logic

```bash
# Provider detection
1. Azure Foundry (if AZURE_API_KEY and AZURE_API_BASE provided)
2. Template fallback when Azure unavailable
```

#### Model Configuration

```yaml
# Model configuration
Azure: "azure"  # aipr model identifier for Azure Foundry
```

### Action Implementation Pattern

#### Composite Action Structure

```yaml
runs:
  using: 'composite'
  steps:
    - name: Detect available LLM
    - name: Check diff size and generate description  
    - name: Create PR
```

#### Error Handling Strategy

```bash
# Graceful degradation approach
1. Try AI generation with detected LLM
2. If AI generation fails, log warning and continue
3. Use fallback description provided by caller
4. Create PR successfully regardless of AI generation outcome
```

### Usage Patterns in Workflows

#### Sync Workflow Limitation

**Important**: The reusable action pattern **cannot be used in the sync workflow** (`sync.yml`) because:
- Sync workflow runs from `fork_upstream` branch (contains only upstream code)
- `create-enhanced-pr` action only exists on `main` branch (template infrastructure)
- GitHub Actions cannot access actions from different branches

**Solution**: Embed PR creation logic directly in sync workflow instead of using reusable action.

```yaml
# ❌ This DOES NOT work in sync.yml (action not available on fork_upstream branch)
- name: Create enhanced sync PR
  uses: ./.github/actions/create-enhanced-pr  # Action doesn't exist on fork_upstream
  
# ✅ This works in sync.yml (embedded logic)
- name: Create enhanced sync PR
  env:
    GITHUB_TOKEN: ${{ secrets.GH_TOKEN }}
  run: |
    # Detect available LLM provider and generate PR description
    # [embedded logic as implemented in sync.yml]
```

#### Template Sync Workflow Usage

```yaml
- name: Create enhanced template sync PR
  uses: ./.github/actions/create-enhanced-pr
  with:
    base-branch: main
    head-branch: ${{ env.SYNC_BRANCH }}
    pr-title: "🔄 Sync template updates $(date +%Y-%m-%d)"
    fallback-description: ${{ env.FALLBACK_DESCRIPTION }}
    use-vulns-flag: 'false'  # Disable security analysis for template PRs
    target-branch-for-aipr: main
```

## Alternatives Considered

### 1. **Shared Shell Functions**

- **Pros**: Lightweight, easy to understand
- **Cons**: Limited parameter handling, no type safety, harder to test
- **Decision**: Rejected due to limited flexibility and maintainability

### 2. **External Action from Marketplace**

- **Pros**: Maintained by community, potentially more features
- **Cons**: External dependency, less control, may not fit our specific needs
- **Decision**: Rejected due to specific requirements for aipr integration

### 3. **Copy-Paste with Documentation**

- **Pros**: Simple, no abstraction complexity
- **Cons**: Maintenance burden, inconsistency risk, violates DRY principle
- **Decision**: Rejected due to long-term maintenance concerns

### 4. **Workflow Templates**

- **Pros**: GitHub native, reusable across repositories
- **Cons**: Can't be used within same repository, less flexible
- **Decision**: Rejected due to within-repository usage requirements

### 5. **NPM Package for PR Creation**
- **Pros**: Version management, external reusability
- **Cons**: External dependency, requires Node.js setup in workflows
- **Decision**: Rejected due to complexity and external dependencies

## Consequences

### Positive

- **Eliminated Code Duplication**: 80+ lines of PR creation logic now in single action
- **Consistent AI Enhancement**: All PRs use identical AI generation logic
- **Easier Maintenance**: Single place to update PR creation behavior
- **Improved Testing**: Can test PR creation logic independently
- **Better Error Handling**: Centralized error handling with graceful degradation
- **Enhanced Flexibility**: Easy to add new parameters or features
- **Workflow Simplification**: Workflows focus on business logic, not PR creation

### Negative

- **Additional Abstraction**: Extra layer between workflows and GitHub API
- **Learning Curve**: Team needs to understand action interface
- **Local Development**: Harder to test workflows locally
- **Action Complexity**: Composite action has multiple steps and conditional logic
- **Branch Dependency Limitation**: Actions cannot be used by workflows running from different branches

### Mitigation Strategies

- **Comprehensive Documentation**: Clear examples and parameter documentation
- **Integration Testing**: Test action behavior in actual workflow contexts
- **Backward Compatibility**: Maintain stable interface as action evolves
- **Error Logging**: Clear logging to help debug action issues
- **Branch-Aware Design**: Document which workflows can/cannot use the action pattern

### Branch Dependency Limitation

**Key Discovery**: GitHub Actions can only reference actions that exist on the same branch where the workflow is running.

#### When to Use Reusable Action

✅ **Use action for workflows that run from `main` branch:**
- `template-sync.yml` - runs from main, action available
- `build.yml` - runs from main, action available  
- `validate.yml` - runs from main, action available
- Future workflows on main branch

#### When to Embed Logic Directly

❌ **Embed logic for workflows that run from other branches:**
- `sync.yml` - runs from `fork_upstream` branch, action not available
- Any workflows triggered to run on feature branches
- Workflows that checkout different branches before running

#### Implementation Strategy

- **Primary Pattern**: Use reusable action where possible (main branch workflows)
- **Fallback Pattern**: Embed logic directly when branch limitations prevent action usage
- **Consistency**: Maintain same AI enhancement logic in both patterns

## Success Criteria

- ⚠️ **Code Duplication Reduced**: Most PR creation logic centralized in reusable action (limited by branch dependencies)
- ✅ **Consistent Behavior**: All PRs created with identical enhancement logic (action + embedded patterns)
- ✅ **Easy Integration**: New main-branch workflows can easily adopt enhanced PR creation
- ✅ **Maintained Functionality**: All existing PR creation features preserved
- ⚠️ **Improved Maintainability**: Changes to PR creation logic require updates in action + sync workflow
- ✅ **Enhanced Flexibility**: Easy to customize PR creation for specific use cases
- ✅ **Branch-Aware Design**: Clear guidance on when to use action vs embedded logic

## Future Evolution

### Potential Enhancements

1. **Additional LLM Providers**: Support for new AI services as they become available
2. **Custom Templates**: Support for PR description templates based on workflow type
3. **Advanced Validation**: Pre-flight checks for PR creation requirements
4. **Metrics Collection**: Built-in tracking of AI generation success rates
5. **Caching**: Cache AI-generated descriptions for similar changes

### Reusability Expansion

- **Cross-Repository Usage**: Package action for use in other template repositories
- **Marketplace Publication**: Make action available to broader GitHub community
- **Plugin Architecture**: Support for custom PR enhancement plugins
- **Template Library**: Built-in support for common PR description patterns

## Testing Strategy

### Unit Testing

- **Mock GitHub API**: Test PR creation logic without actual API calls
- **LLM Provider Testing**: Test provider detection and fallback logic
- **Error Handling**: Test graceful degradation scenarios

### Integration Testing

- **Workflow Testing**: Test action integration in actual workflow contexts
- **API Key Scenarios**: Test behavior with different combinations of API keys
- **Large Diff Testing**: Test diff size management and fallback behavior

### Performance Testing

- **AI Generation Time**: Monitor time for AI-enhanced description generation
- **Fallback Performance**: Ensure fast fallback when AI generation fails
- **Resource Usage**: Monitor action resource consumption

## Related ADRs

- **ADR-011**: Configuration-Driven Template Synchronization (benefits from consistent PR creation)
- **ADR-012**: Template Update Propagation Strategy (uses this action for template sync PRs)
- **ADR-014**: AI-Enhanced Development Workflow Integration (implements AI capabilities used by this action)
---

[← ADR-012](012-template-update-propagation-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-014 →](014-ai-enhanced-development-workflow.md)
