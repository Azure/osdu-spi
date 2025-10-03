# ADR-021: Pull Request Target Trigger Pattern

## Status
**Accepted** - 2025-10-01

## Context

The cascade-monitor workflow needs to trigger when pull requests are merged into the `fork_upstream` branch to automatically start the cascade integration process. However, the original implementation using the `pull_request` event has a critical limitation:

1. **Missing YAML Problem**: The `pull_request` event requires the workflow file to exist on the target branch (`fork_upstream`), but our workflow files only exist on the `main` branch
2. **PAT Token Dependency**: Current workaround uses `gh workflow run` with a PAT token to trigger cascade, adding complexity
3. **Multiple Failure Points**: The indirect triggering approach can fail at multiple points
4. **Maintenance Overhead**: Two separate workflows (monitor + cascade) increase complexity

The community feedback highlighted that `pull_request_target` is the canonical solution for this exact scenario.

## Decision

Replace the `pull_request` event with `pull_request_target` in the cascade-monitor workflow:

```yaml
on:
  pull_request_target:
    types: [closed]
    branches: [fork_upstream]
```

This single change solves the missing YAML problem because `pull_request_target` always reads the workflow definition from the default branch (`main`) while still providing access to the pull request event payload.

## Rationale

### Why pull_request_target is Superior

1. **Workflow Location**: Always reads from `main` branch, eliminating the missing YAML issue
2. **Same Security Model**: Runs with base repository permissions, identical to current PAT approach
3. **Atomic Operation**: Direct event handling without intermediate steps
4. **Simpler Architecture**: No need for complex workarounds or auxiliary issues
5. **GitHub's Intended Solution**: This is exactly what `pull_request_target` was designed for

### Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **pull_request_target** | • Reads from main<br>• Direct trigger<br>• Simple | • Elevated permissions (same as PAT) |
| Copy YAML to fork_upstream | • Standard trigger | • Duplicate files<br>• Maintenance burden |
| workflow_run | • Works from main | • Fires before merge<br>• Complex logic |
| Issue-close pattern | • Works from main | • Extra complexity<br>• Manual cleanup |
| repository_dispatch | • Explicit control | • Requires PAT<br>• More moving parts |

## Implementation Details

### Minimal Changes Required

Only two lines need to change in cascade-monitor.yml:

1. Change the event trigger:
   ```yaml
   # Before
   pull_request:
   
   # After
   pull_request_target:
   ```

2. Update the job condition:
   ```yaml
   # Before
   github.event_name == 'pull_request'
   
   # After
   github.event_name == 'pull_request_target'
   ```

### Security Considerations

`pull_request_target` runs with write permissions to the base repository, but this is identical to our current approach using PAT tokens. The workflow already includes appropriate safeguards:

- Only triggers on closed PRs
- Checks for merged status
- Validates specific labels
- Limited to fork_upstream branch

## Consequences

### Positive

- **Reliability**: Eliminates the missing YAML problem completely
- **Simplicity**: Removes complex workarounds and reduces failure points
- **Maintainability**: Single clear trigger mechanism
- **Performance**: Direct event handling without intermediate steps
- **Compatibility**: Works with existing sync-template distribution

### Negative

- **Learning Curve**: Team needs to understand `pull_request_target` vs `pull_request`
- **Security Awareness**: Must be careful with untrusted PR content (already handled)

### Neutral

- **Same Security Model**: No change from current PAT-based approach
- **Workflow Count**: Still using cascade-monitor + cascade separation
- **Distribution**: Sync-template handles propagation automatically

## Migration Strategy

1. **Update cascade-monitor.yml**: Change to `pull_request_target` (completed)
2. **Test in Template Repository**: Verify trigger works correctly
3. **Document Change**: Update workflow documentation
4. **Automatic Distribution**: Let sync-template propagate to all forks
5. **Monitor Rollout**: Watch for successful cascade triggers

## Related Decisions

- [ADR-019: Cascade Monitor Pattern](019-cascade-monitor-pattern.md) - Original monitor pattern
- [ADR-001: Three-Branch Fork Management Strategy](001-three-branch-strategy.md) - Branch structure
- [ADR-020: Human-Required Label Strategy](020-human-required-label-strategy.md) - Label-based triggers

## Success Criteria

- Cascade triggers fire 100% reliably when sync PRs merge
- No missing YAML errors in workflow logs
- Existing functionality preserved (health checks, error handling)
- Smooth rollout via sync-template to all repositories
- Clear audit trail in workflow logs

## References

- [GitHub Docs: pull_request_target](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request_target)
- [GitHub Security: pull_request_target](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
- Community feedback on fork management patterns
---

[← ADR-020](020-human-required-label-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-022 →](022-issue-lifecycle-tracking-pattern.md)
