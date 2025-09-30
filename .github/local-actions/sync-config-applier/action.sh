#!/bin/bash
# Sync Configuration Applier
#
# Applies sync configuration rules to copy files, workflows, and tracking files
# from the main branch and template repository to the fork_integration branch.
#
# Inputs (via environment):
#   SYNC_CONFIG_PATH - Path to sync configuration JSON file
#   SOURCE_BRANCH - Branch to copy files from (typically 'main')
#   TEMPLATE_REPO_URL - URL of the template repository
#
# Outputs (to GITHUB_OUTPUT and stdout):
#   files_copied=<count> - Number of files successfully copied
#   directories_copied=<count> - Number of directories successfully copied
#   workflows_copied=<count> - Number of workflows successfully copied
#   tracking_files_created=<count> - Number of tracking files initialized

set -euo pipefail

SYNC_CONFIG_PATH="${SYNC_CONFIG_PATH:-.github/sync-config.json}"
SOURCE_BRANCH="${SOURCE_BRANCH:-main}"
TEMPLATE_REPO_URL="${TEMPLATE_REPO_URL}"

if [ -z "$TEMPLATE_REPO_URL" ]; then
    echo "::error::TEMPLATE_REPO_URL is required"
    exit 1
fi

# Counters for output
FILES_COPIED=0
DIRECTORIES_COPIED=0
WORKFLOWS_COPIED=0
TRACKING_FILES_CREATED=0

# Copy files according to sync configuration
echo "Fetching sync configuration from $SOURCE_BRANCH..."
git checkout "$SOURCE_BRANCH" -- "$SYNC_CONFIG_PATH"

# Copy directories that should be synced entirely
echo "Copying directories per sync configuration..."
DIRECTORIES=$(jq -r '.sync_rules.directories[] | .path' "$SYNC_CONFIG_PATH")
for dir in $DIRECTORIES; do
    echo "Copying directory: $dir"
    if git checkout "$SOURCE_BRANCH" -- "$dir/" 2>/dev/null; then
        DIRECTORIES_COPIED=$((DIRECTORIES_COPIED + 1))
    else
        echo "⚠️  Directory $dir not found, skipping"
    fi
done

# Copy individual files
echo "Copying files per sync configuration..."
FILES=$(jq -r '.sync_rules.files[] | .path' "$SYNC_CONFIG_PATH")
for file in $FILES; do
    echo "Copying file: $file"
    if git checkout "$SOURCE_BRANCH" -- "$file" 2>/dev/null; then
        FILES_COPIED=$((FILES_COPIED + 1))
    else
        echo "⚠️  File $file not found, skipping"
    fi
done

# Add template remote to be able to track template updates
echo "Setting up template remote: $TEMPLATE_REPO_URL"
git remote add template "$TEMPLATE_REPO_URL" || true
# Explicitly fetch the main branch to avoid tag ambiguity
git fetch template refs/heads/main:refs/remotes/template/main --depth=1

# Copy fork workflows from template repository
# This must happen before merge to avoid GitHub App workflow permission issues
echo "Copying fork-specific workflows from template repository..."
if git checkout template/main -- .github/template-workflows/ 2>/dev/null; then
    if [ -d ".github/template-workflows" ]; then
        # Ensure workflows directory exists
        mkdir -p .github/workflows

        # Copy workflows and count them
        for workflow in .github/template-workflows/*.yml; do
            if [ -f "$workflow" ]; then
                cp "$workflow" .github/workflows/
                WORKFLOWS_COPIED=$((WORKFLOWS_COPIED + 1))
                echo "  ✓ $(basename "$workflow")"
            fi
        done

        echo "✅ Copied $WORKFLOWS_COPIED workflow(s)"
    else
        echo "⚠️  Warning: .github/template-workflows directory not found in template"
    fi
else
    echo "⚠️  Warning: Failed to checkout template workflows - template/main reference not available"
    echo "This may occur if the template fetch failed. Initialization will continue without copying workflows."
    echo "Fork workflows will need to be added manually from the template repository."
fi

# Initialize tracking files
echo "Initializing tracking files..."
TRACKING_FILES=$(jq -r '.sync_rules.tracking_files[] | select(.auto_create == true) | .path' "$SYNC_CONFIG_PATH")
for tracking_file in $TRACKING_FILES; do
    echo "Initializing tracking file: $tracking_file"
    mkdir -p "$(dirname "$tracking_file")"

    # Special handling for template sync commit file
    if [[ "$tracking_file" == ".github/.template-sync-commit" ]]; then
        # We need to find the template commit that matches our current template files
        # Since we just created this from the template, we can use the template's current HEAD
        # But ideally we'd want the exact commit this was forked from
        # For now, use the current template HEAD as baseline (may include some changes we already have)
        TEMPLATE_BASELINE=$(git rev-parse template/main)
        echo "$TEMPLATE_BASELINE" > "$tracking_file"
        echo "  ✓ Initialized with template commit: $TEMPLATE_BASELINE"
    else
        # For other tracking files, create empty
        echo "" > "$tracking_file"
        echo "  ✓ Created empty tracking file"
    fi

    git add "$tracking_file"
    TRACKING_FILES_CREATED=$((TRACKING_FILES_CREATED + 1))
done

# Commit all copied files including workflows
git add .github
git commit -m "chore: copy configuration and workflows from main branch"

# Output results
echo "files_copied=$FILES_COPIED" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "directories_copied=$DIRECTORIES_COPIED" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "workflows_copied=$WORKFLOWS_COPIED" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "tracking_files_created=$TRACKING_FILES_CREATED" >> "${GITHUB_OUTPUT:-/dev/stdout}"

echo ""
echo "📊 Summary:"
echo "  - Files copied: $FILES_COPIED"
echo "  - Directories copied: $DIRECTORIES_COPIED"
echo "  - Workflows copied: $WORKFLOWS_COPIED"
echo "  - Tracking files created: $TRACKING_FILES_CREATED"
echo ""
echo "✅ Sync configuration applied successfully"