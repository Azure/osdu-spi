# Contributing

This repository is the Azure implementation of an OSDU community service. It tracks the
upstream [OSDU project](https://community.opengroup.org/osdu/platform) and carries the
Azure provider on top.

> [!IMPORTANT]
> Code contributions are limited to Microsoft employees at this time. Anyone can report
> a bug or request a feature through [GitHub Issues](../../issues).

## Where a change belongs

This tree has three owners; [`.github/CODEOWNERS`](.github/CODEOWNERS) maps the paths.

| Area | Owner | Where to make the change |
|---|---|---|
| `provider/*-azure/`, `testing/*-test-azure/`, `.spi/`, `.github/upstream-filter.yml`, `.github/CODEOWNERS`, `CONTRIBUTING.md` | This repository | A pull request here. |
| `.github/` (except the files above), `build/`, `.release-please-config.json` | [`Azure/osdu-spi`](https://github.com/Azure/osdu-spi) | The template. Template sync overwrites these files here. |
| Everything else (shared service code) | OSDU community | Upstream in [OSDU GitLab](https://community.opengroup.org/osdu/platform). To bring in a specific upstream fix early, port it and add the `port` label to the pull request. |

## Making a change

1. Branch from `main` with a type prefix: `feat/…`, `fix/…`, `chore/…`.
2. Build and test with `mvn clean install`, adding `--settings=.mvn/community-maven.settings.xml` when that file exists, as CI does.
3. Use [Conventional Commits](https://www.conventionalcommits.org/) for commits and the pull request title; release-please versions from them.
4. Open a pull request against `main`. Merging needs passing CodeQL and validation checks, every review thread resolved, and a code owner's approval.

## License

By contributing, you agree that your contributions will be licensed under the
[Apache License 2.0](LICENSE).
