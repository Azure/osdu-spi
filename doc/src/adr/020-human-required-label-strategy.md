# ADR-020: Human-Required Label Strategy

## Status
**Accepted** - 2025-10-01  

## Context

Workflows create issues and pull requests that need human attention. The usual approach assigns them with the `--assignee` flag, which has several problems:

1. **Username resolution**: the GraphQL API requires exact usernames, and an organization name cannot be assigned
2. **Dynamic context**: workflows run under different triggering users and repository owners
3. **API failures**: an invalid username fails the workflow with errors like "Could not resolve to a User with the login of 'organization-name'"
4. **Maintenance**: hardcoded usernames go stale
5. **Template reuse**: a template used across many repositories cannot carry a fixed assignee

The original implementation used patterns like:

```yaml
--assignee "${{ github.repository_owner }}"  # Organization name (invalid)
--assignee "hardcoded-username"              # Brittle
```

These failures blocked automation.

## Decision

Replace assignee-based task management with labels:

1. **No assignees**: remove every `--assignee` flag from automated workflows
2. **`human-required` label**: marks any item that needs a person to act
3. **Label-based filtering**: team members find work by filtering on labels
4. **Labels do not fail**: no username resolution is involved
5. **Combinations**: priority and category labels refine the queue

### Core label

From `.github/labels.json` (managed by ADR-008):

```json
{
  "name": "human-required",
  "description": "Requires human action or approval",
  "color": "fbca04"
}
```

### Supporting labels

- `high-priority`: urgent items
- `conflict`: merge conflicts requiring manual resolution
- `escalation`: items that have exceeded the conflict SLA
- `sync-failed`: failed upstream synchronization
- `template-sync-failed`: failed template synchronization

### Lifecycle labels (ADR-022)

- `upstream-sync`: tracking issue for an upstream synchronization
- `cascade-active`: cascade integration in progress
- `cascade-blocked`: cascade blocked by conflicts or validation failure
- `cascade-failed`: cascade failed; paired with `human-required` until a person clears it
- `cascade-escalated`: conflict older than 48 hours
- `validated`: integration complete
- `template-sync`: template update PRs and issues

### Workflow pattern

Before:

```yaml
ASSIGNEE="${{ github.actor }}"
if gh api users/"$ASSIGNEE" >/dev/null 2>&1; then
  ASSIGNEE_FLAG="--assignee $ASSIGNEE"
else
  ASSIGNEE_FLAG=""
fi

gh issue create --title "..." --body "..." --label "some-label" $ASSIGNEE_FLAG
```

After:

```yaml
gh issue create \
  --title "📥 Upstream Sync Ready for Review - $(date +%Y-%m-%d)" \
  --body "$NOTIFICATION_BODY" \
  --label "upstream-sync,human-required"

# Lifecycle update when the cascade starts
gh issue edit "$ISSUE_NUMBER" \
  --remove-label "human-required" \
  --add-label "cascade-active"
```

### Where the label is used

- `sync.yml`: tracking issue `upstream-sync,human-required`; failure issue `sync-failed,human-required`
- `cascade.yml`: conflict PRs and issues (`conflict,cascade-blocked,high-priority,human-required`), validation failures, held-upstream issues, and failure issues; the label is removed when the cascade starts and re-added on failure
- `cascade-monitor.yml`: escalation issues (`escalation,high-priority,cascade-escalated,human-required`); the recovery job treats the absence of `human-required` on a `cascade-failed` issue as the retry signal
- `sync-template.yml`: the label-configuration issue (`human-required,template-sync`); the template-sync PR itself carries only `template-sync`

### Filtering

```
label:human-required                          # everything needing a person
label:human-required label:high-priority      # urgent
label:human-required label:conflict           # conflicts to resolve
label:upstream-sync label:human-required      # sync awaiting merge and cascade trigger
label:upstream-sync label:cascade-active      # integration in progress
label:upstream-sync label:cascade-blocked     # blocked
```

## Alternatives Considered

1. **Assignee validation with fallbacks**: rejected; complex, still fails in edge cases, and adds API calls.
2. **Assignee from a repository variable**: rejected; still requires a valid username and per-repository setup.
3. **External assignment service**: rejected; extra infrastructure.
4. **Assignment plus labels**: rejected; keeps the assignment failure mode.

## Consequences

Nobody is assigned, so individual accountability depends on team discipline and there are no assignment notifications. Teams filter by label instead. In exchange, issue creation never fails on username resolution and the template works identically in every repository.

## Related Decisions

- [ADR-008: Centralized Label Management Strategy](008-centralized-label-management.md) - Defines how labels are managed
- [ADR-019: Cascade Monitor Pattern](019-cascade-monitor-pattern.md) - Uses `human-required` as the recovery signal
- [ADR-022: Issue Lifecycle Tracking Pattern](022-issue-lifecycle-tracking-pattern.md) - Defines lifecycle label usage

---

[← ADR-019](019-cascade-monitor-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-021 →](021-pull-request-target-trigger-pattern.md)
