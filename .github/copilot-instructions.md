# GitHub Copilot Instructions

## Project Overview

You are working with the Fork Management Template, an automated solution for managing long-lived forks of upstream repositories. This template uses GitHub Actions to automate synchronization, conflict resolution, and release management for OSDU (Open Subsurface Data Universe) projects.

## Key Architecture

### Branch Strategy
- `main` - Production branch with strict protection rules
- `fork_upstream` - Automatically tracks upstream repository changes
- `fork_integration` - Staging branch for conflict resolution before merging to main

### Core Workflows
1. **init.yml** - Repository initialization and configuration
2. **sync.yml** - Automated upstream synchronization with AI-enhanced PR descriptions
3. **build.yml** - Build and test automation for Java/Maven projects
4. **validate.yml** - PR validation, commit message checks, and conflict detection
5. **release.yml** - Automated semantic versioning with Release Please

## Development Guidelines

### Commit Messages
Always use conventional commits format:
```
feat: add new feature
fix: correct bug in sync workflow
chore: update dependencies
docs: improve README documentation
feat!: breaking change to API
```

### Branch Naming
Use the pattern: `agent/<issue-number>-<description>`
Example: `agent/123-fix-sync-conflict`

### Pull Requests
- Create PRs using GitHub CLI: `gh pr create`
- Include clear descriptions of changes
- Reference related issues
- Ensure all CI checks pass before merging

### Testing
- Write behavior-driven tests, not implementation tests
- For Java projects: use JUnit 5 and Mockito
- Aim for 80%+ test coverage
- Run tests locally before pushing: `mvn test`

## Common Tasks

### Adding New Workflow Features
1. Create workflow file in `.github/workflows/`
2. Follow existing patterns for permissions and error handling
3. Update documentation in `doc/` directory
4. Add ADR if making architectural changes

### Modifying Sync Behavior
1. Edit `.github/workflows/sync.yml`
2. Test with `workflow_dispatch` before relying on schedule
3. Consider impact on fork_integration branch
4. Update conflict resolution logic if needed

### Java/Maven Development
```bash
# Build project
mvn clean install

# Run tests with coverage
mvn clean test org.jacoco:jacoco-maven-plugin:0.8.11:report

# Run specific test
mvn test -Dtest=TestClassName#testMethodName
```

### Working with Issues
When creating issues, use appropriate labels:
- **Type**: `bug`, `enhancement`, `documentation`
- **Priority**: `high-priority`, `medium-priority`, `low-priority`
- **Component**: `configuration`, `dependencies`, `workflow`
- **AI**: Add `copilot` label for AI-suitable tasks

## Workflow Patterns

### Standard Workflow Structure
```yaml
name: Workflow Name
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly
  workflow_dispatch:      # Manual trigger

jobs:
  job-name:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      
    steps:
      - uses: actions/checkout@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Your Logic Here
        run: |
          # Implementation
```

### Error Handling
- Always include error handling in workflows
- Use `if: failure()` for cleanup steps
- Report status to PRs when applicable
- Create issues for persistent failures

## Security Considerations

- Never commit sensitive data or credentials
- Use GitHub Secrets for tokens and API keys
- Trivy scanner removes sensitive patterns automatically
- Follow branch protection rules strictly

## AI Development Tips

### For GitHub Copilot
- This project is AI-optimized with clear patterns
- Look for `copilot` labeled issues for AI-suitable tasks
- Follow existing code patterns for consistency
- Reference ADRs for architectural decisions

### Documentation Standards
- Document new features in appropriate `doc/` files
- Create ADRs for significant architecture changes
- Use clear, descriptive variable and function names

## Quick Reference

### Key Files
- `doc/src/adr/` - Architecture decisions
- `.github/workflows/` - All automation workflows
- `doc/product-prd.md` - Product requirements

### Environment Variables
- `UPSTREAM_OWNER` - Upstream repository owner
- `UPSTREAM_REPO` - Upstream repository name
- `GITHUB_TOKEN` - Authentication token
- `OPENAI_API_KEY` - Optional for AI PR descriptions

### Useful Commands
```bash
# View workflow runs
gh workflow view

# Create PR
gh pr create --title "feat: add feature" --body "Description"

# Check PR status
gh pr status

# View issues
gh issue list --label copilot
```

