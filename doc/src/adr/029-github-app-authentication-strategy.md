# ADR-029: GitHub App Authentication Strategy for Workflow Automation

## Status
**Accepted** - 2025-10-06

## Context

Microsoft's enterprise GitHub environment enforces strict security controls that fundamentally impact workflow automation capabilities. Three key constraints create the need for an alternative authentication approach:

### 1. Organization-Wide GITHUB_TOKEN Restrictions

Microsoft DSR (Digital Security & Resilience) has configured organization-level settings that override repository-level permissions:

- Default `GITHUB_TOKEN` permission is **read-only** for all scopes
- "Allow GitHub Actions to create and approve pull requests" is **disabled**
- These settings cannot be changed at the repository level
- Explicit `permissions` blocks in workflows are overridden by org policy

### 2. Personal Access Token (PAT) Deprecation Policy

Microsoft is aggressively phasing out PAT usage following the Secure Future Initiative:

- January 2025: 365-day maximum PAT lifetime
- March 2025: 180-day maximum PAT lifetime
- May 2025: 90-day maximum PAT lifetime
- July 2025: Classic PATs restricted to 30 days
- No automated renewal API available
- Security incidents involving compromised PATs drive policy

### 3. Required Elevated Permissions

Critical workflows in the fork management system require permissions that `GITHUB_TOKEN` cannot provide:

- **Release Automation**: Creating release PRs and GitHub releases (requires `contents: write` and `pull-requests: write`)

- **Repository Initialization**: Setting repository variables, deploying workflows, configuring security settings, creating rulesets (requires `administration: write`, `workflows: write`, `variables: write`)

Traditional approaches (PATs, service accounts) are either blocked by policy or create operational/security burdens incompatible with enterprise requirements.

## Decision

Adopt **GitHub Apps with installation tokens** as the standard authentication mechanism for all workflow automation requiring elevated permissions.

### Core Implementation

1. **Create Organization-Level GitHub App**

   - Owned by the Azure/Microsoft organization (not individuals)
   - Configured with minimal required permissions
   - Installed on specific repositories requiring automation

2. **Required Permissions**

   - **Contents**: Read and write (for releases, git operations)
   - **Pull requests**: Read and write (for release PRs)
   - **Administration**: Read and write (for variables, security settings, rulesets)
   - **Workflows**: Read and write (for deploying workflow files)
   - **Variables**: Read and write (for repository configuration)

3. **Token Generation in Workflows**

   ```yaml
   - name: Generate GitHub App Token
     id: app-token
     uses: actions/create-github-app-token@v1
     with:
       app-id: ${{ secrets.RELEASE_APP_ID }}
       private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

   - name: Use Token for Elevated Operations
     env:
       GH_TOKEN: ${{ steps.app-token.outputs.token }}
     run: |
       gh pr create --title "release"
   ```

4. **Secrets Configuration**

   - `RELEASE_APP_ID`: Application ID (organization-level secret)
   - `RELEASE_APP_PRIVATE_KEY`: Private certificate (organization-level secret)
   - Secrets distributed to all repositories requiring automation

## Rationale

### Why GitHub Apps Are Superior

**Security Advantages:**

- **Short-lived tokens**: 1-hour expiration vs 90+ days for PATs
- **Scoped permissions**: Granular control over what the app can access
- **Installation-based**: Limited to specific repositories, not all user resources
- **Certificate-based**: Private key less likely to be accidentally committed than PAT
- **Audit trail**: Clear attribution in GitHub logs (app name vs user)

**Operational Advantages:**

- **Not tied to individuals**: Survives employee changes, no personal account dependency
- **No manual rotation**: Tokens generated on-demand, no weekly/monthly renewal
- **Team-managed**: Multiple organization admins can manage the app
- **Microsoft-approved**: Explicitly recommended in Microsoft's GitHub TSG documentation
- **Policy-compliant**: Aligns with DSR requirements and PAT deprecation timeline

**Enterprise Advantages:**

- **Centralized management**: Single app serves all OSDU repositories
- **Consistent security model**: Same approach across organization
- **Emergency response**: Org admins can revoke certificates in security incidents
- **Compliance**: Meets SDL requirements for credential lifecycle management

### Comparison with Alternatives

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **GitHub App** | • Short-lived tokens<br>• Not tied to individuals<br>• Microsoft-recommended<br>• Granular permissions | • Initial setup complexity<br>• Requires org admin approval | ✅ **Accepted** |
| **Personal PAT** | • Simple to create<br>• Direct user control | • Tied to individual<br>• Long-lived credentials<br>• Being phased out by Microsoft<br>• Manual rotation | ❌ Rejected |
| **Service Account + PAT** | • Not tied to personal account | • Still requires PAT<br>• Manual rotation<br>• Requires license seat<br>• Against Microsoft policy | ❌ Rejected |
| **Fine-grained PAT** | • Better scoping than classic PAT | • Still manual rotation<br>• 90-day max lifetime<br>• No renewal API<br>• Against policy direction | ❌ Rejected |
| **Manual Workflows** | • No automation complexity | • Breaks automation benefits<br>• Manual intervention required<br>• Not scalable | ❌ Rejected |

## Consequences

### Positive

- **Policy Compliance**: Aligns with Microsoft's PAT deprecation roadmap
- **Enhanced Security**: Short-lived tokens reduce compromise window from months to 1 hour
- **Team Resilience**: Not dependent on any individual employee's account
- **Operational Simplicity**: No manual rotation or credential management
- **Audit Clarity**: Clear attribution in GitHub audit logs (app identity vs user)
- **Scalability**: Single app serves all fork repositories with consistent behavior
- **Future-Proof**: Works within Microsoft's security control framework

### Negative

- **Setup Complexity**: Requires organization admin to create and approve app
- **Permission Management**: Changes to permissions require re-approval on installations
- **Documentation Burden**: Teams need to understand GitHub Apps vs PATs
- **Secret Distribution**: App ID and private key must be added to each repository
- **Dependency**: Relies on GitHub Apps infrastructure availability

### Neutral

- **Token Lifetime**: 1-hour expiration sufficient for workflow execution (same as Entra ID tokens)
- **Permission Model**: Fine-grained permissions require careful configuration
- **Migration Path**: Existing repositories need secrets added but workflows adapt automatically

## Implementation Details

### Phase 1: GitHub App Creation (Completed)

**Application Configuration:**

- **Name**: `osdu-spi-automation`
- **Owner**: Personal account initially, transfer to Azure organization for production
- **Homepage**: https://github.com/Azure/osdu-spi
- **Webhook**: Disabled (not needed for token generation)
- **Installation**: Azure organization repositories

**Permission Configuration:**

```yaml
Repository Permissions:
  contents: read-write        # For releases, git operations
  pull-requests: read-write   # For creating release PRs
  administration: read-write  # For variables, security, rulesets
  workflows: read-write       # For deploying workflow files
  variables: read-write       # For setting repository variables
  metadata: read-only         # Automatic, required

Organization Permissions: none
Account Permissions: none
```

### Phase 2: Workflow Integration (Completed)

**Release Automation** (`dev-release.yml`):

```yaml
jobs:
  release-please:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v5

      - name: Generate GitHub App Token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - name: Generate Release PR
        uses: googleapis/release-please-action@v4
        with:
          token: ${{ steps.app-token.outputs.token }}  # Uses app token
          config-file: .release-please-config.json
```

**Repository Initialization** (`init-complete.yml`):

```yaml
jobs:
  setup_repository:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      actions: write
      issues: write
    steps:
      - name: Generate GitHub App Token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - name: Configure Variables
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}  # Uses app token
        run: |
          gh variable set UPSTREAM_REPO_URL --body "$REPO_URL"

      - name: Configure Security
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}  # Uses app token
        run: |
          ./setup-security.sh

      - name: Setup Repository Rulesets
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}  # Uses app token
        run: |
          ./setup-rulesets.sh
```

### Phase 3: Secret Distribution

**Repository-Level Secrets**:

```bash
# Add secrets to individual repository
gh secret set RELEASE_APP_ID --repo Azure/osdu-spi --body "2072585"
gh secret set RELEASE_APP_PRIVATE_KEY --repo Azure/osdu-spi --body "@osdu-spi-automation.pem"
```

## Security Considerations

### Token Lifecycle

- **Generation**: On-demand per workflow run
- **Lifetime**: 1 hour maximum
- **Scope**: Limited to installed repositories and configured permissions
- **Revocation**: Automatic expiration, manual revocation via app settings

### Private Key Management

- **Storage**: GitHub Secrets (encrypted at rest)
- **Access**: Only available to workflow runs, not visible in UI
- **Rotation**: Generate new key, update secret, revoke old key
- **Backup**: Keep secure backup of private key for disaster recovery

### Permission Boundaries

- **Principle of Least Privilege**: Only grant permissions actively used by workflows
- **Installation Scope**: Only install on repositories requiring automation
- **Regular Review**: Audit app permissions quarterly
- **Change Management**: Re-approval required for permission changes

### Incident Response

**If App Credentials Are Compromised:**
1. Immediately revoke private key in app settings
2. Generate new private key
3. Update organization secrets with new key
4. Review audit logs for unauthorized operations
5. Document incident per Microsoft security procedures

### For New Fork Repositories

GitHub App authentication is automatically configured:

1. Initialization workflow uses app token
2. Secrets inherited from organization
3. App already installed on organization repositories
4. No manual configuration required

## Monitoring and Validation

### Success Metrics

- **Token Generation Rate**: Monitor `actions/create-github-app-token` success rate
- **Authentication Failures**: Alert on 403 errors from GitHub API
- **Workflow Success Rate**: Track release and initialization workflow completion
- **PAT Elimination**: Verify no remaining `secrets.GH_TOKEN` references

### Validation Steps

1. **Release Workflow**: Verify release PRs are created successfully
2. **Init Workflow**: Verify repository variables, security settings, and rulesets are configured
3. **Audit Trail**: Confirm app attribution in GitHub audit logs
4. **Token Lifetime**: Verify 1-hour tokens sufficient for all workflow operations
5. **Permission Scope**: Confirm no over-permissioning or access violations

## Related Decisions

- [ADR-002: GitHub Actions-Based Automation](002-github-actions-automation.md) - Workflow automation framework
- [ADR-004: Release Please for Version Management](004-release-please-versioning.md) - Release automation using app tokens
- [ADR-006: Two-Workflow Initialization Pattern](006-two-workflow-initialization.md) - Initialization using app tokens
- [ADR-026: Dependabot Security Update Strategy](026-dependabot-security-update-strategy.md) - Security automation context

## Success Criteria

- ✅ Release Please successfully creates release PRs without PAT
- ✅ Repository initialization completes all configuration steps
- ✅ No `secrets.GH_TOKEN` references remain in workflow files
- ✅ All fork repositories use GitHub App authentication
- ✅ Zero manual credential rotation required
- ✅ App attribution visible in GitHub audit logs
- ✅ Workflow success rate matches or exceeds PAT baseline

## References

- [Microsoft GitHub TSG: Reduce or Eliminate PAT Use](https://github.com/microsoft/github-operations/blob/main/docs/github/security/tsg/pat-elimination.md)
- [Microsoft GitHub TSG: Securing and Evaluating GitHub Actions](https://github.com/microsoft/github-operations/blob/main/docs/security/tsg/actions.md)
- [GitHub Docs: GitHub Apps Overview](https://docs.github.com/apps)
- [GitHub Docs: Authenticating with a GitHub App](https://docs.github.com/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub Docs: Permissions for GitHub Apps](https://docs.github.com/rest/authentication/permissions-required-for-github-apps)
- [Actions: create-github-app-token](https://github.com/actions/create-github-app-token)

---

[← ADR-028](028-workflow-script-extraction-pattern.md) | :material-arrow-up: [Catalog](index.md)
