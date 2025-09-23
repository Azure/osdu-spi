This is a forked repository of the OSDU project, optimized for GitHub Copilot use. 
The following guidelines are designed to enhance clarity and efficiency in development practices, ensuring a smooth workflow for contributors.

## Repository Structure

* **Important Branches**:

  * `main`: Protected production (semantic releases)
  * `fork_upstream`: Auto-sync from upstream
  * `fork_integration`: Conflict resolution staging

---

## Commit Standards

### Conventional Commit Format

Commits **must** follow the [Conventional Commits](https://www.conventionalcommits.org) standard:

```text
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Valid Types**:

* `feat`: New feature
* `fix`: Bug fix
* `feat!`: Breaking feature change
* `fix!`: Breaking bug fix
* `chore`: Maintenance (no version bump)
* `docs`: Documentation
* `ci`: CI/CD configuration
* `refactor`: Code refactoring
* `test`: Tests

### Rules

* Use imperative mood ("fix bug", not "fixed")
* No emojis or special characters
* Lowercase type, colon, and space required (`fix: correct bug`)
* No brackets or prefixes (e.g., `[feat]`)

**Example**:

```bash
feat: add login middleware
```

---

## Branch Naming

Descriptive naming aligned to issue tracking:

```bash
feat/issue-123-add-auth
fix/issue-456-memory-leak
chore/update-dependencies
```

---

## Pull Request Workflow

* Create PRs using `gh pr create`
* PR title in conventional commit format
* Reference issues clearly (e.g., `Fixes #123`)
* Ensure all CI checks pass

---

## Automation Workflows

| Workflow              | Purpose                                      |
| --------------------- | -------------------------------------------- |
| `sync.yml`            | Sync from upstream; auto-create PRs          |
| `build.yml`           | Build/test Java Maven projects               |
| `validate.yml`        | Commit message validation and conflict check |
| `release.yml`         | Automate semantic version releases           |
| `sync-template.yml`   | Update from fork templates                   |
| `cascade.yml`         | Propagate updates to downstream forks        |
| `cascade-monitor.yml` | Monitor update propagation                   |

---

## Testing Standards

* Behavior-driven development (BDD)
* Maintain 80%+ test coverage

**Local Test Commands:**

```bash
mvn clean install
mvn test
mvn versions:display-dependency-updates
```

---

## MCP Integration Tools

* **`check_version_tool`**: Check Maven dependency versions
* **`check_version_batch_tool`**: Batch process Maven dependency checks
* **`list_available_versions_tool`**: List Maven versions by minor track
* **`scan_java_project_tool`**: Vulnerability scans with Trivy
* **`analyze_pom_file_tool`**: Analyze Maven POM files for dependencies and vulnerabilities

