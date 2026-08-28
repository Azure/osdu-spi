# Pull Request Validation Workflow

The pull request validation workflow acts as the automated quality gatekeeper for your repository. It ensures that changes build correctly and meet process requirements before they merge into protected branches.

The validation system applies different build rules by context. Sync PRs targeting the provider-less `fork_upstream` tree build `core` only and skip the image jobs; other Java changes build the Azure profile set and validate a service image.

## When It Runs

The validation workflow activates automatically across multiple scenarios to maintain consistent quality standards:

- **Every pull request** to protected branches (`main`, `fork_integration`, `fork_upstream`) - Ensures all incoming changes meet quality standards
- **Direct pushes** to protected branches - Validates changes that bypass the PR process (when permitted)
- **Manual trigger** for post-initialization validation - Allows on-demand quality checks during setup or troubleshooting

The workflow declares both `pull_request` and `pull_request_target`, and routes each PR to exactly one lane. Same-repository `sync/` branches take `pull_request_target`, which reads the workflow from the default branch; in filter mode that is the only lane, because neither `fork_upstream` nor the sync branch carries workflows. Every other PR takes `pull_request`. The unused lane reports skipped, so exactly one `🐳 Docker Build` context reflects a real build.

## What Gets Validated

The workflow performs comprehensive validation across three key areas to ensure both code quality and process compliance:

### Code Quality Validation
The system verifies that code compiles, dependencies resolve, and tests pass. Pull-request builds can generate JaCoCo coverage reports. Documentation and configuration-only PRs keep the required summary checks reporting while skipping the heavy Java and container jobs.

### Process Compliance Verification
Beyond code quality, the workflow validates semantic PR titles for ordinary PRs to `main`, detects whitespace/conflict-marker errors, and verifies that PR branches are up to date.

### Security and Dependency Analysis
CodeQL runs in its own workflow and supplies the required `CodeQL` status. Dependabot PRs use `dependabot-validation.yml` for one Java build with coverage followed by validate-only container construction; they do not run the regular Java and container jobs in this workflow.

## Validation Results

### ✅ **All Checks Pass**
- PR is eligible to merge after any required human approval
- Review the change normally

### ⚠️ **Some Checks Fail**
- PR blocked until issues resolved
- Check specific failure details in PR status

### ❌ **Critical Failures**
- Build errors, security issues, or policy violations
- Must be fixed before merge consideration

## How to Fix Common Issues

### Build Failures
```bash
# Run build locally to debug
mvn clean install -P core,azure

# Check for missing dependencies
mvn dependency:tree
```

### PR Title Issues

Edit the pull request title to use a supported Conventional Commit type, for example `feat: add new feature description`.

### Test Failures
```bash
# Run tests locally
mvn test -P core,azure

# Run specific test class
mvn test -P core,azure -Dtest=TestClassName

# Run with coverage report
mvn test -P core,azure jacoco:report
```

### Merge Conflicts
```bash
# Update your branch with target branch
git fetch origin
git merge origin/main  # or target branch

# Resolve conflicts in IDE
# Then commit resolution
git add .
git commit -m "resolve: merge conflicts with main"
```

## Validation Jobs

The workflow coordinates the following validation jobs:

| Job | Purpose | What It Checks |
|-----|---------|----------------|
| **Initialization Check** | Verifies repository setup | Ensures workflows are properly deployed |
| **Repository State** | Detects project type | Identifies Java projects via `pom.xml` |
| **Path Check** | Avoids unnecessary work | Skips heavy jobs for docs/config-only PRs |
| **Java Build** | Compiles and tests | Uses `core,azure` by default; `core` on `fork_upstream` |
| **Docker Build (validate)** | Validates the service image | Builds the canonical `build/Dockerfile` without registry credentials |
| **Docker Push** | Publishes trusted builds | Pushes multi-arch SHA and branch tags to public GHCR |
| **Code Validation** | Process compliance | Semantic PR title, conflict markers, branch status |
| **Docker Build summary** | Required status | Always reports a stable `🐳 Docker Build` result |

## Branch-Specific Rules

All protected branches use the same validation rules, with exemptions for specific PR types:

| Branch | Standard Validation | Exemptions |
|--------|-------------------|------------|
| **`main`** | Azure Maven and image validation + human approval | Docs/config-only changes skip heavy jobs |
| **`fork_integration`** | Azure Maven and image validation | Docs/config-only changes skip heavy jobs |
| **`fork_upstream`** | Core-only Maven validation | No Azure JAR or container image exists on this branch |
| **Feature branches** | N/A - not protected | Standard PR validation when targeting protected branches |

## Special Cases

### Sync PRs
- **Relaxed commit standards** - Upstream commits may not follow conventions
- **Conflict handling** - Automatically creates resolution guidance
- **AI enhancement** - Generates PR descriptions when possible
- **Single lane** - `pull_request_target` owns sync PRs and supplies trusted local actions; it builds `core` only in filter mode, and the full profile set with image validation in mirror mode

### Emergency Fixes
- **Override capability** - Admin can bypass non-critical checks
- **Audit trail required** - Override reason must be documented

## Status Check Details

### Required Checks on `main`
- `CodeQL` - Stable summary from the separate CodeQL workflow
- `🐳 Docker Build` - Stable summary covering Java and validate-only image build results

The integration-branch ruleset does not currently require status checks.

### Check Exemptions
- **Sync PRs**: Build `core` only and skip image validation
- **Release and automation PRs**: Skip semantic PR-title validation
- **Dependabot PRs**: Build with coverage and validate the image through `dependabot-validation.yml`
- **Docs/config-only PRs**: Skip Java and container work while summary checks still report

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Initialization check failed" | Repository not properly set up | Ensure workflows are deployed and `pom.xml` exists |
| "Java build failed" | Compilation or dependency issues | Run `mvn clean install` locally, check dependency conflicts |
| "Unit tests failing" | Test failures in Maven build | Run `mvn test` locally, fix failing test cases |
| "Semantic PR validation failed" | PR title doesn't follow the supported format | Use a title such as `feat:`, `fix:`, or `chore:` |
| "Merge conflicts detected" | Git conflict markers found | Resolve conflicts locally and commit resolution |
| "Repository not initialized" | Missing required setup files | Complete repository initialization first |
| "Branch status validation failed" | Branch protection or merge issues | Ensure branch is up to date with target |

## Configuration

### Commit Message Format
```
type(scope): description

feat: add new feature
fix: resolve bug in component
docs: update API documentation
chore: update dependencies
```

### Container Configuration

The engineering system syncs the canonical `build/Dockerfile` to every fork. `SERVICE_NAME` defaults to the repository name, and `SERVICE_TARGET_JAR` is needed only to disambiguate multiple Azure Spring Boot JARs. Trusted pushes publish to `ghcr.io/<owner>/<service>` with the workflow `GITHUB_TOKEN`; untrusted PR contexts never receive package-write permission.

## Related

- [Conventional Commits](https://conventionalcommits.org/) - Commit message standards
- [Initialization Security](../adr/016-initialization-security-handling.md) - Security setup details
- [Build Workflow](build.md) - Detailed build process
- [ADR-033: GHCR as Service Image Registry](../adr/033-ghcr-as-service-image-registry.md)
- [ADR-037: Canonical Service Dockerfile](../adr/037-engineering-system-owns-service-dockerfile.md)