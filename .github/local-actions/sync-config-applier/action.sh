#!/bin/bash
# Copies the files, directories, and tracking files that sync-config.json names
# from the source branch into the current branch and commits them.
#
# Inputs (via environment):
#   SYNC_CONFIG_PATH - sync configuration JSON
#   SOURCE_BRANCH - branch to copy from (typically main)
#   TEMPLATE_REPO_URL - template repository, seeds .template-sync-commit
#
# Outputs (to GITHUB_OUTPUT):
#   files_copied, directories_copied, workflows_copied, tracking_files_created

set -euo pipefail

SYNC_CONFIG_PATH="${SYNC_CONFIG_PATH:-.github/sync-config.json}"
SOURCE_BRANCH="${SOURCE_BRANCH:-main}"
TEMPLATE_REPO_URL="${TEMPLATE_REPO_URL:-}"

FILES_COPIED=0
DIRECTORIES_COPIED=0
WORKFLOWS_COPIED=0
TRACKING_FILES_CREATED=0

echo "Fetching sync configuration from $SOURCE_BRANCH..."
git checkout "$SOURCE_BRANCH" -- "$SYNC_CONFIG_PATH"

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

echo "::notice::Workflow deployment deferred to post-merge step to avoid GitHub App permission issues"
echo "::notice::Template remote configuration will be handled by sync-template workflow"

echo "Initializing tracking files..."
TRACKING_FILES=$(jq -r '.sync_rules.tracking_files[] | select(.auto_create == true) | .path' "$SYNC_CONFIG_PATH")
for tracking_file in $TRACKING_FILES; do
    echo "Initializing tracking file: $tracking_file"
    mkdir -p "$(dirname "$tracking_file")"

    if [[ "$tracking_file" == ".github/.template-sync-commit" ]]; then
        if [[ -n "$TEMPLATE_REPO_URL" ]]; then
            echo "  Fetching current template commit from $TEMPLATE_REPO_URL..."
            if git remote get-url template >/dev/null 2>&1; then
                git remote set-url template "$TEMPLATE_REPO_URL"
            else
                git remote add template "$TEMPLATE_REPO_URL"
            fi
            if git fetch template main --depth=1 2>/dev/null; then
                TEMPLATE_SHA=$(git rev-parse template/main 2>/dev/null || echo "")
                if [[ -n "$TEMPLATE_SHA" ]]; then
                    echo "$TEMPLATE_SHA" > "$tracking_file"
                    echo "  ✓ Initialized with current template commit: $TEMPLATE_SHA"
                else
                    echo "" > "$tracking_file"
                    echo "  ⚠️ Could not get template commit, initialized empty"
                fi
            else
                echo "" > "$tracking_file"
                echo "  ⚠️ Could not fetch template, initialized empty (will bootstrap on first sync)"
            fi
        else
            echo "" > "$tracking_file"
            echo "  ⚠️ No template URL provided, initialized empty (will bootstrap on first sync)"
        fi
    else
        echo "" > "$tracking_file"
        echo "  ✓ Created empty tracking file"
    fi

    git add "$tracking_file"
    TRACKING_FILES_CREATED=$((TRACKING_FILES_CREATED + 1))
done

git add .github
git commit -m "chore: copy configuration and workflows from main branch"

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