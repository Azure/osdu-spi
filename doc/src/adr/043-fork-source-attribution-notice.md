# ADR-043: Fork Source Attribution Notice

## Status

Accepted (2026-10-27)

## Context

Each service repository is a fork of an OSDU community project and carries its history, but nothing in the repository says so. The root `NOTICE` is upstream's FOSSA output: it lists third-party dependencies and is classified `keep` by the filter (ADR-038), so an edit to it is overwritten by the next upstream sync. Stripping it would stop the dependency notices from following upstream.

The attribution has to reach every existing fork through template sync and every new fork through initialization, and it has to survive in the container image, where a `.dockerignore` from upstream excludes `**/*.md` and dotfiles.

## Decision

**Each fork carries a fork-owned `NOTICE-OSDU-SPI` at its root that names the upstream project, its URL, its license, and the copyright holders named in its source headers. It is planted once, create-if-missing, and the fork owns it from then on.**

### Template and rendering

`.github/fork-resources/NOTICE-OSDU-SPI` is the template. `fork_resources.py notice` fills it: the project name and source from `UPSTREAM_REPO_URL`, and the holders from the `Copyright` lines in the first 20 lines of each tracked Java file. Known spellings of one holder collapse to one name (Schlumberger and SLB print as SLB). An unrecognized holder is kept as written and reported as a warning. Holders print one per line, most files first, because several names contain commas.

The name has no extension so that upstream's `.dockerignore` admits it, and it sits beside `NOTICE` and `LICENSE`, which it points to for dependency notices and the license text.

### Planting

Initialization renders and plants it with the other fork resources (ADR-018). Template sync plants it when it is missing, and a missing, plantable file counts as an update by itself, so a fork receives it on the next sync run whether or not the template changed. A fork whose notice cannot be rendered (no upstream URL, a URL that is not http or https, no Java file with a copyright header) is left without it and each sync run warns; the sync itself continues. After planting, template sync never rewrites it; a holder change is a pull request to the fork.

## Consequences

### Positive

- `NOTICE` keeps following upstream unchanged, and a later generated dependency notice can take that name without touching this file.
- A new fork is attributed at initialization with no manual step.

### Negative

- The holder list is a snapshot from planting. A holder upstream adds later reaches the file only by hand.
- The plant rule lives in the fork's copy of `sync-template.yml`, so an existing fork plants the file one sync after the rule arrives.

## Alternatives Considered

- **Append to `NOTICE`.** The filter keeps upstream's file, so the next upstream sync drops the addition.
- **Strip `NOTICE` and own it in the fork.** Stops the FOSSA dependency notices from following upstream.
- **`NOTICE-OSDU-SPI.md`.** Upstream's `.dockerignore` excludes `**/*.md`, so the file could not be copied into the image.
- **A fixed holder list in the template.** Holders differ per service; partition names The Open Group, storage names BP, and indexer-queue names two.
- **Regenerate on every sync.** Overwrites edits the fork made in review, the same problem as `NOTICE`.

---

[← ADR-042](042-paired-loader-image.md) | :material-arrow-up: [Catalog](index.md)
