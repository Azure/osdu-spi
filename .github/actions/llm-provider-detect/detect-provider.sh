#!/usr/bin/env bash
#
# LLM Provider Detection Script
#
# Detects available LLM providers in priority order:
#   1. Azure Foundry (if AZURE_API_KEY and AZURE_API_BASE are set)
#   2. Fallback (no LLM available)
#
# Outputs (via GITHUB_OUTPUT):
#   use_llm: "true" or "false"
#   llm_model: "azure" or ""
#
# Usage:
#   export AZURE_API_KEY="your_key"
#   export AZURE_API_BASE="https://your-instance.openai.azure.com"
#   ./detect-provider.sh

set -euo pipefail

# Initialize outputs
USE_LLM=false
LLM_MODEL=""

# Check Azure Foundry
if [[ -n "${AZURE_API_KEY:-}" ]] && [[ -n "${AZURE_API_BASE:-}" ]]; then
  echo "✓ Detected Azure Foundry provider"
  USE_LLM=true
  LLM_MODEL="azure"
else
  echo "ℹ No Azure Foundry provider detected (will use fallback descriptions)"
  USE_LLM=false
  LLM_MODEL=""
fi

# Output to GITHUB_OUTPUT if running in GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "use_llm=$USE_LLM" >> "$GITHUB_OUTPUT"
  echo "llm_model=$LLM_MODEL" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for local testing
echo "use_llm=$USE_LLM"
echo "llm_model=$LLM_MODEL"