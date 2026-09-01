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

Microsoft is phasing out PAT usage following the Secure Future Initiative:

- January 2025: 365-day maximum PAT lifetime
- March 2025: 180-day maximum PAT lifetime
- May 2025: 90-day maximum PAT lifetime
- July 2025: Classic PATs restricted to 30 days
- No automated renewal API available
- Security incidents involving compromised PATs drive policy

### 3. Required Elevated Permissions

Workflows in the fork management system need permissions that `GITHUB_TOKEN` cannot provide: creating release PRs and releases (`contents: write`, `pull-requests: write`), and setting repository variables, deploying workflow files, configuring security settings, and creating rulesets during initialization and settings reconciliation (`administration: write`, `workflows: write`, `variables: write`).

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
     uses: actions/create-github-app-token@<sha>  # pinned by SHA
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

   - `RELEASE_APP_ID`: Application ID
   - `RELEASE_APP_PRIVATE_KEY`: Private key
   - Set at organization level where available, otherwise per repository; `.github/scripts/rotate-app-key.sh` distributes a key from Azure Key Vault to a repository and organization secret

## Alternatives Considered

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **GitHub App** | • Short-lived tokens<br>• Not tied to individuals<br>• Microsoft-recommended<br>• Granular permissions | • Initial setup complexity<br>• Requires org admin approval | **Accepted** |
| **Personal PAT** | • Simple to create<br>• Direct user control | • Tied to individual<br>• Long-lived credentials<br>• Being phased out by Microsoft<br>• Manual rotation | Rejected |
| **Service Account + PAT** | • Not tied to personal account | • Still requires PAT<br>• Manual rotation<br>• Requires license seat<br>• Against Microsoft policy | Rejected |
| **Fine-grained PAT** | • Better scoping than classic PAT | • Still manual rotation<br>• 90-day max lifetime<br>• No renewal API<br>• Against policy direction | Rejected |
| **Manual Workflows** | • No automation complexity | • Breaks automation benefits<br>• Manual intervention required<br>• Not scalable | Rejected |

## Consequences

Tokens expire after one hour and are minted per run, so nothing is rotated by hand and no individual's account is on the path. The cost is setup: an organization admin must create and approve the app, any permission change needs re-approval on every installation, and the App ID and private key must be present as secrets wherever a workflow mints a token.

## Implementation Details

**Application**: one GitHub App owned by the Azure organization and installed on the OSDU fork repositories. Repository permissions: contents, pull-requests, administration, workflows, and variables read-write; metadata read-only. No organization or account permissions.

**Workflows that mint a token** (all via `actions/create-github-app-token`, pinned by SHA):

- Template: `dev-release.yml` (Release Please), `init-complete.yml` (variables, security settings, rulesets)
- Forks: `release.yml`, `sync.yml`, `sync-template.yml`, `cascade.yml`, `adopt-fork.yml`, `settings-apply.yml`

The token is passed as `GH_TOKEN` or `GITHUB_TOKEN` to the steps that need elevated access; read-only steps keep the default token. Rulesets, required variables, and GHCR visibility are reconciled by the scripts under `.github/scripts/settings-apply/`, which `settings-apply.yml` runs on a schedule and `init-complete.yml` runs once at initialization.

## Security Considerations

### Token Lifecycle

- **Generation**: On-demand per workflow run
- **Lifetime**: 1 hour maximum
- **Scope**: Limited to installed repositories and configured permissions
- **Revocation**: Automatic expiration, manual revocation via app settings

### Private Key Management

- **Storage**: GitHub Secrets (encrypted at rest)
- **Access**: Only available to workflow runs, not visible in UI
- **Rotation**: Generate a new key, distribute it with `.github/scripts/rotate-app-key.sh`, revoke the old key
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

## Related Decisions

- [ADR-002: GitHub Actions-Based Automation](002-github-actions-automation.md) - Workflow automation framework
- [ADR-004: Release Please for Version Management](004-release-please-versioning.md) - Release automation using app tokens
- [ADR-006: Two-Workflow Initialization Pattern](006-two-workflow-initialization.md) - Initialization using app tokens
- [ADR-026: Dependabot Security Update Strategy](026-dependabot-security-update-strategy.md) - Security automation context

## References

- [Microsoft GitHub TSG: Reduce or Eliminate PAT Use](https://github.com/microsoft/github-operations/blob/main/docs/github/security/tsg/pat-elimination.md)
- [Microsoft GitHub TSG: Securing and Evaluating GitHub Actions](https://github.com/microsoft/github-operations/blob/main/docs/security/tsg/actions.md)
- [GitHub Docs: GitHub Apps Overview](https://docs.github.com/apps)
- [GitHub Docs: Authenticating with a GitHub App](https://docs.github.com/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub Docs: Permissions for GitHub Apps](https://docs.github.com/rest/authentication/permissions-required-for-github-apps)
- [Actions: create-github-app-token](https://github.com/actions/create-github-app-token)

---

[← ADR-028](028-workflow-script-extraction-pattern.md) | :material-arrow-up: [Catalog](index.md)
