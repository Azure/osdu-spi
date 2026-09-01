# ADR-003: Template Repository Pattern for Self-Configuration

## Status
**Accepted** - 2025-10-01

## Context
Teams need to set up fork management for different upstream repositories without manual configuration. Done by hand, setup means creating three branches with the right relationships, installing workflows, configuring branch protection and security settings, and connecting the upstream repository. Each step is error-prone and produces inconsistent results across repositories.

## Decision
Implement the fork management system as a GitHub Template Repository that configures itself through an initialization workflow:

1. **Template Repository**: The repository is marked as a template and contains the complete set of workflows and configuration files.
2. **Issue-Based Configuration**: On creation, `init.yml` opens an initialization issue. The user replies with the upstream repository URL.
3. **Automated Setup**: `init-complete.yml` validates the URL, creates the branch structure, installs the fork workflows, applies protection and security settings, and closes the issue.
4. **Configuration via Repository Variables**: Repository-specific values such as `UPSTREAM_REPO_URL` and `INITIALIZATION_COMPLETE` are stored as GitHub repository variables, not written into workflow files. Workflows read them through `vars`.

Issue-based input keeps setup inside the GitHub web interface, lets the workflow validate the URL and reply with clear errors, and leaves an audit trail of the configuration in the issue history.

## Alternatives Considered

### 1. Manual Setup Documentation
No automation to maintain, but error-prone, slow, and inconsistent. Rejected.

### 2. CLI Tool for Setup
Flexible, but requires local tool installation and platform-specific maintenance. Rejected.

### 3. External Configuration Service
Centralized management, but an external dependency with its own security surface. Rejected.

### 4. Cookiecutter/Yeoman Template
Industry-standard templating, but needs local tools and produces a static copy with no update path. Rejected.

## Consequences
The system is tied to GitHub's template feature, and the initial setup captures only what an issue comment can carry (today, the upstream URL). Template changes do not reach existing forks by themselves; ADR-011 and ADR-012 add template synchronization for that.

## Implementation Details

### Initialization Process
1. User creates a repository from the template.
2. `init.yml` creates the system labels and the initialization issue.
3. User provides the upstream repository URL in an issue comment (GitHub or GitLab URL; see `.github/local-actions/validate-upstream-repo/`).
4. `init-complete.yml` validates the upstream, sets repository variables, creates the three-branch structure with the upstream connection, installs workflows from `.github/template-workflows/`, applies protection and security settings, and removes template-only files listed in `.github/sync-config.json`.
5. The initialization issue is closed and the repository is ready for upstream synchronization.

---

[← ADR-002](002-github-actions-automation.md) | :material-arrow-up: [Catalog](index.md) | [ADR-004 →](004-release-please-versioning.md)
