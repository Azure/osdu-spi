#!/usr/bin/env bash
#
# Deploy Fork Resources Script
#
# Copies fork-specific resources from .github/fork-resources/ to their final
# locations and cleans up template-specific files.
#
# Resources deployed:
#   - Copilot instructions
#   - Dependabot configuration
#   - Copilot firewall configuration
#   - Triage prompts
#   - VS Code MCP configuration
#   - Issue templates
#   - Copilot setup workflow
#
# Cleanup performed:
#   - fork-resources directory removal
#   - dev-* workflows removal
#   - template-workflows directory removal
#   - Template files per sync-config.json cleanup rules
#
# Post-cleanup seeding:
#   - fork-owned CODEOWNERS rule for /.spi/ (ADR-039)
#
# Arguments:
#   None
#
# Environment Variables:
#   SPI_ENGINEERING_OWNERS  Optional. GitHub team/user that must review `.spi/**`
#                           (for example "@my-org/engineering-system"). When unset or
#                           invalid a documented, commented placeholder is written.
#
# Usage:
#   ./deploy-fork-resources.sh

set -euo pipefail

echo "Deploying fork-specific resources..."

# Copy fork-specific copilot instructions
if [[ -f ".github/fork-resources/copilot-instructions.md" ]]; then
  echo "Installing fork-specific copilot instructions..."
  cp ".github/fork-resources/copilot-instructions.md" ".github/copilot-instructions.md"
  git add ".github/copilot-instructions.md"
fi

# Copy fork-specific Dependabot configuration (language-aware: Java/Maven or Python/uv)
DEPENDABOT_SOURCE=".github/fork-resources/dependabot.yml"
if [[ -f ".github/fork-resources/select-dependabot-config.sh" ]]; then
  DEPENDABOT_SOURCE=$(bash ".github/fork-resources/select-dependabot-config.sh" --print-source)
fi

if [[ -f "$DEPENDABOT_SOURCE" ]]; then
  echo "Installing fork-specific Dependabot configuration from $DEPENDABOT_SOURCE..."

  # Detect service name from repository name
  SERVICE_NAME=$(basename "$(git rev-parse --show-toplevel)")
  echo "Detected service name: $SERVICE_NAME"

  # Copy and replace <service> placeholders, escaping special characters in service name
  SERVICE_ESCAPED=${SERVICE_NAME//&/\\&}
  sed "s|<service>|$SERVICE_ESCAPED|g" "$DEPENDABOT_SOURCE" > ".github/dependabot.yml"
  git add ".github/dependabot.yml"
fi

# Copy GitHub Copilot firewall configuration
if [[ -f ".github/fork-resources/copilot-firewall-config.json" ]]; then
  echo "Installing GitHub Copilot firewall configuration..."
  cp ".github/fork-resources/copilot-firewall-config.json" ".github/copilot-firewall-config.json"
  git add ".github/copilot-firewall-config.json"
fi

# Copy triage prompt file to .github/prompts directory
if [[ -f ".github/fork-resources/triage.prompt.md" ]]; then
  echo "Installing triage prompt for dependency analysis..."
  mkdir -p ".github/prompts"
  cp ".github/fork-resources/triage.prompt.md" ".github/prompts/triage.prompt.md"
  git add ".github/prompts/triage.prompt.md"
fi

# Copy .vscode configuration directory
if [[ -d ".github/fork-resources/.vscode" ]]; then
  echo "Installing .vscode MCP configuration..."
  mkdir -p ".vscode"
  cp -r ".github/fork-resources/.vscode/"* ".vscode/"
  # Force add .vscode files even if gitignore might affect them
  git add -f ".vscode/"
fi

# Copy issue templates
if [[ -d ".github/fork-resources/ISSUE_TEMPLATE" ]]; then
  echo "Installing fork-specific issue templates..."
  mkdir -p ".github/ISSUE_TEMPLATE"
  cp -r ".github/fork-resources/ISSUE_TEMPLATE/"* ".github/ISSUE_TEMPLATE/"
  git add ".github/ISSUE_TEMPLATE/"
fi

# Copy copilot setup steps workflow
if [[ -f ".github/fork-resources/copilot-setup-steps.yml" ]]; then
  echo "Installing GitHub Copilot setup steps workflow..."
  mkdir -p ".github/workflows"
  cp ".github/fork-resources/copilot-setup-steps.yml" ".github/workflows/copilot-setup-steps.yml"
  git add ".github/workflows/copilot-setup-steps.yml"
fi

# Clean up fork-resources directory after copying
if [[ -d ".github/fork-resources" ]]; then
  echo "Removing fork-resources directory after copying..."
  rm -rf ".github/fork-resources"
fi

# Clean up template development workflows
echo "Cleaning up template development workflows..."

# Remove all dev-* workflows (template development only)
echo "Removing template development workflows..."
rm -f .github/workflows/dev-*.yml

# Remove the template-workflows directory (no longer needed)
echo "Cleaning up template-workflows directory..."
rm -rf .github/template-workflows/

# Clean up template files using sync configuration
echo "Cleaning up remaining template-specific files..."

SYNC_CONFIG=".github/sync-config.json"

# Remove directories specified in cleanup rules
CLEANUP_DIRS=$(jq -r '.cleanup_rules.directories[]? | .path' "$SYNC_CONFIG" 2>/dev/null || echo "")
for dir in $CLEANUP_DIRS; do
  if [[ -d "$dir" ]]; then
    echo "Removing template directory: $dir"
    rm -rf "$dir"
  fi
done

# Remove files specified in cleanup rules
CLEANUP_FILES=$(jq -r '.cleanup_rules.files[]? | .path' "$SYNC_CONFIG" 2>/dev/null || echo "")
for file in $CLEANUP_FILES; do
  if [[ -f "$file" ]]; then
    echo "Removing template file: $file"
    rm -f "$file"
  fi
done

# Remove workflows specified in cleanup rules
CLEANUP_WORKFLOWS=$(jq -r '.cleanup_rules.workflows[]? | .path' "$SYNC_CONFIG" 2>/dev/null || echo "")
for workflow in $CLEANUP_WORKFLOWS; do
  if [[ -f "$workflow" ]]; then
    echo "Removing initialization workflow: $workflow"
    rm -f "$workflow"
  fi
done

# Seed the fork-owned CODEOWNERS ownership rule for the service descriptor (ADR-039).
# The template CODEOWNERS was just removed by the cleanup rules above; the fork needs its
# own file so the ruleset's require_code_owner_review can protect `/.spi/`. The owning team
# differs per organization, so it comes from the SPI_ENGINEERING_OWNERS repository variable;
# without it a documented, commented placeholder is written instead of an invalid team.
if [[ -f ".github/scripts/service-config/generate_codeowners.py" ]]; then
  echo "Seeding CODEOWNERS ownership for /.spi/..."
  python3 .github/scripts/service-config/generate_codeowners.py \
    --path CODEOWNERS \
    --owners "${SPI_ENGINEERING_OWNERS:-}"
  git add CODEOWNERS
fi

echo "✅ Fork resources deployed and template files cleaned up"