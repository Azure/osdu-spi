# ADR-027: Documentation Generation Strategy with MkDocs

## Status
**Accepted** - 2025-10-01

## Context

The template needs published documentation for using and maintaining the template, the ADR catalog, workflow guides, and action interfaces. It has to be versioned with the code, searchable, and published automatically to GitHub Pages.

## Decision

Documentation is written in Markdown under `doc/src/` and built with **MkDocs Material**, deployed to GitHub Pages by `.github/workflows/docs.yml`.

- Configuration lives in `doc/mkdocs.yml` (site name, theme, navigation, Markdown extensions). Mermaid diagrams render through the `superfences` extension.
- ADRs live in `doc/src/adr/` alongside `architecture/`, `workflows/`, and the home page. `doc/product/` holds product specifications outside the site.
- The docs workflow runs on pushes to `main` that touch `doc/src/**`, `doc/mkdocs.yml`, or the workflow itself, and on manual dispatch.
- The deploy job is gated on `vars.IS_TEMPLATE == 'true'`, so forks that inherit the workflow do not publish a copy of the template site.
- Python dependencies are installed with `pip install --require-hashes -r doc/requirements.txt`; `doc/requirements.in` is the source and the hashed file is regenerated from it. The build runs `mkdocs gh-deploy --strict`, so a broken link or missing page fails the run.

## Alternatives Considered

GitHub Wiki lives outside version control and PR review. Docusaurus and Sphinx add a build pipeline or markup that the content does not need. Jekyll's search and navigation are weaker than Material's. Plain README files were rejected for discoverability.

## Consequences

Local preview needs Python and the pinned requirements. The site is tied to the Material theme's customisation options and to GitHub Pages hosting.

## Related ADRs

- [ADR-002: GitHub Actions-Based Automation Architecture](002-github-actions-automation.md) - Automation for docs deployment
- [ADR-003: Template Repository Pattern](003-template-repository-pattern.md) - Documentation distribution
- [ADR-011: Configuration-Driven Template Synchronization](011-configuration-driven-template-sync.md) - Docs sync strategy

## References

- [MkDocs Documentation](https://www.mkdocs.org/)
- [MkDocs Material Theme](https://squidfunk.github.io/mkdocs-material/)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)
---

[← ADR-026](026-dependabot-security-update-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-028 →](028-workflow-script-extraction-pattern.md)
