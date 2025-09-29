# Pull Request Validation Workflow

The pull request validation workflow acts as the automated quality gatekeeper for your repository. It ensures that all changes meet established standards before they can be merged into protected branches. This workflow runs comprehensive checks on every pull request and serves as your first line of defense against build failures, security vulnerabilities, and process violations that could disrupt your development workflow or compromise your fork's stability.

The validation system is intelligent enough to apply different rules based on context - it treats upstream sync pull requests differently than regular development contributions, and applies stricter requirements to changes targeting your production `main` branch versus integration branches. This contextual awareness helps balance thorough quality control with practical workflow needs.

## When It Runs

The validation workflow activates automatically across multiple scenarios to maintain consistent quality standards:

- **Every pull request** to protected branches (`main`, `fork_integration`, `fork_upstream`) - Ensures all incoming changes meet quality standards
- **Direct pushes** to protected branches - Validates changes that bypass the PR process (when permitted)
- **Manual trigger** for post-initialization validation - Allows on-demand quality checks during setup or troubleshooting

## What Gets Validated

The workflow performs comprehensive validation across three key areas to ensure both code quality and process compliance:

### Code Quality Validation
The system verifies that your code is functional and maintainable by running build verification to ensure code compiles and all dependencies resolve correctly, executing the full test suite and generating coverage reports, and performing lint checks to enforce consistent code style and formatting standards.

### Process Compliance Verification
Beyond code quality, the workflow enforces development process standards by validating that commit messages follow conventional commit format for consistent release notes, checking that branch names follow established naming patterns, and detecting potential merge conflicts early in the development cycle.

### Security and Dependency Analysis
The validation system includes security-focused checks that scan for known vulnerabilities in your dependencies, analyze package integrity to prevent supply chain attacks, and detect accidentally committed secrets or credentials in your code changes.

## Validation Results

### ✅ **All Checks Pass**
- PR can be merged immediately
- No action required

### ⚠️ **Some Checks Fail**
- PR blocked until issues resolved
- Check specific failure details in PR status

### ❌ **Critical Failures**
- Build errors, security issues, or policy violations
- Must be fixed before merge consideration

## How to Fix Common Issues

### Build Failures
```bash
# Run build locally to debug
mvn clean install

# Check for missing dependencies
mvn dependency:tree
```

### Commit Message Issues
```bash
# Fix last commit message
git commit --amend -m "feat: add new feature description"

# For multiple commits, use interactive rebase
git rebase -i HEAD~3
```

### Test Failures
```bash
# Run tests locally
mvn test

# Run specific test class
mvn test -Dtest=TestClassName

# Run with coverage report
mvn test jacoco:report
```

### Security Vulnerabilities
```bash
# Check for vulnerabilities
mvn dependency-check:check

# Update dependencies to latest versions
mvn versions:use-latest-versions

# Display dependency updates available
mvn versions:display-dependency-updates
```

### Merge Conflicts
```bash
# Update your branch with target branch
git fetch origin
git merge origin/main  # or target branch

# Resolve conflicts in IDE
# Then commit resolution
git add .
git commit -m "resolve: merge conflicts with main"
```

## Validation Jobs

The workflow runs four distinct validation jobs:

| Job | Purpose | What It Checks |
|-----|---------|----------------|
| **Initialization Check** | Verifies repository setup | Ensures workflows are properly deployed |
| **Repository State** | Detects project type | Identifies Java projects via `pom.xml` |
| **Java Build** | Compiles and tests | Maven build, unit tests, dependency resolution |
| **Code Validation** | Process compliance | Conventional commits, merge conflicts, branch status |

## Branch-Specific Rules

All protected branches use the same validation rules, with exemptions for specific PR types:

| Branch | Standard Validation | Exemptions |
|--------|-------------------|------------|
| **`main`** | All checks required + human approval | None - strictest validation |
| **`fork_integration`** | All checks required | None - full validation for integration safety |
| **`fork_upstream`** | All checks required | Sync PRs skip conventional commit validation |
| **Feature branches** | N/A - not protected | Standard PR validation when targeting protected branches |

## Special Cases

### Sync PRs
- **Relaxed commit standards** - Upstream commits may not follow conventions
- **Conflict handling** - Automatically creates resolution guidance
- **AI enhancement** - Generates PR descriptions when possible

### Emergency Fixes
- **Override capability** - Admin can bypass non-critical checks
- **Audit trail required** - Override reason must be documented

## Status Check Details

### Required Checks
- `check-initialization` - Repository setup verification
- `java-build` - Maven compilation, dependency resolution, unit tests
- `code-validation` - Conventional commits, merge conflicts, branch status

### Check Exemptions
- **Sync PRs**: Skip conventional commit validation (upstream commits may not follow format)
- **Release PRs**: Skip conventional commit validation (generated by release automation)
- **Dependabot PRs**: Reduced validation requirements for automated dependency updates

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Initialization check failed" | Repository not properly set up | Ensure workflows are deployed and `pom.xml` exists |
| "Java build failed" | Compilation or dependency issues | Run `mvn clean install` locally, check dependency conflicts |
| "Unit tests failing" | Test failures in Maven build | Run `mvn test` locally, fix failing test cases |
| "Conventional commits validation failed" | Commit messages don't follow format | Use format: `feat:`, `fix:`, `chore:`, etc. |
| "Merge conflicts detected" | Git conflict markers found | Resolve conflicts locally and commit resolution |
| "Repository not initialized" | Missing required setup files | Complete repository initialization first |
| "Branch status validation failed" | Branch protection or merge issues | Ensure branch is up to date with target |

## Configuration

### Commit Message Format
```
type(scope): description

feat: add new feature
fix: resolve bug in component
docs: update API documentation
chore: update dependencies
```

### Coverage Thresholds
- **Minimum coverage**: 80%
- **Branch coverage**: 75%
- **Function coverage**: 85%

## Related

- [Conventional Commits](https://conventionalcommits.org/) - Commit message standards
- [Security Scanning](../decisions/adr_016_security.md) - Security validation details
- [Build Workflow](build.md) - Detailed build process