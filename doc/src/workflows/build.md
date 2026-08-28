# Build and Test Workflow

The build and test workflow provides rapid feedback for Java developers by automatically building and testing code changes on feature branches. It reports whether changes compile, pass tests, and produce a JaCoCo coverage report before they reach a protected branch.

Unlike the more comprehensive validation workflow, the build workflow is optimized for feature-branch feedback. Protected-branch pushes and container validation are handled by the validation workflow.

## When It Runs

The build workflow activates during active development to provide continuous feedback:

- **Feature branch pushes** - Triggers on every commit to non-protected branches during development
- **PR events** - Handled by `validate.yml` and `dependabot-validation.yml`, so one commit never starts two builds; `sync/**` and `dependabot/**` pushes are excluded here for the same reason
- **Fork contributions** - A fork's branch produces no push event here, so `validate.yml` is a contribution PR's only build

Markdown/text-only changes (for example `**/*.md`, `**/*.txt`) and selected repository-metadata paths (for example `.github/**` and `docs/**`) are excluded.

## What Happens

The workflow follows an optimized build and test process designed for rapid developer feedback:

1. **Repository detection** - Skips the Java jobs when no `pom.xml` is present
2. **Java build** - Uses the reusable Java action to compile, test, and upload JARs
3. **Coverage build** - Runs tests with JaCoCo and uploads the generated report
4. **Results reporting** - Adds coverage details to the workflow summary

The workflow produces clear outcomes to help you understand the state of your changes:
- **Success**: The Maven build and tests complete successfully
- **Failure**: Compilation, dependency resolution, or tests fail

## Build Support

### Supported Project Types
- **Java/Maven only** - Detects Maven-based projects with `pom.xml` files
- **Java 17 runtime** - Uses Temurin distribution for consistent builds
- **Community Maven repositories** - Supports GitLab-hosted OSDU dependencies
- **Azure profile in protected-branch validation** - Builds `core,azure` by default, with `MAVEN_PROFILE` available for exceptional repository layouts

### Build Features
- **Maven dependency caching** - Speeds up builds by caching `.m2/repository`
- **JaCoCo coverage reporting** - Generates detailed test coverage reports using JaCoCo plugin
- **Community repository access** - Authenticates with GitLab Maven repositories for OSDU dependencies
- **Artifact storage** - Saves JARs and coverage data for 2 days

## When You Need to Act

### Build Failures
- **Red X on PR** - Build failed, check details in Actions tab
- **Email notifications** - If configured for your repository
- **Status badges** - Build status indicators in README

## How to Respond

### Debug Build Failures
```bash
# Run the default Azure build locally
mvn clean install -P core,azure

# Check for common issues
mvn dependency:analyze  # dependency conflicts
mvn versions:display-dependency-updates  # outdated dependencies
```

### Fix Test Failures
```bash
# Run tests locally with the default profiles
mvn test -P core,azure

# Run specific test class
mvn test -Dtest=TestClassName

# Run specific test method
mvn test -Dtest=TestClassName#testMethodName
```

### Improve Coverage
```bash
# Generate coverage report locally
mvn clean test -P core,azure org.jacoco:jacoco-maven-plugin:0.8.11:report

# View coverage report
open target/site/jacoco/index.html

# Add tests for uncovered code
# Focus on critical paths and edge cases
```

## Configuration

### Maven Profiles

Protected-branch validation and cascade builds pass `-P core,azure`. Maven disables an `activeByDefault` profile when any explicit profile is selected, so `core` must be included with `azure`. Set the optional `MAVEN_PROFILE` repository variable only when a service uses a different module layout.

Sync PRs targeting the provider-less `fork_upstream` tree build `core` only. See [ADR-035](../adr/035-azure-only-maven-profile.md).

### Community Repository Access

When present, `.mvn/community-maven.settings.xml` supplies the OSDU dependency repository configuration. The `GITLAB_TOKEN`, `OPENGROUP_MAVEN_USERNAME`, and `OPENGROUP_MAVEN_TOKEN` secrets provide credentials where the corresponding workflow needs them.

## Performance

### Optimization Features
- **Dependency caching** - Reuse cached dependencies across builds
- **Path filtering** - Skip documentation and configuration-only changes
- **Azure-only validation** - Avoid building unrelated cloud-provider modules

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Dependencies not found" | Check pom.xml, clear cache |
| "Azure module not built" | Verify `MAVEN_PROFILE`; the default is `core,azure` |
| "Test flakiness" | Fix non-deterministic tests, add proper waits |
| "Coverage calculation errors" | Verify test configuration, check exclusions |

## Integration

### With Other Workflows
- **Validation workflow** - Handles protected-branch PR events, generates their coverage, and builds the service image with the canonical `build/Dockerfile`; trusted events publish it to public GHCR
- **Dependabot validation** - Builds dependency updates with coverage and validates their service image without publishing it
- **Release workflow** - Retags the release commit's existing GHCR image with the released version

### Artifact Handling
- **Build artifacts** - This workflow's JARs are retained for 2 days; validation creates and consumes a separate artifact within its own run
- **Coverage reports** - Retained for 2 days as downloadable artifacts
- **Build logs** - Accessible via Actions tab for debugging

## Related

- [Validation Workflow](validation.md) - PR quality gates that use build results
- [ADR-025: Java/Maven Build Architecture](../adr/025-java-maven-build-architecture.md)
- [ADR-035: Azure-Only Maven Profile](../adr/035-azure-only-maven-profile.md)
- [ADR-037: Canonical Service Dockerfile](../adr/037-engineering-system-owns-service-dockerfile.md)