#!/usr/bin/env bash
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Copies fork-specific resources from .github/fork-resources/ to their final
# locations and removes template-only files per sync-config.json.
#
# Environment:
#   UPSTREAM_REPO_URL - derives the service slug for <service> substitution
#                       (falls back to the repository variable via gh when unset)

set -euo pipefail

echo "Deploying fork-specific resources..."

# An explicit fork_owned list in the filter config names the fork-owned paths the
# Dependabot, CODEOWNERS and CONTRIBUTING.md templates otherwise assume.
FILTER_CONFIG=".github/upstream-filter.yml"
RENDER=".github/actions/upstream-filter/fork_resources.py"
FORK_OWNED_EXPLICIT=false
if [[ -f "$FILTER_CONFIG" && -f "$RENDER" ]]; then
  explicit_rc=0
  python3 "$RENDER" explicit --config "$FILTER_CONFIG" || explicit_rc=$?
  case "$explicit_rc" in
    0) FORK_OWNED_EXPLICIT=true; echo "Fork-owned paths come from fork_owned in $FILTER_CONFIG" ;;
    1) ;;
    *) echo "ERROR: $FILTER_CONFIG could not be read for fork_owned"; exit 1 ;;
  esac
fi

UPSTREAM_URL="${UPSTREAM_REPO_URL:-$(gh variable get UPSTREAM_REPO_URL 2>/dev/null || true)}"

# Renders a fork resource from stdin to stdout; passes it through when fork_owned is unset.
render() {
  local kind="$1"
  if [[ "$FORK_OWNED_EXPLICIT" == "true" ]]; then
    python3 "$RENDER" "$kind" --config "$FILTER_CONFIG" --checkout .
  else
    cat
  fi
}

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
  if [[ -n "$UPSTREAM_URL" ]]; then
    SERVICE_SLUG=$(basename "${UPSTREAM_URL%.git}")
    echo "Derived service slug: $SERVICE_SLUG"
  fi

  if grep -q "<service>" ".github/fork-resources/dependabot.yml" && [[ -z "$SERVICE_SLUG" ]]; then
    echo "ERROR: dependabot.yml uses the <service> placeholder but UPSTREAM_REPO_URL is not available"
    exit 1
  fi

  SERVICE_ESCAPED=${SERVICE_SLUG//&/\\&}
  dependabot_rc=0
  sed "s|<service>|$SERVICE_ESCAPED|g" ".github/fork-resources/dependabot.yml" | render dependabot > ".github/dependabot.yml" || dependabot_rc=$?
  case "$dependabot_rc" in
    0) git add ".github/dependabot.yml" ;;
    3)
      echo "::warning::No fork_owned tree holds a pom.xml, so Dependabot has no Maven directory to watch; .github/dependabot.yml not planted"
      rm -f ".github/dependabot.yml"
      ;;
    *) echo "ERROR: rendering .github/dependabot.yml failed"; exit 1 ;;
  esac
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

# Replaces the template's own guide at init; sync-template only plants it when missing.
if [[ -f ".github/fork-resources/CONTRIBUTING.md" ]]; then
  echo "Installing fork contributing guide..."
  render contributing < ".github/fork-resources/CONTRIBUTING.md" > "CONTRIBUTING.md"
  git add "CONTRIBUTING.md"
fi

# Upstream's README is stripped from fork_upstream, so init seeds the fork's own from the skeleton.
if [[ -f ".github/fork-resources/README.md" ]]; then
  echo "Installing fork README skeleton..."
  cp ".github/fork-resources/README.md" "README.md"
  git add "README.md"
fi

if [[ -d ".github/fork-resources/ISSUE_TEMPLATE" ]]; then
  echo "Installing fork-specific issue templates..."
  mkdir -p ".github/ISSUE_TEMPLATE"
  cp -r ".github/fork-resources/ISSUE_TEMPLATE/"* ".github/ISSUE_TEMPLATE/"
  git add ".github/ISSUE_TEMPLATE/"
fi

# Fork-owned once planted, like the filter config: a file already on main wins.
if [[ -f ".github/fork-resources/CODEOWNERS" ]] && [[ ! -f ".github/CODEOWNERS" ]]; then
  # A single default person would be unable to approve their own PRs, so there is no default.
  OWNERS="$(gh variable get CODEOWNERS 2>/dev/null || true)"
  # The fork's own Azure module names the prefix to protect; the filter's service key is the
  # fallback when that tree is absent or ambiguous.
  CODEOWNERS_SERVICE=""
  azure_dirs=(provider/*-azure/)
  if [[ ${#azure_dirs[@]} -eq 1 && -d "${azure_dirs[0]}" ]]; then
    CODEOWNERS_SERVICE="${azure_dirs[0]#provider/}"; CODEOWNERS_SERVICE="${CODEOWNERS_SERVICE%-azure/}"
  fi
  if [[ ! "$CODEOWNERS_SERVICE" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    CODEOWNERS_SERVICE="$(sed -n "s/^service:[[:space:]]*[\"']\{0,1\}\([a-z0-9][a-z0-9-]*\)[\"']\{0,1\}[[:space:]]*\(#.*\)\{0,1\}$/\1/p" .github/upstream-filter.yml 2>/dev/null | head -1 || true)"
  fi
  CODEOWNERS_TEMPLATE="$(mktemp)"
  render codeowners < ".github/fork-resources/CODEOWNERS" > "$CODEOWNERS_TEMPLATE"
  if [[ -z "$CODEOWNERS_SERVICE" ]] && grep -v '^#' "$CODEOWNERS_TEMPLATE" | grep -q "<service>"; then
    echo "::warning::CODEOWNERS not planted: no provider/<service>-azure module and no valid service key in .github/upstream-filter.yml"
  elif [[ -z "$OWNERS" ]]; then
    echo "::warning::CODEOWNERS not planted: set the CODEOWNERS repository variable to a team with write access and the next template sync plants it"
  elif [[ "$OWNERS" != @* ]]; then
    echo "::warning::CODEOWNERS not planted: owners must be @user or @org/team handles, got '$OWNERS'"
  else
    echo "Installing CODEOWNERS owned by $OWNERS..."
    OWNERS_ESCAPED=${OWNERS//&/\\&}; OWNERS_ESCAPED=${OWNERS_ESCAPED//|/\\|}
    sed "s|<owners>|$OWNERS_ESCAPED|g; s|<service>|${CODEOWNERS_SERVICE//&/\\&}|g" "$CODEOWNERS_TEMPLATE" > ".github/CODEOWNERS"
    git add ".github/CODEOWNERS"
  fi
fi

# Fork-owned once planted, like CODEOWNERS; sync-template plants it when missing.
if [[ -f ".github/fork-resources/NOTICE-OSDU-SPI" ]] && [[ ! -f "NOTICE-OSDU-SPI" ]]; then
  if [[ -z "$UPSTREAM_URL" ]]; then
    echo "::warning::NOTICE-OSDU-SPI not planted: UPSTREAM_REPO_URL is not available; the next template sync plants it"
  else
    NOTICE_RENDERED="$(mktemp)"
    notice_rc=0
    python3 "$RENDER" notice --upstream-url "$UPSTREAM_URL" --checkout . \
      < ".github/fork-resources/NOTICE-OSDU-SPI" > "$NOTICE_RENDERED" 2> "$NOTICE_RENDERED.err" || notice_rc=$?
    while IFS= read -r line; do
      case "$line" in "warning: "*) echo "::warning::NOTICE-OSDU-SPI: ${line#warning: }" ;; *) echo "$line" ;; esac
    done < "$NOTICE_RENDERED.err"
    case "$notice_rc" in
      0) echo "Installing NOTICE-OSDU-SPI..."; mv "$NOTICE_RENDERED" "NOTICE-OSDU-SPI"; git add "NOTICE-OSDU-SPI" ;;
      4) echo "::warning::NOTICE-OSDU-SPI not planted: no Java source carries a copyright header" ;;
      *) echo "::warning::NOTICE-OSDU-SPI not planted: rendering failed (exit $notice_rc); the next template sync retries" ;;
    esac
    rm -f "$NOTICE_RENDERED" "$NOTICE_RENDERED.err"
  fi
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