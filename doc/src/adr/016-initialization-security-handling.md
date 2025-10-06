# ADR-016: Initialization Security Handling

## Status
Accepted

## Context
Many upstream repositories contain secrets or sensitive data in their git history. GitHub's push protection feature blocks these commits from being pushed, which prevents the initialization workflow from creating the `fork_upstream` branch during repository setup.

Additionally, organizations can enforce push protection at the organization level, which cannot be overridden by repository-level settings.

## Decision
We will implement a multi-layered approach to handle push protection during initialization:

1. **Detection**: Check for both repository-level and organization-level push protection
2. **Mitigation**: Attempt to disable push protection at the repository level
3. **Alternative Strategies**: If disabling fails, try alternative push strategies
4. **Clear Guidance**: Provide detailed instructions for manual resolution when automated approaches fail

## Implementation

### 1. Enhanced Security Detection
```yaml
# Check organization-level push protection status first
ORG_NAME=$(echo "${{ github.repository }}" | cut -d'/' -f1)
ORG_PUSH_PROTECTION="unknown"

if ORG_SETTINGS=$(gh api "/orgs/$ORG_NAME" 2>/dev/null); then
  ORG_PUSH_PROTECTION=$(echo "$ORG_SETTINGS" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // "unknown"')
  echo "::notice::Organization-level push protection: $ORG_PUSH_PROTECTION"
fi

# Attempt to disable at repository level
gh api --method PATCH "/repos/${{ github.repository }}" \
  --input .github/security-off.json

# Verify settings were applied
REPO_SETTINGS=$(gh api "/repos/${{ github.repository }}")
PUSH_PROTECTION_STATUS=$(echo "$REPO_SETTINGS" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // "unknown"')
```

### 2. Alternative Push Strategy
When the initial push fails due to push protection:
```bash
# Create a minimal branch first
git checkout -b temp_upstream upstream/$DEFAULT_BRANCH
git reset --soft HEAD~1000 2>/dev/null || git reset --soft $(git rev-list --max-parents=0 HEAD)
git commit -m "chore: initial upstream reference"

if git push -u origin temp_upstream; then
  # Try to update to full history
  git checkout -b fork_upstream upstream/$DEFAULT_BRANCH
  git push -u origin fork_upstream --force
fi
```

### 3. Enhanced Error Handling
When push protection cannot be bypassed:
- Extract secret allowlist URLs from the error output
- Create a detailed issue with multiple resolution options
- Provide clear instructions for each resolution path

## Consequences

### Positive
- Handles both repository-level and organization-level push protection
- Provides multiple fallback strategies
- Creates actionable issues with clear resolution steps
- Automatically extracts and presents secret allowlist URLs
- Maintains security for all future operations

### Negative
- More complex implementation
- May require manual intervention for organization-level protection
- Alternative push strategy might not work in all cases

### Security Considerations
- The temporary disable only affects the initialization process
- Organization-level protection is respected and not bypassed
- Users are guided to use GitHub's official secret allowlist mechanism
- All future operations have full security protection enabled

## Manual Resolution Options

When automated approaches fail, users have three options:

1. **Secret Allowlist URLs**: Use GitHub's official mechanism to allow specific secrets
2. **Organization Admin Action**: Temporarily disable push protection at the organization level
3. **Manual Initialization**: Clone locally and use `git push --no-verify` with appropriate permissions

## Alternatives Considered

1. **Simple retry logic**: Insufficient for organization-level protection
2. **History rewriting**: Would break synchronization with upstream
3. **Forking without history**: Would lose valuable commit history
4. **Requiring pre-initialization setup**: Would complicate the user experience

The chosen approach balances automation with respect for security policies while providing clear paths for resolution when manual intervention is required.

---

[← ADR-015](015-template-workflows-separation-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-017 →](017-mcp-server-integration-pattern.md)
