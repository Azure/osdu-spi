# Build and Test Workflow

The build and test workflow provides rapid feedback for Java developers by automatically building and testing code changes on feature branches. It reports whether changes compile, pass tests, and produce a JaCoCo coverage report before they reach a protected branch.

Unlike the validation workflow, the build workflow only covers feature-branch pushes. Protected-branch pushes and container validation are handled by the validation workflow.

## When It Runs

The build workflow runs on:

- **Feature branch pushes** - Triggers on every commit to non-protected branches during development
- **PR events** - Handled by `validate.yml` and `dependabot-validation.yml`, so one commit never starts two builds; `sync/**` and `dependabot/**` pushes are excluded here for the same reason
- **Fork contributions** - A fork's branch produces no push event here, so `validate.yml` is a contribution PR's only build

Markdown/text-only changes (for example `**/*.md`, `**/*.txt`) and selected repository-metadata paths (for example `.github/**` and `docs/**`) are excluded.

## What Happens

The workflow:

1. **Repository detection** - Skips the Java jobs when no `pom.xml` is present
2. **Java build** - Uses the reusable Java action to compile, test, and upload JARs
3. **Coverage build** - Runs tests with JaCoCo and uploads the generated report
4. **Results reporting** - Adds coverage details to the workflow summary

The run is green when the Maven build and tests pass, and red when compilation, dependency resolution, or a test fails.

## Build Support

### Supported Project Types
- **Java/Maven only** - Detects Maven-based projects with `pom.xml` files
- **Java release from the pom** - Temurin at the release the root pom declares (`maven.compiler.release`, then `java.version`, default 17); 17 and 25 are supported
- **Community Maven repositories** - Supports GitLab-hosted OSDU dependencies
- **Azure profile in protected-branch validation** - Builds `core,azure` by default, with `MAVEN_PROFILE` available for exceptional repository layouts

### Build Features
- **Maven dependency caching** - Speeds up builds by caching `.m2/repository`
- **JaCoCo coverage reporting** - Generates a coverage report
- **Community repository access** - Resolves OSDU dependencies from the public GitLab Maven repository
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
mvn clean test -P core,azure org.jacoco:jacoco-maven-plugin:0.8.14:report

# View coverage report
open target/site/jacoco/index.html

# Add tests for uncovered code
# Focus on critical paths and edge cases
```

## Configuration

### Maven Profiles

Protected-branch validation and cascade builds pass `-P core,azure`. Maven disables an `activeByDefault` profile when any explicit profile is selected, so `core` must be included with `azure`. Set the optional `MAVEN_PROFILE` repository variable only when a service uses a different module layout.

Sync PRs targeting the provider-less `fork_upstream` tree build `core` only. See [ADR-035](../adr/035-azure-only-maven-profile.md).

### Build Environment

Some upstream tests read an environment variable that upstream CI sets for every job, and a Maven property cannot stand in for it. The optional `BUILD_ENV` repository variable holds `KEY=VALUE` lines that every Maven build exports first: validation, the push build and its coverage job, Dependabot validation and the cascade's integration build, including core-only `fork_upstream` builds. In a value, `$GITHUB_WORKSPACE` becomes the checkout root and nothing else expands. Blank lines and lines starting with `#` are skipped.

```text
SIS_DATA=$GITHUB_WORKSPACE/apachesis_setup/SIS_DATA
```

A malformed line, or a name the runner or the build owns (`PATH`, `HOME`, `SHELL`, `ENV`, `BASH_ENV`, `CI`, `JAVA_HOME`, `M2_HOME`, `MAVEN_HOME`, `MAVEN_OPTS`, `MAVEN_PROFILE`, `GENERATE_COVERAGE`, `NODE_OPTIONS`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, and anything starting with `GITHUB_`, `RUNNER_` or `ACTIONS_`), fails the build with an error naming the line. Unset, nothing is exported.

### Community Repository Access

When present, `.mvn/community-maven.settings.xml` supplies the OSDU dependency repository configuration. Dependency downloads use the repository's public read access, so the build workflows do not require Maven registry secrets. Maven publication is outside the scope of these workflows and would require separate authenticated configuration.

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
| A test fails on a missing environment variable upstream CI sets | Add it to `BUILD_ENV` |
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