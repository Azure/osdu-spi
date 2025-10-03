# ADR-027: Documentation Generation Strategy with MkDocs

## Status
**Accepted** - 2025-10-01

## Context

The Fork Management Template requires comprehensive documentation for:

1. **Template Documentation**: How to use and maintain the template itself
2. **Architectural Decisions**: ADRs and their evolution over time
3. **Workflow Documentation**: Detailed guides for each workflow
4. **API Documentation**: Reusable actions and their interfaces
5. **User Guides**: Step-by-step instructions for common tasks

The documentation needed to be:
- Automatically published and versioned
- Searchable and well-organized
- Maintainable alongside code
- Accessible via GitHub Pages
- Professional in appearance

## Decision

Implement **MkDocs Material** as the documentation generation system with:

1. **MkDocs Material Theme**: Professional, responsive documentation site
2. **GitHub Pages Deployment**: Automatic publishing via GitHub Actions
3. **Markdown-Based Content**: Documentation as code in the repository
4. **ADR Integration**: Automatic inclusion of all ADRs in documentation
5. **Search Functionality**: Built-in search across all documentation

## Rationale

### Why MkDocs Material

1. **Developer-Friendly**: Markdown-based, lives with code
2. **Professional Appearance**: Material Design theme is clean and modern
3. **Feature-Rich**: Search, navigation, syntax highlighting built-in
4. **GitHub Integration**: Works seamlessly with GitHub Pages
5. **Active Community**: Well-maintained with regular updates

### Documentation as Code Benefits

1. **Version Control**: Documentation versioned with code
2. **Pull Request Reviews**: Documentation changes reviewed like code
3. **Consistency**: Single source of truth in repository
4. **Automation**: Generated and published automatically
5. **Searchability**: Full-text search across all documentation

## Alternatives Considered

### 1. GitHub Wiki
- **Pros**: Built into GitHub, no setup required
- **Cons**: Separate from code, poor version control, limited features
- **Decision**: Rejected - Lacks version control and automation

### 2. Docusaurus
- **Pros**: React-based, highly customizable, versioning support
- **Cons**: More complex, requires Node.js build pipeline
- **Decision**: Rejected - Unnecessary complexity for current needs

### 3. Sphinx
- **Pros**: Powerful, extensive plugin ecosystem, reStructuredText
- **Cons**: Python-specific, steeper learning curve, complex configuration
- **Decision**: Rejected - MkDocs simpler for Markdown content

### 4. Jekyll (GitHub Pages default)
- **Pros**: GitHub native support, Ruby-based, simple
- **Cons**: Less features, dated appearance, limited search
- **Decision**: Rejected - MkDocs Material provides better UX

### 5. No Documentation Site
- **Pros**: Simplest approach, just README files
- **Cons**: Poor discoverability, no search, unprofessional
- **Decision**: Rejected - Documentation critical for adoption

## Implementation Details

### Directory Structure

```
doc/
├── mkdocs.yml                 # MkDocs configuration
├── src/
│   ├── index.md              # Home page
│   ├── architecture/         # Architecture documentation
│   ├── workflows/            # Workflow guides
│   ├── decisions/            # ADRs
│   ├── images/               # Diagrams and screenshots
│   ├── stylesheets/          # Custom CSS
│   └── javascripts/          # Custom JavaScript
└── README.md                 # Documentation about documentation
```

### MkDocs Configuration

```yaml
# mkdocs.yml
site_name: OSDU Fork Management
site_url: https://azure.github.io/osdu-spi
theme:
  name: material
  features:
    - navigation.instant
    - navigation.tracking
    - navigation.sections
    - search.highlight
    - content.code.copy
  palette:
    primary: indigo
    accent: indigo

plugins:
  - search
  - mermaid2

nav:
  - Home: index.md
  - Architecture:
    - Overview: architecture/overview.md
    - Three-Branch Strategy: architecture/three_branch_strategy.md
  - Workflows:
    - Initialization: workflows/initialization.md
    - Synchronization: workflows/synchronization.md
    - Build: workflows/build.md
  - Decisions:
    - Index: decisions/index.md
    - ADRs: decisions/*.md
```

### GitHub Actions Workflow

```yaml
# .github/workflows/docs.yml
name: Documentation
on:
  push:
    branches: [main]
    paths:
      - 'doc/**'
      - 'mkdocs.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-python@v4
      - run: pip install mkdocs-material
      - run: mkdocs gh-deploy --force
```

### Documentation Categories

| Category | Content | Update Frequency |
|----------|---------|------------------|
| **Architecture** | System design, patterns | On architectural changes |
| **Workflows** | Detailed workflow guides | On workflow updates |
| **Decisions** | ADRs | On new decisions |
| **API Reference** | Action interfaces | On action changes |
| **User Guides** | How-to documentation | As needed |

## Consequences

### Positive
- **Professional Documentation**: Clean, searchable documentation site
- **Automatic Publishing**: Changes published on merge to main
- **Version Control**: Documentation versioned with code
- **Search Capability**: Full-text search across all content
- **Mobile Friendly**: Responsive design works on all devices
- **Low Maintenance**: Minimal ongoing maintenance required

### Negative
- **Build Dependency**: Requires Python and MkDocs for local preview
- **Learning Curve**: Team needs to learn MkDocs configuration
- **Build Time**: Adds ~2 minutes to CI/CD pipeline
- **Storage**: GitHub Pages has 1GB limit (not a practical concern)

### Neutral
- **Markdown Only**: Limited to Markdown formatting capabilities
- **Theme Lock-in**: Customization limited to Material theme options
- **GitHub Pages**: Tied to GitHub's hosting service

## Success Criteria

- Documentation site builds and deploys successfully on every merge
- Search returns relevant results across all documentation
- Page load time < 2 seconds for documentation pages
- Documentation stays in sync with code changes
- ADRs automatically included in documentation site
- Mobile and desktop responsive design works correctly

## Integration Points

### With GitHub Actions (ADR-002)
- Automated build and deployment via GitHub Actions
- Triggered on documentation changes to main branch
- Uses GitHub Pages for hosting

### With ADR System
- All ADRs automatically included in documentation
- ADR index page generated from file system
- Cross-references between ADRs maintained

### With Template Distribution
- Documentation included in template repository
- Fork repositories can customize their documentation
- Template updates include documentation improvements

## Future Evolution

### Potential Enhancements
1. **API Documentation Generation**: Auto-generate from code comments
2. **Multi-Version Documentation**: Support multiple versions
3. **Internationalization**: Multi-language documentation support
4. **Interactive Examples**: Embedded code playgrounds
5. **Video Tutorials**: Embedded video content
6. **PDF Export**: Generate PDF versions of documentation

### Integration Opportunities
- Link documentation to GitHub Discussions
- Integrate with search engines for better SEO
- Add analytics to understand usage patterns
- Create documentation feedback system

## Migration Path

For repositories adopting this documentation strategy:

1. **Copy MkDocs configuration** from template
2. **Move existing documentation** to `doc/src/` structure
3. **Configure GitHub Pages** in repository settings
4. **Run initial deployment** to validate setup
5. **Update repository README** with documentation link

## Related ADRs

- [ADR-002: GitHub Actions-Based Automation Architecture](002-github-actions-automation.md) - Automation for docs deployment
- [ADR-003: Template Repository Pattern](003-template-repository-pattern.md) - Documentation distribution
- [ADR-011: Configuration-Driven Template Synchronization](011-configuration-driven-template-sync.md) - Docs sync strategy

## References

- [MkDocs Documentation](https://www.mkdocs.org/)
- [MkDocs Material Theme](https://squidfunk.github.io/mkdocs-material/)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)
- [Markdown Guide](https://www.markdownguide.org/)
---

[← ADR-026](026-dependabot-security-update-strategy.md) | :material-arrow-up: [Catalog](index.md) | [ADR-028 →](028-workflow-script-extraction-pattern.md)
