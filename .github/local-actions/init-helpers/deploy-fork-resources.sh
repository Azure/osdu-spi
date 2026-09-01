#!/usr/bin/env bash
#
# Copies fork-specific resources from .github/fork-resources/ to their final
# locations and removes template-only files per sync-config.json.
#
# Environment:
#   UPSTREAM_REPO_URL - derives the service slug for <service> substitution
#                       (falls back to the repository variable via gh when unset)

set -euo pipefail

echo "Deploying fork-specific resources..."

if [[ -f ".github/fork-resources/copilot-instructions.md" ]]; then
  echo "Installing fork-specific copilot instructions..."
  cp ".github/fork-resources/copilot-instructions.md" ".github/copilot-instructions.md"
  git add ".github/copilot-instructions.md"
fi

if [[ -f ".github/fork-resources/dependabot.yml" ]]; then
  echo "Installing fork-specific Dependabot configuration..."

  # Derive the service slug from the upstream URL (e.g. partition), not the
  # checkout directory, which on a runner is the repository name (osdu-spi-partition).
  SERVICE_SLUG=""
  UPSTREAM_URL="${UPSTREAM_REPO_URL:-$(gh variable get UPSTREAM_REPO_URL 2>/dev/null || true)}"
  if [[ -n "$UPSTREAM_URL" ]]; then
    SERVICE_SLUG=$(basename "${UPSTREAM_URL%.git}")
    echo "Derived service slug: $SERVICE_SLUG"
  fi

  if grep -q "<service>" ".github/fork-resources/dependabot.yml" && [[ -z "$SERVICE_SLUG" ]]; then
    echo "ERROR: dependabot.yml uses the <service> placeholder but UPSTREAM_REPO_URL is not available"
    exit 1
  fi

  SERVICE_ESCAPED=${SERVICE_SLUG//&/\\&}
  sed "s|<service>|$SERVICE_ESCAPED|g" ".github/fork-resources/dependabot.yml" > ".github/dependabot.yml"
  git add ".github/dependabot.yml"
fi

if [[ -f ".github/fork-resources/copilot-firewall-config.json" ]]; then
  echo "Installing GitHub Copilot firewall configuration..."
  cp ".github/fork-resources/copilot-firewall-config.json" ".github/copilot-firewall-config.json"
  git add ".github/copilot-firewall-config.json"
fi

if [[ -f ".github/fork-resources/triage.prompt.md" ]]; then
  echo "Installing triage prompt for dependency analysis..."
  mkdir -p ".github/prompts"
  cp ".github/fork-resources/triage.prompt.md" ".github/prompts/triage.prompt.md"
  git add ".github/prompts/triage.prompt.md"
fi

if [[ -d ".github/fork-resources/ISSUE_TEMPLATE" ]]; then
  echo "Installing fork-specific issue templates..."
  mkdir -p ".github/ISSUE_TEMPLATE"
  cp -r ".github/fork-resources/ISSUE_TEMPLATE/"* ".github/ISSUE_TEMPLATE/"
  git add ".github/ISSUE_TEMPLATE/"
fi

if [[ -d ".github/fork-resources" ]]; then
  echo "Removing fork-resources directory after copying..."
  rm -rf ".github/fork-resources"
fi

echo "Cleaning up template development workflows..."

echo "Removing template development workflows..."
rm -f .github/workflows/dev-*.yml

echo "Cleaning up template-workflows directory..."
rm -rf .github/template-workflows/

echo "Cleaning up remaining template-specific files..."

SYNC_CONFIG=".github/sync-config.json"

CLEANUP_DIRS=$(jq -r '.cleanup_rules.directories[]? | .path' "$SYNC_CONFIG" 2>/dev/null || echo "")
for dir in $CLEANUP_DIRS; do
  if [[ -d "$dir" ]]; then
    echo "Removing template directory: $dir"
    rm -rf "$dir"
  fi
done

CLEANUP_FILES=$(jq -r '.cleanup_rules.files[]? | .path' "$SYNC_CONFIG" 2>/dev/null || echo "")
for file in $CLEANUP_FILES; do
  if [[ -f "$file" ]]; then
    echo "Removing template file: $file"
    rm -f "$file"
  fi
done

CLEANUP_WORKFLOWS=$(jq -r '.cleanup_rules.workflows[]? | .path' "$SYNC_CONFIG" 2>/dev/null || echo "")
for workflow in $CLEANUP_WORKFLOWS; do
  if [[ -f "$workflow" ]]; then
    echo "Removing initialization workflow: $workflow"
    rm -f "$workflow"
  fi
done

echo "✅ Fork resources deployed and template files cleaned up"