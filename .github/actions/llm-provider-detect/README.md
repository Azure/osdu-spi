# LLM Provider Detection Action

Detects available LLM providers for AI-enhanced workflow operations.

## Purpose

This action checks for available LLM API credentials and sets outputs that workflows can use to determine whether to use AI-enhanced features or fall back to static descriptions.

## Detection Priority

1. **Azure Foundry** (if `AZURE_API_KEY` and `AZURE_API_BASE` are set)
2. **Fallback** (no LLM available, use static descriptions)

## Outputs

| Output | Description | Values |
|--------|-------------|--------|
| `use_llm` | Whether an LLM provider is available | `true` or `false` |
| `llm_model` | LLM model identifier for aipr tool | `azure` or empty |

## Usage in Workflows

```yaml
- name: Detect LLM provider
  uses: ./.github/actions/llm-provider-detect
  id: llm
  env:
    AZURE_API_KEY: ${{ secrets.AZURE_API_KEY }}
    AZURE_API_BASE: ${{ secrets.AZURE_API_BASE }}

- name: Generate AI-enhanced PR description
  if: steps.llm.outputs.use_llm == 'true'
  run: |
    aipr pr \
      -m ${{ steps.llm.outputs.llm_model }} \
      -b "${{ inputs.base-branch }}" \
      -o "${{ inputs.head-branch }}"

- name: Use fallback description
  if: steps.llm.outputs.use_llm == 'false'
  run: |
    echo "Using static PR description (no LLM available)"
    gh pr create --title "..." --body "$FALLBACK_DESCRIPTION"
```

## Local Testing

### Test with Azure Foundry

```bash
cd .github/actions/llm-provider-detect

# Set Azure Foundry credentials
export AZURE_API_KEY="your_azure_key_here"
export AZURE_API_BASE="https://your-instance.openai.azure.com"

# Run the script
./detect-provider.sh

# Expected output:
# ✓ Detected Azure Foundry provider
# use_llm=true
# llm_model=azure
```

### Test Fallback Scenario

```bash
cd .github/actions/llm-provider-detect

# Unset Azure credentials
unset AZURE_API_KEY
unset AZURE_API_BASE

# Run the script
./detect-provider.sh

# Expected output:
# ℹ No Azure Foundry provider detected (will use fallback descriptions)
# use_llm=false
# llm_model=
```

## Integration with aipr Tool

When Azure Foundry is detected, the `llm_model` output can be used directly with the `aipr` CLI tool:

```bash
# Azure Foundry
aipr pr -m azure -b main -o feature-branch
```

## Implementation Details

- **Script**: `detect-provider.sh` - Bash script with provider detection logic
- **Action**: `action.yml` - Composite action wrapper
- **Outputs**: Sets `GITHUB_OUTPUT` when running in GitHub Actions, prints to stdout for local testing

## Error Handling

- Script uses `set -euo pipefail` for strict error handling
- Uses `${VAR:-}` syntax to safely check undefined variables
- Gracefully falls back when no provider is available (no error, just `use_llm=false`)

## Used By

- `sync.yml` - Upstream synchronization workflow (inline script to be migrated)
- `sync-template.yml` - Template update workflow
- Future AI-enhanced workflows

## Related

- **ADR-013**: Reusable GitHub Actions Pattern
- **ADR-014**: AI-Enhanced Development Workflow Integration
- **ADR-028**: Workflow Script Extraction Pattern