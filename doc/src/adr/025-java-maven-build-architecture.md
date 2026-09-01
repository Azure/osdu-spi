# ADR-025: Java/Maven Build Architecture

## Status
**Accepted** - 2025-10-01; amended 2026-08-30 to reflect public Maven read access

## Context

OSDU services are Java projects built with Maven. Forks created from this template need build automation that resolves dependencies from the community GitLab Maven repository, reports JaCoCo coverage, caches `.m2`, and fits the three-branch strategy. The template had to decide which build system to support and how to implement it once for every fork.

## Decision

Java/Maven is the build architecture:

1. **Java 17 Temurin** as the runtime
2. **Maven** as the build tool
3. **JaCoCo** for coverage reporting
4. **GitLab community Maven repository** for OSDU dependencies, read anonymously
5. **Reusable composite actions** so every fork builds the same way

### Reusable actions

```
.github/actions/
├── java-build/           # Core build logic
├── java-build-status/    # Status reporting with coverage
└── pr-status/            # PR status updates
```

`java-build` takes two optional inputs: `generate_coverage` (default `false`) and `maven_profile`. `build.yml` calls it with no inputs. `validate.yml` passes coverage on for PR events and supplies the `core,azure` profile that restricts the build to the provider-neutral and Azure modules ([ADR-035](035-azure-only-maven-profile.md)). When no profile is given, no `-P` is passed.

### Coverage

JaCoCo is invoked as `org.jacoco:jacoco-maven-plugin:0.8.11:report` from the action and the HTML report is uploaded as an artifact and summarised in the job log. No coverage threshold is enforced; the report is informational.

### Community repository access

When `.mvn/community-maven.settings.xml` is present the action passes it to Maven. The repository at `https://community.opengroup.org/api/v4/groups/17/-/packages/maven` allows anonymous read, so no registry secret is required to build. Publishing happens outside these workflows and needs its own authentication.

### Container images

Building and publishing the service image is a separate concern owned by the `docker-build` action and the canonical `build/Dockerfile` ([ADR-033](033-ghcr-as-service-image-registry.md), [ADR-037](037-engineering-system-owns-service-dockerfile.md)).

## Alternatives Considered

Multi-language support (Python, Node.js) was rejected because OSDU services are Java and the extra surface would be unused. Gradle and Bazel were rejected because upstream is Maven and a conversion would have to be re-done on every sync. Leaving the build system unspecified was rejected because it defeats the point of a template.

## Consequences

Non-Java or Gradle projects need custom workflows. The Java version is fixed at 17 in the action and changes with it. Builds depend on the community GitLab repository being reachable.

## Related ADRs

- [ADR-002: GitHub Actions-Based Automation Architecture](002-github-actions-automation.md) - Foundation for build automation
- [ADR-013: Reusable GitHub Actions Pattern](013-reusable-github-actions-pattern.md) - Reusable build actions
- [ADR-003: Template Repository Pattern](003-template-repository-pattern.md) - Template distribution of build configuration
- [ADR-035: Azure-Only Maven Profile](035-azure-only-maven-profile.md) - The `core,azure` profile supplied by validate.yml
- [ADR-037: Engineering System Owns Service Dockerfile](037-engineering-system-owns-service-dockerfile.md) - Image build

## References

- [OSDU Platform Documentation](https://community.opengroup.org/osdu/platform)
- [Maven Documentation](https://maven.apache.org/guides/)
- [JaCoCo Documentation](https://www.jacoco.org/jacoco/trunk/doc/)
- [GitHub Actions Java Setup](https://github.com/actions/setup-java)

---

[← ADR-024](024-sync-workflow-duplicate-prevention-architecture.md) | :material-arrow-up: [Catalog](index.md) | [ADR-026 →](026-dependabot-security-update-strategy.md)
