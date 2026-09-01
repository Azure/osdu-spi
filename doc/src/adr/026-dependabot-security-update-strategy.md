# ADR-026: Dependabot Security Update Strategy

## Status
**Accepted** - 2025-10-01
**Updated** - 2025-10-24 (Separation of Concerns Architecture)
**Updated** - 2025-10-28 (Removed pip/doc from template to prevent fork caching issues)
**Updated** - 2025-12-19 (Changed Maven schedule from weekly to daily for faster rebasing)

## Context

Forks of OSDU services need dependency updates that arrive promptly, do not break compatibility with upstream, and are validated before merge. The engineering system (workflows, actions, the Dockerfile) is maintained in the template and reaches forks through template sync, so a fork's own Dependabot must not also scan `.github`: doing so produced duplicate PRs and a race during initialization, when a fork briefly inherits the template's configuration before `deploy-fork-resources.sh` replaces it.

## Decision

Dependabot is split by ownership:

1. **The template owns the engineering system.** The template's `.github/dependabot.yml` scans GitHub Actions under `.github` and the base image in `build/Dockerfile`.
2. **Forks own application code.** The fork configuration deployed from `.github/fork-resources/dependabot.yml` scans Maven only.
3. **Template sync carries platform updates.** Action and Dockerfile bumps merged in the template reach forks through `sync-template.yml`, never through a fork's Dependabot.
4. **Conservative policy.** Fork Maven updates are patch-only; build tooling is pinned by hand.
5. **Grouped updates** reduce PR count.

### Auto-rebase

Dependabot rebases its open PRs on the daily check, on conflict with the target branch, and when a closed PR is reopened. The schedule was moved from weekly to daily because PRs against a busy `pom.xml` went stale for up to a week. `@dependabot rebase` on a PR forces an immediate rebase.

## Alternatives Considered

Disabling Dependabot leaves security fixes to manual monitoring. Allowing minor and major updates broke compatibility with upstream OSDU too often. Security-only updates accumulate technical debt. All three were rejected in favour of the patch-only, grouped policy.

## Implementation

**Template repository** (`.github/dependabot.yml`): two ecosystems, both targeting `main` with the `dependencies` label and a limit of 5 open PRs.

- `github-actions` on `/.github`, daily at 08:00, all actions grouped, minor and patch only, with a 7-day cooldown
- `docker` on `/build`, daily at 08:30, grouped, for the base image digest in the canonical Dockerfile ([ADR-037](037-engineering-system-owns-service-dockerfile.md)); the App Insights agent is an `ADD` with a checksum rather than a `FROM`, so its bump stays manual

There is no pip ecosystem for `doc/`. A fork inherits this file until `deploy-fork-resources.sh` replaces it, and Dependabot caches the ecosystem list, so a `doc/` entry made forks fail on a directory they do not have.

**Fork repositories** (`.github/fork-resources/dependabot.yml`, deployed to `.github/dependabot.yml`): one `maven` ecosystem, daily at 09:00, targeting `main` with the `dependencies` label.

- Directories: `/`, `/*-core`, `/*-acceptance-test`, `/provider/*-azure`, `/testing`, `/testing/*-test-core`, `/testing/*-test-azure`
- Minor and major updates ignored for every dependency
- Build tooling ignored entirely: JaCoCo, git-commit-id, Lombok, Maven plugins, the Spring Boot Maven plugin
- Groups: `spring`, `logging`, `jackson`, `azure`

**Validation** (`.github/template-workflows/dependabot-validation.yml`): runs on PRs from `dependabot[bot]` against `main`, `fork_integration`, and `fork_upstream`, skipping `.github` and documentation paths. It builds the Java project, runs a validate-only Docker build, posts a build status comment, and opens an issue labelled `build-failed` when the build fails. There is no auto-approve and no auto-merge; a human merges every Dependabot PR.

### Update flow

```
Template (azure/osdu-spi):
  08:00 → Dependabot scans /.github, opens a grouped actions PR
  08:30 → Dependabot scans /build, opens a base-image PR
         → platform team merges
  next sync-template run → PR in every fork with the updated workflows/Dockerfile

Fork (service repository):
  09:00 → Dependabot scans Maven, opens grouped patch PRs
         → dependabot-validation builds and comments
         → human reviews and merges
```

## Consequences

Forks depend on the template for every workflow and action update. Automated PRs still need review time, and a patch update can conflict with a fork's local modifications. Because only patch updates are automated, minor and major upgrades have to be scheduled by hand.

## Related ADRs

- [ADR-002: GitHub Actions-Based Automation Architecture](002-github-actions-automation.md) - Automation foundation
- [ADR-016: Initialization Security Handling](016-initialization-security-handling.md) - Security considerations
- [ADR-025: Java/Maven Build Architecture](025-java-maven-build-architecture.md) - Build system integration
- [ADR-037: Engineering System Owns Service Dockerfile](037-engineering-system-owns-service-dockerfile.md) - Why the template scans `build/`

## References

- [GitHub Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [GitHub Security Advisories](https://github.com/advisories)
- [Maven Dependency Management](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html)
---

[← ADR-025](025-java-maven-build-architecture.md) | :material-arrow-up: [Catalog](index.md) | [ADR-027 →](027-documentation-generation-strategy.md)
