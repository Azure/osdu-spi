# ADR-010: YAML-Safe Shell Scripting in GitHub Actions

## Status
**Accepted** - 2025-10-01

## Context

GitHub Actions workflows use YAML syntax to define shell scripts, which creates potential conflicts when shell scripts contain YAML-meaningful characters. During implementation of the initialization completion message system, we encountered YAML parsing errors caused by:

**Problematic Patterns:**
- **Heredocs with colons**: `Here's what was set up:` interpreted as YAML mapping
- **Multiline string assignments**: Complex heredoc syntax within YAML run blocks
- **Special characters**: Backticks, quotes, and colons within shell variable assignments
- **Mixed contexts**: Shell script syntax nested within YAML string contexts

**Example of Problematic Code:**
```yaml
run: |
  MANUAL_STEPS="## Manual Configuration Required

  Since no GH_TOKEN was provided, please complete these steps:

  ### 1. Branch Protection  
  - Go to Settings → Branches
  - For each branch (`main`, `fork_upstream`, `fork_integration`):
    - Require pull request reviews before merging
  "
```

**YAML Parser Errors:**
- `line 351: could not find expected ':'`
- `line 353: mapping values are not allowed in this context`

## Decision

Establish **YAML-Safe Shell Scripting Patterns** for GitHub Actions workflows:

### 1. **Avoid Complex Heredocs in Variable Assignments**
❌ **Don't:**
```bash
VARIABLE=$(cat << 'EOF'
Multi-line content with: colons
And other YAML-meaningful characters
EOF
)
```

✅ **Do:**
```bash
VARIABLE="Simple single-line message without YAML conflicts"
```

### 2. **Use External Files for Complex Content**

❌ **Don't:** Embed complex markdown/text in shell variables

✅ **Do:** Store complex content in separate files and reference them

### 3. **Escape YAML-Meaningful Characters**

❌ **Don't:** `Here's what was set up:`

✅ **Do:** `Here is what was set up` (avoid apostrophes in workflow text)

### 4. **Prefer Simple String Concatenation**

❌ **Don't:** Complex multiline assignments within YAML

✅ **Do:** Build complex messages using simple string concatenation or external templates

### 5. **Test YAML Validity During Development**
**Required Command:**
```bash
yq eval '.github/workflows/workflow-name.yml' >/dev/null && echo "✅ YAML is valid" || echo "❌ YAML has errors"
```

## Rationale

### Technical Benefits

1. **Reliability**: Prevents workflow failures due to YAML parsing errors
2. **Maintainability**: Simpler patterns easier to debug and modify
3. **Predictability**: Consistent behavior across different YAML parsers
4. **Validation**: Easy to validate syntax during development

### Development Benefits

1. **Faster Development**: Avoid debugging complex YAML/shell interactions
2. **Team Productivity**: Clear patterns reduce time spent on syntax issues
3. **CI/CD Stability**: Prevent workflow failures in critical automation

## Implementation

### Immediate Actions

1. ✅ **Fixed init-complete.yml** with simplified manual steps message
2. ✅ **Established YAML validation** as part of development process

### Going Forward

1. **Code Review Requirement**: All workflow changes must pass YAML validation
2. **Pattern Documentation**: This ADR serves as reference for team development
3. **Template Updates**: Apply these patterns to workflow templates

## Alternatives Considered

### Alternative 1: External Template Files

**Pros:** Complete separation of complex content from YAML

**Cons:** Additional file management, less self-contained workflows

### Alternative 2: JSON-Encoded Strings

**Pros:** Guaranteed YAML compatibility

**Cons:** Reduced readability, complex escaping

### Alternative 3: GitHub Actions Expressions

**Pros:** Native GitHub syntax

**Cons:** Limited formatting capabilities, expression complexity

**Decision:** Chose simple string patterns for optimal balance of readability and reliability.

## Consequences

### Positive

- **Workflow Reliability**: Eliminates YAML parsing errors
- **Development Speed**: Clear patterns reduce debugging time
- **Team Knowledge**: Establishes best practices for complex workflows

### Negative

- **Content Limitations**: Complex formatted messages require external files
- **Pattern Learning**: Team needs to adopt new development patterns

### Mitigation

- **Documentation**: This ADR provides clear guidance
- **Validation Tools**: YAML checking integrated into development process
- **Examples**: Working patterns documented for reference

## References

- **GitHub Actions Documentation**: [Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- **YAML Specification**: [YAML Ain't Markup Language (YAML™) 1.2](https://yaml.org/spec/1.2.2/)
- **Related ADR**: [ADR-006: Two-Workflow Initialization Pattern](006-two-workflow-initialization.md)
---

[← ADR-009](009-asymmetric-cascade-review-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-011 →](011-configuration-driven-template-sync.md)
