# Sync Config Applier

Applies sync configuration rules to copy files, workflows, and tracking files from main branch and template repository.

## Usage

```yaml
- name: Apply sync configuration
  uses: ./.github/local-actions/sync-config-applier
  with:
    sync_config_path: '.github/sync-config.json'
    source_branch: 'main'
    template_repo_url: ${{ vars.TEMPLATE_REPO_URL || 'https://github.com/azure/osdu-spi.git' }}
```

## Behavior

- Reads `sync_rules` from sync-config.json
- Copies directories listed in `sync_rules.directories[]`
- Copies individual files from `sync_rules.files[]`
- Sets up template remote for tracking updates
- Copies workflows from `.github/template-workflows/` → `.github/workflows/`
- Initializes tracking files (e.g., `.github/.template-sync-commit`)
  - For `.template-sync-commit`: If `template_repo_url` is provided, fetches the current template commit SHA to initialize the file. This prevents spurious "sync needed" detections on first run.
- Creates commit with all copied content
- Outputs: `files_copied`, `directories_copied`, `workflows_copied`, `tracking_files_created`

## Testing

```bash
cd .github/local-actions/sync-config-applier
git init test-repo && cd test-repo
git checkout -b fork_integration
export SYNC_CONFIG_PATH=".github/sync-config.json"
export SOURCE_BRANCH="main"
export TEMPLATE_REPO_URL="https://github.com/azure/osdu-spi.git"
../action.sh  # Verify outputs
```