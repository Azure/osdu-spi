# Configure MCP Server for GitHub Copilot Agent

To enable the Maven MCP Server for GitHub Copilot Agent in this repository, you need to manually configure it in the repository settings.

## Configuration Steps

1. **Navigate to Repository Settings**:
   - Go to your repository on GitHub.com
   - Click on **Settings** (you must be a repository admin)
   - In the left sidebar under "Code & automation", click **Copilot** → **Copilot agent**

2. **Add MCP Configuration**:
   - Scroll to the **MCP configuration** section
   - Replace the existing JSON with:

```json
{
  "mcpServers": {
    "mvn-mcp-server": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mvn-mcp-server"],
      "tools": []
    }
  }
}
```

3. **Save Configuration**:
   - The configuration will be validated when you save
   - If validation passes, the MCP server will be available to GitHub Copilot Agent

## What This Enables

The Maven MCP Server provides GitHub Copilot Agent with capabilities to:
- Analyze Maven project structures
- Understand dependencies and build configurations
- Provide context-aware assistance for Java/Maven projects
- Help with build issues and dependency management

## Verification

After configuration, you can verify the setup by:
1. Assigning an issue to `@copilot`
2. The agent should have enhanced Maven project understanding

## Manual Configuration Required

⚠️ **Important**: This configuration cannot be automated via API. Repository administrators must configure it manually in the GitHub UI.

---

Close this issue after completing the MCP configuration.