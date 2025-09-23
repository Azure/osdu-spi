# ADR-025: GitLab Cross-Platform Integration Strategy for OSDU

## Status
Accepted

## Context
The Fork Management Template was originally designed for GitHub-only workflows. However, the OSDU (Open Subsurface Data Universe) community hosts its official repositories on GitLab at `community.opengroup.org`, creating a need for cross-platform integration to effectively contribute to OSDU projects while maintaining the template's GitHub-based fork management capabilities.

The OSDU community requires:
1. **Contributions to GitLab-hosted repositories** while maintaining GitHub fork workflows
2. **AI-enhanced development workflows** that span both platforms
3. **Synchronized changes** between GitHub forks and GitLab upstream repositories
4. **Automated merge request creation** on GitLab for OSDU contributions

## Problem Statement
The existing GitHub-only architecture creates barriers for OSDU community participation:

- **Platform isolation** - GitHub forks cannot directly contribute to GitLab repositories
- **Manual cross-platform work** - Developers must manually sync changes between platforms
- **Workflow disruption** - AI-enhanced workflows stop at GitHub boundaries
- **Community fragmentation** - Contributors work in isolation from main OSDU repository
- **Authentication complexity** - Multiple credential management systems

## Decision
We implement a comprehensive cross-platform integration strategy that bridges GitHub and GitLab while maintaining the template's core fork management capabilities:

### 1. Overall Strategy
- **AI-driven cross-platform bridging** using Model Context Protocol (MCP) servers
- **OSDU-specific GitLab targeting** for `community.opengroup.org` integration
- **Unified authentication system** with single GitLab token for multiple purposes
- **Automated workflow triggers** for seamless platform synchronization

### 2. Cross-Platform Architecture Pattern
**Options Considered:**
- Direct GitLab CLI integration (rejected - limited AI integration capabilities)
- Custom GitHub Actions for GitLab API (rejected - reinventing existing tooling)
- **MCP Server integration (chosen)** - Leverages AI capabilities with GitLab tools

**Implementation:**
- GitLab MCP Server (`@zereight/mcp-gitlab`) for GitLab API operations
- AI Assistant integration with MCP tools
- AI-enhanced merge request creation with context awareness

### 3. Authentication Strategy
**Options Considered:**
- Separate tokens for Maven and API access (rejected - complexity)
- GitHub token impersonation (rejected - security and compatibility issues)
- **Unified GitLab token approach (chosen)** - Single token for multiple purposes

**Implementation:**
- `GITLAB_TOKEN` secret serves both Maven authentication and GitLab API access
- Token validation in workflows ensures proper configuration
- Secure parameter passing through composite actions

### 4. Workflow Integration Pattern
**Options Considered:**
- Always-on GitLab sync (rejected - unnecessary overhead)
- Manual GitLab workflows only (rejected - breaks AI-enhanced workflow continuity)
- **Trigger-based integration (chosen)** - Responds to specific mentions and contexts

**Implementation:**
- `@alfi` mention triggers in GitHub comments and issues
- AI determines when GitLab MR creation is appropriate
- Maintains GitHub as primary platform with GitLab extension

## Architecture Components

### GitLab MCP Server Integration
**Purpose:** Enable AI agents to interact with GitLab APIs through structured tools
**Location:** `.github/template-workflows/osdu-alfi.yml`

**Key Configuration:**
```yaml
mcp_config: |
  {
    "mcpServers": {
      "gitlab": {
        "command": "npx",
        "args": ["-y", "@zereight/mcp-gitlab"],
        "env": {
          "GITLAB_PERSONAL_ACCESS_TOKEN": "${{ secrets.GITLAB_TOKEN }}",
          "GITLAB_API_URL": "https://community.opengroup.org/api/v4",
          "GITLAB_READ_ONLY_MODE": "false"
        }
      }
    }
  }
```

**Capabilities:**
- Read GitHub PR changes and context
- Create GitLab branches with synchronized changes
- Generate GitLab merge requests with appropriate metadata
- Comment back on GitHub with GitLab MR links

### Unified Authentication System
**Purpose:** Single credential management for cross-platform operations
**Implementation:** `GITLAB_TOKEN` secret used for:

1. **Maven Authentication** - As `COMMUNITY_MAVEN_TOKEN` for dependency resolution
2. **GitLab API Access** - For MCP server GitLab operations
3. **Build Integration** - Passed to Java build actions via input parameters

**Security Pattern:**
- Token scoped to minimum required permissions
- Validation checks before workflow execution
- No token logging or exposure in workflow outputs

### AI-Enhanced Cross-Platform Workflow
**Purpose:** Seamless GitHub-to-GitLab workflow automation
**Trigger Patterns:**
- `@alfi` mentions in GitHub PR reviews
- `@alfi` mentions in GitHub issue comments
- New GitHub issues with OSDU context

**Workflow Logic:**
1. **Context Analysis** - AI reads GitHub PR/issue content
2. **GitLab Preparation** - Creates appropriate GitLab branch
3. **Change Synchronization** - Pushes GitHub changes to GitLab
4. **MR Creation** - Creates GitLab merge request with OSDU-specific labels
5. **Feedback Loop** - Comments on GitHub with GitLab MR link

### OSDU-Specific Configuration
**GitLab Instance:** `community.opengroup.org` (OSDU community GitLab)
**Branch Naming:** `ai-agent/` prefix for automated branches
**MR Labels:** `MR::Dependencies Upgrade` and context-appropriate labels
**Repository Detection:** Skip template repositories, only run on actual forks

## Implementation Benefits

### Technical Benefits
- **Seamless cross-platform integration** without disrupting GitHub workflows
- **AI-enhanced automation** extends to GitLab contributions
- **Unified credential management** reduces authentication complexity
- **OSDU community integration** enables direct upstream contribution
- **Template consistency** - All fork instances gain GitLab capabilities

### User Experience Benefits
- **No platform switching** required for OSDU contributions
- **AI assistance** for GitLab merge request creation and management
- **Automatic synchronization** maintains consistency across platforms
- **Community engagement** facilitated through automated workflows
- **Reduced manual work** for cross-platform development

## Implementation Details

### Files Created/Modified
1. **`.github/template-workflows/osdu-alfi.yml`** - Main GitLab integration workflow
2. **`.github/actions/java-build/action.yml`** - Added `gitlab_token` input parameter
3. **`.github/template-workflows/build.yml`** - GitLab token parameter passing
4. **`.github/template-workflows/validate.yml`** - GitLab token for Maven authentication
5. **`.github/sync-config.json`** - Added osdu-alfi.yml to template sync

### Key Technical Patterns
- **Workflow Triggers:** `pull_request_review`, `issue_comment`, `issues` events
- **Authentication:** Flexible AI provider authentication
- **Platform Detection:** Template vs fork repository detection
- **Error Handling:** Comprehensive validation and graceful degradation
- **Security:** Token validation and no-logging policies

### Maven Integration Pattern
**Purpose:** Enable GitLab-hosted Maven repository access during builds
**Implementation:**
- `GITLAB_TOKEN` passed as `gitlab_token` parameter to `java-build` action
- Mapped to `COMMUNITY_MAVEN_TOKEN` environment variable
- Used by Maven settings for GitLab package registry authentication
- Enables access to `org.opengroup.osdu:*` dependencies

## Consequences

### Positive
- ✅ **OSDU community integration** - Direct contribution capability to GitLab repositories
- ✅ **AI workflow continuity** - AI assistance extends across both platforms
- ✅ **Simplified authentication** - Single token for multiple platform operations
- ✅ **Automated MR creation** - Reduces manual cross-platform synchronization
- ✅ **Template-wide deployment** - All fork instances gain capabilities automatically
- ✅ **Maven dependency access** - Enables building projects with GitLab-hosted dependencies

### Negative
- ⚠️ **Increased complexity** - Additional workflow logic and MCP server dependency
- ⚠️ **External dependency** - Relies on `@zereight/mcp-gitlab` npm package
- ⚠️ **GitLab-specific configuration** - OSDU community GitLab instance coupling
- ⚠️ **Token management** - Single token failure affects multiple capabilities

### Neutral
- 📝 **Optional functionality** - GitLab integration only activates when configured
- 📝 **Backward compatibility** - Existing workflows continue unchanged
- 📝 **Template-only impact** - Changes isolated to template workflows directory

## Testing Strategy
Cross-platform integration testing focuses on real-world OSDU contribution scenarios:

### Functional Testing
- Validate `@alfi` mention triggers activate GitLab workflow
- Confirm GitHub PR changes synchronize to GitLab branches
- Verify GitLab merge requests created with appropriate metadata
- Test Maven authentication with GitLab-hosted dependencies

### Integration Testing
- Validate token authentication across Maven and GitLab API usage
- Confirm MCP server reliability and error handling
- Test workflow behavior in template vs fork repository contexts
- Validate AI-enhanced MR description generation

### Security Testing
- Confirm no token exposure in workflow logs or outputs
- Validate MCP server permissions and GitLab API scope
- Test authentication fallback and error scenarios
- Verify template repository protection mechanisms

## Rollout Plan

### Phase 1: Core Integration (Completed)
- ✅ GitLab MCP server workflow creation
- ✅ Maven authentication integration
- ✅ Template workflow sync configuration
- ✅ Initial OSDU-specific configuration

### Phase 2: Refinement and Enhancement (Completed)
- ✅ Authentication strategy unification
- ✅ Workflow trigger optimization
- ✅ Error handling and validation improvements
- ✅ Security hardening and token management

### Phase 3: Production Deployment (Completed)
- ✅ Template sync distribution to fork instances
- ✅ Real-world testing with OSDU repositories
- ✅ Workflow reliability validation
- ✅ Community integration verification

### Phase 4: Monitoring and Optimization (Ongoing)
- 📋 Monitor GitLab integration usage patterns
- 📋 Collect feedback from OSDU community contributors
- 📋 Optimize MCP server performance and reliability
- 📋 Enhance AI-generated MR quality

## Success Metrics
- **OSDU contribution rate** - Increased contributions to GitLab OSDU repositories
- **Cross-platform workflow adoption** - Usage of `@alfi` triggers in fork instances
- **Maven build success rate** - Successful builds with GitLab-hosted dependencies
- **AI MR quality** - Quality and accuracy of AI-generated GitLab merge requests
- **Authentication reliability** - Successful token-based operations across platforms

## Alternatives Considered

### 1. GitHub-GitLab Mirror Strategy
**Approach:** Automatic mirroring between GitHub forks and GitLab repositories
**Rejected:** Complex synchronization, merge conflict resolution challenges, loss of GitHub workflow benefits

### 2. Separate GitLab-Native Template
**Approach:** Create separate fork management template for GitLab
**Rejected:** Duplicated effort, fragmented community, loss of GitHub ecosystem benefits

### 3. Manual Cross-Platform Workflows
**Approach:** Provide documentation for manual GitHub-to-GitLab synchronization
**Rejected:** Breaks AI-enhanced workflow continuity, increases manual overhead, error-prone

### 4. GitLab CLI Integration Only
**Approach:** Use GitLab CLI without MCP server integration
**Rejected:** Limited AI integration capabilities, manual scripting required, no structured tool interface

## Related ADRs
- **ADR-017: MCP Server Integration Pattern** - Establishes MCP server usage patterns
- **ADR-014: AI-Enhanced Development Workflow** - Provides AI integration foundation
- **ADR-002: GitHub Actions Automation** - Defines workflow automation patterns
- **ADR-015: Template-Workflows Separation** - Enables clean template workflow deployment

## References
- [OSDU Community GitLab](https://community.opengroup.org/osdu)
- [GitLab MCP Server (@zereight/mcp-gitlab)](https://www.npmjs.com/package/@zereight/mcp-gitlab)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [Issue #163: Add OSDU GitLab Alfi integration workflow](https://github.com/danielscholl-osdu/osdu-fork-template/issues/163)
- [AI Development Tools Documentation](https://platform.openai.com/docs/overview)