# ADR-016: Initialization Security Handling

## Status
Accepted

## Context
Many upstream repositories contain secrets or sensitive data in their git history. GitHub's push protection blocks these commits from being pushed, which prevents the initialization workflow from creating the `fork_upstream` branch during repository setup.

Organizations can also enforce push protection at the organization level, which repository settings cannot override.

## Decision
Handle push protection during initialization by detecting the block from the push output, guiding the user through GitHub's secret allowlist, and retrying:

1. **Detection**: parse the failed push output for secret scanning violations and extract the allowlist URLs GitHub reports
2. **Guidance**: open an escalation issue listing every allowlist URL and the manual alternatives, and comment on the initialization issue with the retry instructions
3. **Retry**: the user allowlists the secrets and comments the upstream URL again, which re-runs initialization

Push protection is never disabled by the workflow. The repository's security settings are left as configured.

## Implementation

### 1. Detection and escalation
The `secret-push-handler` local action (`.github/local-actions/secret-push-handler/`) wraps the push. On a secret scanning rejection it extracts the allowlist URLs (handling ANSI escape codes), creates an escalation issue labeled `escalation` with the URLs and resolution options, and comments on the initialization issue with next steps. Any other push failure is reported as an ordinary error.

### 2. Retry through the filter engine
Resolution is allowlist plus retry: after the reported secrets are allowlisted, commenting on the initialization issue re-runs `init-complete.yml`, which regenerates `fork_upstream` through the upstream filter engine (ADR-038) and pushes again. An existing partial branch becomes the base of an ordinary incremental generation, so the retry converges.

`fork_upstream` must never be recreated directly from `upstream/$DEFAULT_BRANCH`: a manual push of the verbatim upstream ref would silently undo the filtered model.

## Manual Resolution Options

The escalation issue offers three paths:

1. **Secret allowlist URLs**: use GitHub's official mechanism to allow each reported secret
2. **Organization admin action**: temporarily disable push protection at the organization level
3. **Manual initialization**: clone locally and use `git push --no-verify` with appropriate permissions

## Consequences

Initialization of an upstream with secrets in history requires one manual round trip through the allowlist before the retry succeeds. Organization-level protection is respected, not bypassed. All later operations run with the repository's security features unchanged.

## Alternatives Considered

1. **Simple retry logic**: insufficient; the block does not clear on its own
2. **History rewriting**: would break synchronization with upstream
3. **Forking without history**: would lose the upstream commit history
4. **Requiring pre-initialization setup**: would complicate the user experience

---

[← ADR-015](015-template-workflows-separation-pattern.md) | :material-arrow-up: [Catalog](index.md) | [ADR-018 →](018-fork-resources-staging-pattern.md)
