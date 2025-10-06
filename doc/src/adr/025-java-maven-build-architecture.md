# ADR-025: Java/Maven Build Architecture

## Status
**Accepted** - 2025-10-01

## Context

The OSDU (Open Subsurface Data Universe) ecosystem is predominantly built using Java with Maven as the build system. Fork repositories created from this template need consistent, reliable build automation that:

- Supports Maven-based Java projects with standard OSDU dependencies
- Integrates with GitLab-hosted OSDU community Maven repositories
- Provides comprehensive test coverage reporting using JaCoCo
- Caches dependencies efficiently to reduce build times
- Works seamlessly with the three-branch fork management strategy

The template needed to make an architectural decision about which build systems to support and how to implement that support consistently across all fork repositories.

## Decision

Implement **Java/Maven as the primary build architecture** with:

1. **Java 17 Temurin** as the standard runtime
2. **Maven 3.9+** as the build tool
3. **JaCoCo** for code coverage reporting
4. **GitLab Maven repository** integration for OSDU dependencies
5. **Reusable GitHub Actions** for consistent build implementation

## Rationale

### Why Java/Maven Focus

1. **OSDU Ecosystem Alignment**: All core OSDU services are Java/Maven projects
2. **Enterprise Standard**: Java remains the enterprise standard for large-scale systems
3. **Mature Tooling**: Maven provides comprehensive dependency management and build lifecycle
4. **Coverage Integration**: JaCoCo integrates seamlessly with Maven for coverage reporting
5. **Community Consistency**: Aligns with OSDU community build practices

### Build Architecture Benefits

1. **Dependency Caching**: Maven `.m2/repository` caching speeds up builds by 50-70%
2. **Community Repository Access**: Automatic authentication with GitLab OSDU repositories
3. **Standardized Structure**: Consistent `pom.xml` patterns across all services
4. **Test Integration**: Native support for JUnit, TestNG, and other test frameworks
5. **Security Scanning**: Integration with dependency vulnerability scanning tools

## Alternatives Considered

### 1. Multi-Language Support (Java, Python, Node.js)

- **Pros**: Broader applicability, flexibility for different project types
- **Cons**: Complexity, maintenance overhead, diluted focus
- **Decision**: Rejected - OSDU is Java-centric, focus provides better experience

### 2. Gradle Build System

- **Pros**: More flexible, better performance, Kotlin DSL
- **Cons**: OSDU uses Maven, would require conversion effort
- **Decision**: Rejected - Incompatible with OSDU ecosystem standards

### 3. Bazel Build System

- **Pros**: Excellent for monorepos, reproducible builds
- **Cons**: Steep learning curve, not used in OSDU
- **Decision**: Rejected - Too different from OSDU practices

### 4. No Build System Opinion

- **Pros**: Maximum flexibility for teams
- **Cons**: No automation, inconsistent practices, manual setup
- **Decision**: Rejected - Defeats purpose of template automation

## Implementation Details

### Reusable Actions Structure

```yaml
.github/actions/
├── java-build/           # Core build logic
├── java-build-status/    # Status reporting with coverage
└── pr-status/           # PR status updates
```

### Build Workflow Configuration

```yaml
# build.yml
- uses: ./.github/actions/java-build
  with:
    java-version: '17'
    java-distribution: 'temurin'
    maven-args: 'clean install'
    community-maven-token: ${{ secrets.COMMUNITY_MAVEN_TOKEN }}
```

### Coverage Configuration

```xml
<!-- Required in pom.xml -->
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.11</version>
</plugin>
```

### Community Repository Access

```yaml
# Automatic GitLab OSDU repository configuration
settings.xml generated with:
- Repository: https://community.opengroup.org/api/v4/projects/
- Authentication: Bearer token from COMMUNITY_MAVEN_TOKEN
```

## Consequences

### Positive

- **Zero Configuration**: Java projects work immediately after fork creation
- **Fast Builds**: Dependency caching reduces build times significantly
- **OSDU Compatible**: Seamless integration with OSDU ecosystem
- **Coverage Reports**: Automatic test coverage tracking and reporting
- **Security Integration**: Dependency vulnerability scanning included
- **Consistent Experience**: Same build behavior across all forks

### Negative

- **Java-Only Focus**: Non-Java projects require custom workflow modifications
- **Maven Lock-in**: Projects using Gradle need conversion or custom workflows
- **Version Constraints**: Locked to Java 17 (though configurable)
- **GitLab Dependency**: Requires GitLab community repository access

### Neutral

- **Opinionated Defaults**: Prescriptive approach may not suit all teams
- **OSDU Alignment**: Tightly coupled to OSDU ecosystem practices
- **Action Maintenance**: Reusable actions require ongoing updates

## Success Criteria

- Maven builds complete successfully in < 10 minutes for typical projects
- JaCoCo coverage reports generated and accessible as artifacts
- GitLab OSDU dependencies resolve without authentication errors
- Build caching reduces subsequent build times by > 50%
- Zero configuration required for standard OSDU Java projects
- Coverage thresholds enforced (80% line, 75% branch coverage)

## Migration Path

For existing repositories adopting this architecture:

1. **Ensure Java 17 compatibility** in source code
2. **Add JaCoCo plugin** to pom.xml if not present
3. **Configure COMMUNITY_MAVEN_TOKEN** secret for GitLab access
4. **Update workflow files** via template-sync mechanism
5. **Verify build passes** with new architecture

## Future Evolution

### Potential Enhancements

1. **Multi-module Support**: Better support for Maven multi-module projects
2. **Parallel Builds**: Implement parallel test execution for faster builds
3. **Container Builds**: Add Docker/OCI image building to workflow
4. **SBOM Generation**: Software Bill of Materials for supply chain security
5. **Performance Profiling**: Build performance metrics and optimization

### Extensibility Points

- Custom Maven settings via repository variables
- Override Java version through workflow inputs
- Additional Maven repositories via configuration
- Custom test frameworks through Maven profiles

## Related ADRs

- [ADR-002: GitHub Actions-Based Automation Architecture](002-github-actions-automation.md) - Foundation for build automation
- [ADR-013: Reusable GitHub Actions Pattern](013-reusable-github-actions-pattern.md) - Reusable build actions
- [ADR-003: Template Repository Pattern](003-template-repository-pattern.md) - Template distribution of build configuration

## References

- [OSDU Platform Documentation](https://community.opengroup.org/osdu/platform)
- [Maven Documentation](https://maven.apache.org/guides/)
- [JaCoCo Documentation](https://www.jacoco.org/jacoco/trunk/doc/)
- [GitHub Actions Java Setup](https://github.com/actions/setup-java)

---

[← ADR-024](024-sync-workflow-duplicate-prevention-architecture.md) | :material-arrow-up: [Catalog](index.md) | [ADR-026 →](026-dependabot-security-update-strategy.md)
