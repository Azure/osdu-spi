# Upstream Synchronization Workflow

🧠 **AI-powered sync** | 🔁 **Three-branch safety** | 🚧 **Human-reviewed conflict resolution** | 🔄 **Duplicate prevention**

This workflow regularly syncs changes from the upstream repository, which often include unconventional or inconsistent commit messages. Rather than preserving those commits as-is, the workflow uses AI to analyze the incoming changeset (via a git diff) and generate a single, conventional meta-commit that summarizes the entire upstream changeset—replacing the original, often inconsistent commits with a standardized summary. The AI classifies the changes (e.g., feat, fix, chore) and creates a detailed, multi-line commit message that adheres to conventional commit standards. A three-branch strategy (`fork_upstream` → `fork_integration` → `main`) is used to isolate changes, manage potential conflicts safely, and generate pull requests automatically. **The workflow now includes intelligent duplicate prevention** to avoid creating multiple PRs and issues for the same upstream state.

## Duplicate Prevention Architecture

### sync-state-manager Action
The workflow integrates a custom GitHub Action (`sync-state-manager`) that provides comprehensive duplicate detection and state management:

**Key Capabilities:**
- **Upstream SHA Tracking**: Compares current upstream state with last synced state
- **Existing PR Detection**: Queries GitHub API for open sync PRs with `upstream-sync` label
- **Branch Management**: Updates existing sync branches instead of creating new ones
- **Abandoned Branch Cleanup**: Automatically removes stale sync branches (>24h old, no associated PR)
- **State Persistence**: Uses git config to store sync state between workflow runs

### Decision Matrix Implementation
The action implements a smart decision matrix:

```yaml
Decision Logic:
  - No existing PR + Upstream changed → Create new PR and issue
  - Existing PR + Upstream unchanged → Add reminder comment
  - Existing PR + Upstream changed → Update existing branch and PR
  - No existing PR + Upstream unchanged → No action needed
```

### State Management
**Storage Method**: Git config variables scoped to repository
- `sync.last-upstream-sha`: Last successfully processed upstream SHA
- `sync.current-pr-number`: Active sync PR number (if any)
- `sync.current-issue-number`: Active tracking issue number (if any)
- `sync.last-sync-timestamp`: Timestamp of last sync attempt

**Persistence**: Automatic across workflow runs
**Cleanup**: Automatic when PRs/issues are closed or merged

## Three-Branch Strategy

The workflow uses a three-branch approach to ensure safe integration:

```mermaid
graph TD
    A[Upstream Repo] --> B[fork_upstream]
    B --> C[fork_integration]
    C --> D[main]
    style A fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    style B fill:#fff3e0,stroke:#e65100,stroke-width:2px  
    style C fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style D fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
```

- **fork_upstream**: Mirror of upstream, updated first
- **fork_integration**: Conflict resolution and testing
- **main**: Your stable production branch

## Key Benefits
- **Automated Scheduled Sync**: No manual intervention for clean merges
- **Conflict Safety**: Conflicts isolated and handled safely
- **AI-Enhanced Analysis**: Intelligent PR descriptions and conflict categorization
- **Complete Audit Trail**: Full tracking of all changes and decisions

## Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| **Schedule** | `0 0 * * *` | Daily at midnight UTC (customizable) |
| **Diff Size Limit** | `20,000 lines` | Maximum diff size for AI analysis |
| **AI Provider** | Claude (Anthropic) | Primary AI service for PR descriptions |
| **Auto-merge** | Disabled | Automatic merging for small changes |
| **Conflict Timeout** | 6 hours | How long before monitor auto-triggers cascade |
| **Retry Attempts** | 3 | Network operation retry count |

💡 **AI Enhancement**: To enable AI-powered PR descriptions, configure an `ANTHROPIC_API_KEY` secret in your repository settings. This provides intelligent analysis of upstream changes with structured commit summaries. Other AI providers can be configured as alternatives.

### Workflow Triggers
- **Automatic**: Daily at midnight UTC
- **Manual**: Click "Run workflow" in GitHub Actions tab
- **API**: Trigger via GitHub REST ∏API

### Required Permissions
The workflow needs these GitHub permissions:
- `contents: write` - Update repository files and branches
- `pull-requests: write` - Create and manage pull requests
- `issues: write` - Create tracking issues for conflicts

## How It Works

### The Happy Path (No Conflicts)
1. **Check for Changes**: Workflow fetches upstream and compares with your fork
2. **Create Sync Branch**: If changes exist, creates a dated sync branch
3. **AI Analysis**: Generates intelligent PR description with change summary
4. **Create PR**: Opens pull request from sync branch to `fork_upstream`
5. **Human Review**: Team reviews and merges the PR
6. **Cascade**: Manual or automatic cascade moves changes to `main`

### When Conflicts Occur
1. **Conflict Detection**: Workflow identifies merge conflicts during integration
2. **Create Conflict PR**: Opens PR with conflict markers for manual resolution
3. **Create Tracking Issue**: Detailed issue with step-by-step resolution instructions
4. **Human Resolution**: Developer resolves conflicts and updates PR
5. **Continue Process**: Once resolved, normal cascade process continues

```mermaid
flowchart TD
    A[Daily Trigger] --> B[Check Upstream]
    B --> C{Changes Found?}
    C -->|No| D[Exit Clean]
    C -->|Yes| E[Create Sync Branch]
    E --> F{Conflicts?}
    F -->|No| G[AI-Enhanced PR]
    F -->|Yes| H[Conflict PR + Issue]
    G --> I[Human Review]
    H --> J[Manual Resolution]
    I --> K[Merge to fork_upstream]
    J --> K
    K --> L[Cascade to main]
```

### Immediate Actions
When the workflow detects conflicts, it automatically:

1. **Creates a Conflict Pull Request**
   - Contains the conflicted files with merge markers
   - Targets the `fork_integration` branch for safe resolution
   - Labeled with `conflict`, `upstream-sync`, `human-required`

2. **Creates a Tracking Issue**
   - Comprehensive resolution instructions
   - Links to the conflict PR
   - Complete process overview with checkboxes
   - Labeled with `conflict`, `human-required`, `high-priority`

### Your Resolution Steps

#### Step 1: Review the Conflict
```bash
# Clone the conflict branch locally
git checkout sync/upstream-YYYYMMDD-HHMMSS

# See which files have conflicts
git status
```

#### Step 2: Resolve Conflicts
- Open conflicted files in your preferred merge tool
- Choose between `<<<<<<< HEAD` (your changes) and `>>>>>>> upstream` (their changes)
- Or combine both as appropriate for your use case
- Remove conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)

#### Step 3: Test and Commit
```bash
# Test your changes
mvn test  # or your project's test command

# Commit the resolution
git add .
git commit -m "resolve: merge conflicts from upstream sync"
git push origin sync/upstream-YYYYMMDD-HHMMSS
```

#### Step 4: Complete the Process
1. Update the conflict PR with your resolution
2. Request review from team members
3. Once approved, merge the PR
4. Manually trigger the cascade workflow (or wait for automatic trigger)

### Getting Help
- Conflict resolution templates in `.github/` directory
- Issue tracking provides complete guidance
- Team members can assist via PR reviews
- [Conflict management documentation](adr/005-conflict-management.md)

## Handling Human-Required Tasks

When you see a sync issue labeled `human-required`, follow this decision tree:

**Clean PR** → Review → Merge → Cascade  
**Conflict PR** → Resolve Locally → Push → Review → Merge → Cascade

### For Clean Syncs (No Conflicts)
1. **Review the PR**: Click the link in the tracking issue
2. **Check AI Summary**: Review the AI-generated description of changes
3. **Verify No Breaking Changes**: Look for any compatibility issues
4. **Merge the PR**: Approve and merge to `fork_upstream` branch
5. **Trigger Cascade**: 
   - Go to Actions → Cascade Integration workflow
   - Enter the issue number from the tracking issue
   - Click "Run workflow"
6. **Monitor Progress**: Check back in 15-30 minutes for completion

### For Conflict Syncs
1. **Read the Conflict Issue**: Complete step-by-step instructions provided
2. **Checkout the Branch**: Follow the git commands in the issue
3. **Resolve Conflicts**: Use your IDE's merge tools or manual editing
4. **Test Thoroughly**: Run your test suite to ensure stability
5. **Push Resolution**: Commit and push your conflict resolution
6. **Update PR**: The conflict PR will automatically update
7. **Request Review**: Get team approval for your resolution
8. **Merge and Cascade**: Same process as clean syncs after merge

### Safety Features
- **6-Hour Monitor**: If you miss triggering the cascade, automation kicks in
- **Branch Protection**: Prevents accidental damage to stable branches
- **Complete Audit Trail**: Every action tracked in the issue comments
- **Rollback Support**: Can revert to previous stable state if needed

## Monitoring and Troubleshooting

### Finding Your Sync Tasks
Use these GitHub issue filters to find items needing attention:

| Filter | Purpose |
|--------|---------|
| [`label:human-required label:upstream-sync`](../../issues?q=is:open+label:human-required+label:upstream-sync) | All sync items needing review |
| [`label:conflict label:high-priority`](../../issues?q=is:open+label:conflict+label:high-priority) | Urgent conflicts requiring resolution |
| [`label:human-required`](../../issues?q=is:open+label:human-required) | All items across workflows needing attention |

### Common Issues and Solutions

#### "No upstream changes detected"
- **Cause**: Your fork is already up to date
- **Action**: No action needed, workflow will exit cleanly

#### "Failed to fetch upstream"
- **Cause**: Network issues or incorrect `UPSTREAM_REPO_URL`
- **Action**: Check repository secrets and network connectivity

#### "AI description generation failed"
- **Cause**: API key issues or service unavailable
- **Action**: PR created with standard template, no impact on functionality

#### "Cascade workflow not triggered"
- **Cause**: Manual trigger missed
- **Action**: Monitor detects and auto-triggers within 6 hours

### Performance Expectations
- **Typical Sync Time**: 2-5 minutes for clean merges
- **Large Repository Sync**: Up to 15 minutes for repos with extensive history
- **AI Description Generation**: Adds 30-60 seconds when enabled
- **Conflict Resolution**: Variable based on complexity (30 minutes to 2 hours)

## Customization Options

### Changing the Sync Schedule
Edit `.github/workflows/sync.yml`:
```yaml
# Weekly instead of daily
- cron: '0 2 * * 1'  # Monday 2 AM

# Multiple times per day
- cron: '0 0,12 * * *'  # Midnight and noon
```

### Adjusting Diff Size Limits
For larger repositories, increase the AI analysis threshold:
```yaml
env:
  DIFF_SIZE_LIMIT: 50000  # Analyze larger diffs
```

### Disabling AI Enhancement
Remove AI API keys to use standard PR templates:
```yaml
# Remove these secrets to disable AI
# ANTHROPIC_API_KEY
# AZURE_API_KEY  
# OPENAI_API_KEY
```

### Custom Conflict Handling
Modify templates in `.github/` directory:
- `conflict_pr_template.md` - Conflict PR description
- `conflict_issue_template.md` - Resolution issue template

## Architecture References

For deeper technical understanding:
- [ADR-001: Three-Branch Strategy](adr/001-three-branch-strategy.md) - Core branching approach
- [ADR-020: Human-Required Labels](adr/020-human-required-label-strategy.md) - Task assignment strategy
- [ADR-023: Meta Commit Strategy](adr/023-meta-commit-strategy-for-release-please.md) - Release integration
- [Product Architecture](product-architecture.md#synchronization) - Complete system overview

---

*For setup help, see the [initialization workflow](init-workflow.md). For cascade process details, see the [cascade workflow](cascade-workflow.md).*

⬆️ [Back to top](#upstream-synchronization-workflow)