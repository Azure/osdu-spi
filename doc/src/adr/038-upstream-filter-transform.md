# ADR-038: Upstream Filter Transform and One-Time Azure Seeding

## Context

Upstream OSDU service repositories carry shared service code alongside implementations for several cloud providers. Our Azure forks need the shared code and the Azure implementation. They do not need the AWS, Google Cloud, or IBM providers, the community `<svc>-core-plus` module, upstream's `devops/` pipelines, or the other providers' test suites. On the `osdu-spi-partition` reference fork that surplus is 274 of 421 files (65%), measured by a working prototype of the filter against the current upstream tip, code the Azure SPI never builds or ships but today still scans, patches, and reviews. Dependabot opens CVE PRs against it, CodeQL and Trivy scan it, and every cascade PR asks reviewers to read diffs for providers we do not own. `-P core,azure` (ADR-035) stops *building* it, but it stays in the tree.

Upstream also plans to remove its Azure implementations. `provider/<svc>-azure` and `testing/<svc>-test-azure` will be deleted, and the Azure code becomes ours to own. A fork that keeps mirroring upstream unchanged would faithfully propagate that deletion into our repositories.

We cannot get there by deleting the unwanted paths and continuing to merge. `git merge -X theirs` does not resolve modify/delete conflicts. Any path we delete that upstream still modifies fails the merge, and fails again on every future sync as the merge base advances. The obvious recovery, `git add -A`, silently restores the deleted files.

One property of the branch model makes a different approach safe. Today `fork_upstream` is a byte-for-byte upstream mirror. It is written only by `sync.yml` and read only by `cascade.yml`, so nothing depends on how its commits are produced.

## Decision

**Keep receiving upstream changes to the shared OSDU code, stop carrying the other cloud providers' code, and take permanent ownership of the Azure implementation before upstream deletes it.**

The three-branch topology (ADR-001) divides that work:

```text
Upstream OSDU repository
        |
        |  sync: copy shared code, drop provider implementations,
        |        inject references to the fork-owned Azure modules
        v
fork_upstream        (shared code, Azure references, no Azure source)
        |
        |  cascade: merge with fork-owned Azure source,
        |           stamp Azure parent versions
        v
fork_integration     (shared code + Azure source)
        |
        |  normal release PR
        v
main                 (shared code + Azure source)
```

The existing branch topology and release flow remain unchanged. Sync now generates `fork_upstream`, and the cascade gains one additional step to stamp Azure parent versions after merging.

### Three ownership categories

| Category | Source of truth | Contents |
| --- | --- | --- |
| Upstream-owned | Regenerated into `fork_upstream` from the upstream tip on every sync | `<svc>-core`, `<svc>-acceptance-test`, `testing/<svc>-test-core`, `pom.xml`, `testing/pom.xml`, `docs`, `NOTICE`, `LICENSE`, `.mvn` |
| Removed | Excluded from the generated branch, never on `fork_upstream` | Non-Azure providers, `<svc>-core-plus`, all of `devops/`, non-Azure `testing/` modules, `.gitlab-ci.yml` |
| Fork-owned | Seeded once at init, then maintained through the fork's normal PR process on `fork_integration` and `main` | `provider/<svc>-azure`, `testing/<svc>-test-azure`, `.github/`, `build/` |

Fork ownership needs no new machinery. It is how `.github/` and `build/` already survive every cascade. A three-way merge only touches paths that differ between the merge base and one of its sides. A path absent from both the merge base and `fork_upstream` is invisible to the cascade merge, so the fork's copy survives untouched. New forks get this for free because the Azure trees never exist on their `fork_upstream`. The existing fork gets it from the first post-cutover merge base onward. Upstream's eventual deletion of its Azure trees becomes a non-event.

### Generate `fork_upstream` instead of merging into it

A permanently reduced tree cannot be maintained by repeatedly merging the complete upstream tree into it (see Context). Each sync instead builds the desired tree directly. The same generated-branch pattern is already proven in production on core-only forks of these same upstream services, and this ADR adapts it to preserve fork-owned Azure implementations. The sync extracts the verbatim upstream tip to a scratch directory, runs the filter over it, and serializes the result through a scratch index into a commit on `fork_upstream`. The workflow's own checkout never leaves `main`, where the engine and the per-service config live, and the branch is written by ref update:

```
GIT_INDEX_FILE=$SCRATCH git read-tree upstream/$DEFAULT_BRANCH
GIT_INDEX_FILE=$SCRATCH git checkout-index -a -f --prefix=$GEN/
upstream-filter --config .github/upstream-filter.yml --checkout $GEN   # exit 2 = halt
GIT_INDEX_FILE=$SCRATCH git -C $GEN --git-dir=$REPO/.git add -A --force
TREE=$(GIT_INDEX_FILE=$SCRATCH git write-tree)
git commit-tree $TREE -p fork_upstream -p $UPSTREAM_SHA
```

`checkout-index` materializes every tracked file byte for byte, where `git archive` would honor upstream `export-ignore` and `export-subst` attributes and could silently drop or rewrite tracked files before the filter sees them. Nothing is textually merged, so modify/delete conflicts cannot occur. The scratch index never contains the previous branch state: it begins as the upstream tip's own tree, and `add -A` reconciles it to exactly the filtered directory, deletions included. No merge is ever in progress, which is what makes staging everything safe; the hazard described in Context is `git add -A` during a conflicted merge.

The commit is merge-shaped, with the previous `fork_upstream` tip as its first parent and the upstream tip as its second. That is an implementation detail, but it is what preserves upstream history. `git log`, `git blame`, contributor attribution, the changelog, and the AIPR meta commit (ADR-023) all work unchanged. Every generated commit records `Upstream-Sha` and `Filter-Rev` trailers, where `Filter-Rev` identifies both the filter engine version and the effective per-service configuration, so any generated tree can be reproduced exactly from its inputs.

### The filter halts rather than guesses

The filter classifies in two modes. Two directory categories are handled wholesale. The entire `provider/` tree is excluded from `fork_upstream`. The configured Azure provider is fork-owned and seeded separately, and every other provider is discarded automatically, never silently kept. All of `devops/` is likewise excluded. Everything else is classified entry by entry from `.github/upstream-filter.yml`: the top level, each `testing/` module, each root pom `<profile>`, and each module under `.fossa.yml`'s `analyze.modules` key. The Azure module entry there is deliberately dropped rather than injected: the fork strips `.gitlab-ci.yml` and runs no FOSSA analysis of its own, so an injected entry would be a second fork-maintained block that nothing consumes. Anything the config does not name makes the filter **exit 2**, failing the sync and opening a `sync-failed,human-required` issue, so a genuinely new shared module is never silently deleted.

Verification is three-way: **negative** (no stripped provider, profile, or FOSSA module survives), **positive** (`expected_kept` paths still exist, so an upstream rename fails loud instead of passing as an empty diff), and a non-mutating re-run of the classification as a new-module alarm.

### Maven adjustments during sync and cascade

Removing directories and splitting ownership leave dangling references in the poms. Three adjustments repair them, each at the stage where the affected files exist.

**During sync**, in the upstream-owned poms of the generated tree:

- Dangling `<module>` entries are pruned by derivation rather than by a second list. Any `<module>` whose target path does not exist after the file pass is removed, such as `partition-core-plus` inside the kept `core` profile. This is safe precisely because the file pass halts on unknowns, so a missing path can only mean a deliberate strip.
- The Azure references are always injected. The root pom's `azure` profile and the azure `<module>` in `testing/pom.xml` point at fork-owned directories, so the filter strips upstream's versions of both and injects the fork's stored blocks from `.github/upstream-filter.yml`. Behavior is identical before and after upstream deletes its Azure provider, so there is no transition to schedule.
- Verification asserts every surviving `<module>` resolves, with one deliberate exemption. The injected azure entries dangle on `fork_upstream` by design and resolve only after the cascade merge, where the fork-owned directories exist.

**During cascade**, in the fork-owned poms on `fork_integration`:

- The fork-owned poms carry upstream-derived versions in several places fed by independent sources: each module's `<parent><version>`, and pins such as the Azure test module's dependency on `testing/<svc>-test-core`'s own version. The sync cannot rewrite any of them because the poms exist on neither `fork_upstream` nor the generated tree, and `fork_integration` is the first branch where an upstream version bump and the fork-owned poms coexist. After `cascade.yml` merges `fork_upstream` there, it invokes the engine's stamp mode, which is defined by a post-condition rather than a site list: after stamping, no pre-bump upstream version string survives anywhere in the fork-owned poms, and the cascade fails if one does. A site list would not generalize across services, and a partial stamp is worse than a failed build, since Maven accepts a child whose version differs from its parent and would ship an Azure JAR carrying the old coordinates inside a bumped reactor. The bump then rides the normal release PR from `fork_integration` to `main`.

### Validation builds core-only on `fork_upstream`

`validate.yml` runs `java-build` on sync PRs and pushes to `fork_upstream` with `-P core,azure` (ADR-035). Against the generated tree that would hard-fail. The injected azure profile points at directories the tree deliberately omits, and Maven aborts the reactor when an explicitly activated profile's `<module>` has no pom. Validation targeting `fork_upstream` therefore drops `azure` and builds `core` only, validating the branch as what it is, a provider-less tree. Azure compilation is validated where the trees exist: the cascade compiles `fork_integration` with the Azure profiles, a check this program introduces since no workflow compiled the Azure modules after a sync before it, and `main` builds them on every PR.

### Where the machinery lives

- **Engine**: `.github/actions/upstream-filter/`, owned by the engineering system and synced to every fork like `docker-build` (ADR-013, ADR-028, ADR-037). Invoked by `sync.yml` to generate the tree, by `cascade.yml` to stamp the fork-owned pom versions, and by initialization to seed the Azure trees. The git plumbing lives beside the engine as scripts in the action directory, so the surface is locally testable and no caller ever checks out a branch lacking `.github/`.
- **Per-service config**: `.github/upstream-filter.yml`, seeded at init from `.github/fork-resources/` with `<service>` substitution (ADR-018), then fork-owned. Classifying a new upstream module is an ordinary PR in the repository whose team knows the answer.
- **Halt path**: the existing `Handle Failure` step and its `sync-failed,human-required` issue (ADR-020, ADR-022). A halt just supplies a more specific body.
- **Proof**: fixture tests drive every halt path, plus idempotence and determinism gates, in `dev-ci.yml` ahead of the sync stage.

### Seeding and cutover

New forks have no cutover. A `--seed` mode copies the Azure trees onto `main` at init, taking them from the newest upstream commit that still contains them. Today that is the upstream tip. After upstream deletes the trees it is the parent of the deletion commit, which upstream history retains permanently, so forks can be initialized at any time. `fork_upstream` is filtered from its first generation.

`osdu-spi-partition` needs one deliberate, scripted step. The first filtered sync deletes the Azure trees on `fork_upstream`, and the automation would carry that deletion to `main` on its own. `cascade-monitor` triggers the cascade on the sync PR's merge event itself, and for files untouched on our side the deletion merges silently. No reviewer can be expected to catch those deletions in a PR changing hundreds of files. (Files carrying Azure-local edits surface as modify/delete conflicts instead, which the restore below also resolves.) The cascade is therefore held for this one sync and the restore is scripted:

```bash
# cascade-monitor disabled for this one sync, commands run on fork_integration
git merge origin/main --no-edit                      # cascade.yml's normal first step
git merge origin/fork_upstream --no-commit || true   # deletions apply silently, Azure-local edits raise modify/delete conflicts
git checkout HEAD -- provider/partition-azure testing/partition-test-azure
git commit
git push origin fork_integration
```

Re-enabling `cascade-monitor` lets `cascade.yml`'s already-merged check pick up from here and open the normal release PR to `main`. After the restore commit, every future merge base lacks those paths, and the arrangement is stable permanently.

## Consequences

### Positive

- Modify/delete conflicts become structurally impossible. Removed paths are absent from the generated tree, every branch, and every merge base alike, so cascade merges have nothing to conflict over. The fork-owned Azure paths exist only on our side of any merge, so merges leave them untouched. Azure-local changes on `main` merge exactly as today.
- The sync surface on the partition reference fork drops from 421 files to 88 (21%). The filter discards 274 files, and the 59 files of the Azure trees leave the sync surface by becoming fork-owned. Reviewers read Azure-relevant diffs, and Dependabot, CodeQL, and Trivy stop covering code we never ship.
- Upstream's removal of the Azure provider requires no action and produces no incident.
- A new provider under `provider/` is stripped automatically, anything outside the recognized categories halts for review, and a rename of a kept module fails loud via `expected_kept`.

### Negative

- The Azure trees stop receiving upstream changes at seeding. That is the explicit intent, since upstream is deleting them, but any late upstream fix to them must be ported by hand.
- The cascade rewrites upstream-derived version strings inside fork-owned poms, the automation's only write to fork-owned content. The rule becomes that automation owns the Azure modules' version wiring, never their content. (The alternative of halting on mismatch would block every fork's cascade at each upstream version bump.)
- Sync-PR validation compiles `core` only, so an upstream change that breaks the Azure modules is first caught during the cascade on `fork_integration`, not on the sync PR.
- Each fork carries a classification file, and an unclassified upstream module blocks that fork's sync until someone classifies it. This is deliberate, but it is real recurring work.
- A filter program replaces a one-line `git merge`. A bug in it produces a wrong tree rather than a failed merge, which is why the idempotence, determinism, and halt-path gates run before the sync stage.
- Removed code remains reachable in `fork_upstream` history. "Provider-free" is a claim about the generated tree and its artifacts, not historical erasure.

### Neutral

- Customer-tier forks consume the already filtered `main` of a service repository and mirror it verbatim (ADR-039). The filter runs exactly once per change, at this tier.
- `<svc>-acceptance-test` is unaffected. It declares no `<parent>` and belongs to no root pom profile.
- `testing/<svc>-test-azure` depends only on `testing/<svc>-test-core` plus published artifacts in every service surveyed, so the kept pair is self-contained.
- `pom.xml` and `testing/pom.xml` stay upstream-owned. Making them fork-owned would end the injection problem but cut off upstream's `dependencyManagement`, plugin, and Java-version updates.

## Alternatives Considered

- **Merge, then delete the unwanted trees.** Rejected. Experiments confirmed that `-X theirs` leaves modify/delete conflicts unresolved, that the failure recurs on every sync, and that `git add -A` silently restores upstream files.
- **Sparse-checkout or a `.gitattributes` merge driver.** Rejected. The paths stay in the branch's tree, so the scan, Dependabot, and review surfaces are unchanged.
- **Strip `testing/` wholesale.** Rejected. SPI needs `testing/<svc>-test-azure` as its Azure integration suite, and per-entry classification keeps the new-module alarm.
- **Keep `devops/azure`.** Rejected. `osdu-spi-stack` ships its own charts, and ADR-037 already owns the Dockerfile.
- **Keep `<svc>-core-plus`.** Rejected. Across all eight services its only consumers are modules that are themselves removed.
- **Stamp parent versions by emitting the Azure poms into the generated tree.** Rejected. It would put those poms back on the `fork_upstream` lineage, reopening the modify/delete class this design exists to close, make `main` a third input to the generated tree, and revert fork edits to those poms on every sync. The cascade stamp writes the version wiring where the files actually live.
- **Decouple the Azure modules entirely** (standalone poms, depending on `<svc>-core` as a resolved artifact). Deferred, not rejected. It would end the version coupling and the parent stamp permanently, but costs a per-service pom rewrite and loses inherited `dependencyManagement`. Revisit once upstream's deletion has landed.

---

[← ADR-037](037-engineering-system-owns-service-dockerfile.md) | :material-arrow-up: [Catalog](index.md)
