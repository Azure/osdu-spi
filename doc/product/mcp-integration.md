# MCP Server Integration for Fork Management

This document describes how to integrate Model Context Protocol (MCP) servers with GitHub Copilot Agent in fork repositories managed by this template.

## Overview

MCP servers extend GitHub Copilot Agent's capabilities by providing specialized tools and context. For OSDU fork repositories, the Maven MCP Server enables AI-enhanced dependency management, security scanning, and version control.

## Maven MCP Server Integration

### What is the Maven MCP Server?

The [Maven MCP Server](https://pypi.org/project/mvn-mcp-server/) provides GitHub Copilot Agent with tools for:
- **Version Management**: Check Maven dependency versions against Maven Central
- **Security Scanning**: Identify vulnerabilities in project dependencies
- **Batch Processing**: Analyze multiple dependencies efficiently
- **AI-Driven Workflows**: Enable intelligent dependency management decisions

### Prerequisites

For fork repositories using this template:
1. Repository must be configured with GitHub Copilot Agent
2. Repository must contain Java/Maven project structure
3. Administrator access to repository settings

## Configuration Steps

### 1. Repository MCP Configuration

Navigate to your fork repository settings:
1. Go to **Settings** → **Copilot** → **Copilot agent**
2. Add the following MCP configuration:

```json
{
  "mcpServers": {
    "mvn-mcp-server": {
      "command": "uvx",
      "args": ["mvn-mcp-server"]
    }
  }
}
```

### 2. Firewall Configuration (Automatic)

OSDU projects often require access to `community.opengroup.org` and other Maven repositories. The template automatically configures GitHub Copilot's firewall to allow access to required domains:

**Automatically Allowlisted Domains:**
- `community.opengroup.org` - OSDU Open Group community resources
- `repo1.maven.org` - Maven Central repository
- `central.maven.org` - Maven Central mirror
- `repo.maven.apache.org` - Apache Maven repository
- `plugins.gradle.org` - Gradle plugins repository

This is configured via the `COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS` repository variable.

### 3. Environment Configuration (Optional)

If your Maven projects require specific environment variables:

```json
{
  "mcpServers": {
    "mvn-mcp-server": {
      "command": "uvx",
      "args": ["mvn-mcp-server"]
    }
  }
}
```

### 4. Validation

After configuration:
1. Create a test issue in your repository
2. Assign it to `@copilot` 
3. Ask Copilot to check Maven dependencies
4. Verify that MCP server tools are available in the response

## Available Tools

Once configured, GitHub Copilot Agent has access to:

### check_version_tool
```bash
# Example usage in Copilot conversation:
"Check if spring-boot-starter-web has any newer versions available"
```

### scan_java_project_tool  
```bash
# Example usage:
"Scan this project for security vulnerabilities in dependencies"
```

### list_available_versions_tool
```bash
# Example usage:
"List all available versions for jackson-databind"
```

## Integration with Fork Workflows

### Automated Dependency Management

The MCP server integrates with existing fork workflows:

1. **Upstream Sync**: When upstream changes include dependency updates, Copilot can analyze security implications
2. **Conflict Resolution**: Dependency conflicts can be resolved with AI-enhanced version analysis
3. **Release Planning**: Vulnerability scans inform release timing decisions

### Workflow Enhancement Examples

**In sync workflow comments:**
```markdown
@copilot Please analyze the dependency changes in this upstream sync and check for security vulnerabilities
```

**In issue resolution:**
```markdown
@copilot Scan the project dependencies and suggest updates that address CVE-2023-XXXXX
```

## Security Considerations

### MCP Server Safety
- The Maven MCP Server is read-only and does not modify your repository
- All dependency analysis is performed against public Maven Central data
- No sensitive project information is transmitted to external services

### Best Practices
1. **Review Configuration**: Validate MCP server source before deployment
2. **Tool Restrictions**: Use `"tools": ["check_version_tool", "scan_java_project_tool"]` to limit available tools if needed
3. **Environment Isolation**: MCP servers run in isolated environments

## Troubleshooting

### Common Issues

**Configuration Not Loading**
- Verify JSON syntax is valid
- Check repository permissions for Copilot configuration
- Ensure MCP server repository is accessible

**Firewall Blocking Domain Access**
- Check that `COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS` variable is set in repository settings
- Verify the variable contains: `community.opengroup.org,repo1.maven.org,central.maven.org,repo.maven.apache.org,plugins.gradle.org`
- If manual setup is needed, go to Settings → Secrets and variables → Actions → Variables
- Look for firewall warnings in pull request comments from Copilot

**Tools Not Available**
- Check Copilot agent logs in repository settings
- Verify `uvx` is available in the GitHub Actions environment
- Confirm network access to the MCP server repository

**Performance Issues**
- Large projects may require timeout adjustments
- Consider using batch processing tools for multiple dependencies
- Monitor resource usage in workflow logs

### Debugging Steps

1. **Validate Configuration**:
   ```bash
   # Test MCP server locally (if you have Python 3.12+)
   uvx mvn-mcp-server
   ```

2. **Check Logs**:
   - Repository Settings → Copilot → View logs
   - Look for MCP server initialization messages

3. **Test Integration**:
   - Create simple issue: "Check Maven dependencies"
   - Assign to `@copilot`
   - Verify tool usage in response

## Template Integration

**Manual Configuration Required**: MCP configuration cannot be automated via GitHub APIs and must be configured manually in each fork repository's settings. The initialization workflow creates an issue with detailed setup instructions.

### Related Workflows
- **init-complete.yml**: Creates an issue with MCP configuration instructions after repository setup
- **sync.yml**: Enhanced with dependency analysis capabilities when MCP is configured
- **build.yml**: Can leverage security scanning for build decisions when MCP is configured

## Future Enhancements

Planned improvements for MCP integration:
- Additional MCP servers for OSDU-specific tooling
- Integration with release planning workflows
- Enhanced conflict resolution with dependency analysis
- Automated security policy enforcement

## Support

For MCP-related issues:
1. Check the [Maven MCP Server repository](https://pypi.org/project/mvn-mcp-server/) for updates
2. Review GitHub's [MCP documentation](https://docs.github.com/en/enterprise-cloud@latest/copilot/customizing-copilot/extending-copilot-coding-agent-with-mcp)
3. Create an issue with the `mcp-integration` label