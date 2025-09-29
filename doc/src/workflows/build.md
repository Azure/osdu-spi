# Build and Test Workflow

The build and test workflow provides rapid feedback for developers by automatically building and testing code changes on feature branches. This workflow focuses specifically on giving developers immediate visibility into whether their changes compile correctly, pass existing tests, and maintain adequate code coverage before they submit pull requests for review.

Unlike the more comprehensive validation workflow that runs on protected branches, the build workflow is optimized for speed and developer productivity. It runs in parallel with your development process, helping you catch issues early when they're easier and cheaper to fix. The workflow supports multiple project types and includes intelligent caching to minimize build times while maintaining thorough verification.

## When It Runs

The build workflow activates during active development to provide continuous feedback:

- **Feature branch pushes** - Triggers on every commit to non-protected branches during development
- **Pull request updates** - Runs when a PR is created or updated to verify changes
- **Manual trigger** - Available via GitHub Actions tab for debugging build issues or testing configurations

## What Happens

The workflow follows an optimized build and test process designed for rapid developer feedback:

1. **Environment setup** - Configures the build environment with correct runtime versions and dependencies
2. **Dependency installation** - Downloads and caches project dependencies to speed up subsequent builds
3. **Code compilation** - Builds the project and immediately reports any compilation errors
4. **Test execution** - Runs the full test suite with coverage analysis and performance monitoring
5. **Results reporting** - Provides detailed feedback on build status, test results, and coverage metrics

The workflow produces clear outcomes to help you understand the state of your changes:
- **Success**: Build passes, all tests complete, and coverage meets or exceeds minimum thresholds
- **Failure**: Build errors, test failures, or coverage drops below required minimum requirements

## Build Support

### Supported Project Types
- **Java/Maven only** - Detects Maven-based projects with `pom.xml` files
- **Java 17 runtime** - Uses Temurin distribution for consistent builds
- **Community Maven repositories** - Supports GitLab-hosted OSDU dependencies

### Build Features
- **Maven dependency caching** - Speeds up builds by caching `.m2/repository`
- **JaCoCo coverage reporting** - Generates detailed test coverage reports using JaCoCo plugin
- **Community repository access** - Authenticates with GitLab Maven repositories for OSDU dependencies
- **Artifact storage** - Saves test reports and coverage data for 30 days

## When You Need to Act

### Build Failures
- **Red X on PR** - Build failed, check details in Actions tab
- **Email notifications** - If configured for your repository
- **Status badges** - Build status indicators in README

### Coverage Issues
- **Coverage dropped** - New code lacks sufficient test coverage
- **Threshold warnings** - Coverage below required minimums

## How to Respond

### Debug Build Failures
```bash
# Run build locally to reproduce
mvn clean install

# Check for common issues
mvn dependency:analyze  # dependency conflicts
mvn versions:display-dependency-updates  # outdated dependencies
```

### Fix Test Failures
```bash
# Run tests locally
mvn test

# Run specific test class
mvn test -Dtest=TestClassName

# Run specific test method
mvn test -Dtest=TestClassName#testMethodName
```

### Improve Coverage
```bash
# Generate coverage report locally
mvn clean test org.jacoco:jacoco-maven-plugin:0.8.11:report

# View coverage report
open target/site/jacoco/index.html

# Add tests for uncovered code
# Focus on critical paths and edge cases
```

## Configuration

### Required Maven Configuration
```xml
<!-- Required plugins for build workflow -->
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.11</version>
</plugin>
```

### Community Repository Access
```xml
<!-- Maven settings for GitLab OSDU dependencies -->
<settings>
  <servers>
    <server>
      <id>gitlab-maven</id>
      <configuration>
        <token>${env.COMMUNITY_MAVEN_TOKEN}</token>
      </configuration>
    </server>
  </servers>
</settings>
```

### Coverage Thresholds
| Metric | Minimum | Target |
|--------|---------|---------|
| **Line Coverage** | 80% | 90% |
| **Branch Coverage** | 75% | 85% |
| **Function Coverage** | 85% | 95% |

## Performance

### Build Times (Typical)
- **Small projects** - 2-5 minutes
- **Medium projects** - 5-10 minutes
- **Large projects** - 10-20 minutes

### Optimization Features
- **Incremental builds** - Only rebuild changed components
- **Dependency caching** - Reuse cached dependencies across builds
- **Parallel execution** - Run tests in parallel when possible

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Dependencies not found" | Check pom.xml, clear cache |
| "Build timeout" | Reduce test scope or optimize build scripts |
| "Memory issues" | Increase heap size in build configuration |
| "Test flakiness" | Fix non-deterministic tests, add proper waits |
| "Coverage calculation errors" | Verify test configuration, check exclusions |

## Integration

### With Other Workflows
- **Validation workflow** - Uses build results for PR checks
- **Release workflow** - Requires successful builds for releases
- **Security scanning** - Runs after successful builds

### Artifact Handling
- **Test reports** - Stored for 30 days in GitHub Actions
- **Coverage reports** - Available as downloadable artifacts
- **Build logs** - Accessible via Actions tab for debugging

## Related

- [Validation Workflow](validation.md) - PR quality gates that use build results
- [Java Build Action](../actions/java-build/README.md) - Maven-specific build details
- [Test Coverage Guidelines](../decisions/adr_testing.md) - Testing standards