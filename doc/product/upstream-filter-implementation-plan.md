# Upstream Filter Implementation Plan (ADR-038)

How the engineering system moves from mirroring `fork_upstream` to generating it, how the one running fork migrates, and in what order the pieces land.

ADR-038 is the design. This plan is the delivery sequence, the decisions the design left open, and the corrections that investigation of the real repositories forced.

## Starting position

One fork is running: `osdu-spi-partition`, initialized February 2026, upstream `community.opengroup.org/osdu/platform/system/partition`. Every other fork is created after this change ships, so the migration path has exactly one customer and can be a runbook rather than a program.

Numbers below come from a working prototype of the filter run against the current upstream tip, not from estimation.

| Measure | Value |
| --- | --- |
| Upstream tree today | 421 files |
| Generated `fork_upstream` after filtering | 88 files (21%) |
| Discarded entirely | 274 files |
| Moved to fork ownership | 59 files (`provider/partition-azure` 47, `testing/partition-test-azure` 12) |

The 333 files that leave `fork_upstream` are `provider/` 149, `devops/` 90, `partition-core-plus` 22, the six non-core `testing/` modules 71, and `.gitlab-ci.yml`. Of those, the 59 Azure files return as fork-owned content on `fork_integration` and `main`, leaving 274 discarded. The prototype produced byte-identical output across repeated runs and converged when re-applied to its own output.

## What investigation changed

Seven findings alter the work described in ADR-038. Four are corrections to the ADR, three are pre-existing defects that this feature would otherwise ride on top of.

### The stamp is a post-condition, not a list of sites

ADR-038 says the cascade rewrites two `<parent><version>` values. The fork-owned poms actually carry the upstream version in five places fed by three independent sources: the root `pom.xml` version, the `testing/pom.xml` version, and `testing/partition-test-core/pom.xml`'s own version, which `testing/partition-test-azure` pins as a dependency.

Rewriting only the two parent versions still builds. Maven accepts a child whose own `<version>` differs from its parent, so a stamp that narrow leaves the Azure JAR carrying the previous version inside a bumped reactor. That is a silent artifact-coordinate skew rather than a failed build, which is the worst available outcome.

Enumerating five sites also does not generalize to the other seven services. The rule becomes: after stamping, no pre-bump version string survives in either fork-owned pom, and the cascade fails if one does.

### Nothing compiles the generated tree before `main`

ADR-038 states that Azure compilation is validated on `fork_integration` during the cascade, which compensates for sync PRs building core only. Neither half holds today.

Sync PRs receive no validation at all. `validate.yml` gates every job on the actor being `github-actions[bot]`, `app/github-actions`, or `dependabot[bot]`, and sync PRs are opened by `osdu-spi-automation[bot]`. Every Validation run on the current sync PR is `skipped`, all eight jobs included, and there are no `pull_request` runs to compensate. `fork_upstream` also carries no required status checks, its ruleset holds a single deletion rule.

The cascade's validation step runs `mvn -B clean install` with no `-P`. The root pom's `core` profile is `activeByDefault`, but Maven disables default activation once any other profile activates, and the `Default` profile activates on `!repo.releases.id`. The bare command therefore builds the root aggregator pom alone. Azure has never been compiled during a cascade.

Even with `-P core,azure`, the reactor reaches `partition`, `partition-core`, and `provider/partition-azure` only. The root pom declares no top-level `<modules>`, so `testing/` is a separate reactor that no workflow enters.

This is the single highest-value item in the plan and it is fixable before any filter exists.

### The seed source formula silently returns nothing

Finding the newest upstream commit that still contains a deleted tree looks like `git rev-list -1 <ref> -- <path>`. Against a path deleted through a merge, default history simplification returns an empty result. `--full-history` is required, and it returns the merge commit itself, whose first parent is not necessarily the side that had the tree.

Verified against `provider/partition-gcp` in the fork's own history: simplified history returns nothing, `--full-history` returns a three-parent merge, and only the second parent holds the 33 files. The seed must iterate the deletion commit's parents and select the one where the path resolves.

### `.github/upstream-filter.yml` is delivered by nothing

`sync-template.yml` excludes `.github/fork-resources` from its directory loop and delivers that staging area through a hardcoded six-item allowlist. A seventh file added there reaches no fork. The per-service config must be hand-planted on the running fork and gain an explicit allowlist entry for future ones.

### `<service>` substitution is broken and unused

`deploy-fork-resources.sh` substitutes `<service>` using `basename $(git rev-parse --show-toplevel)`, which on a runner yields the repository name `osdu-spi-partition`, not the service slug `partition`. No file under `fork-resources/` contains the placeholder any more, so the mechanism has never substituted anything and the defect is invisible.

The filter config needs a real slug. `basename "${UPSTREAM_REPO_URL%.git}"` derives it from a repository variable that already exists on the fork, and it stays distinct from `SERVICE_NAME`, which several call sites legitimately want to be the repository name.

### The cascade cannot see the conflict the cutover is built around

`cascade.yml` detects conflicts with `grep -q "^UU\|^AA\|^DD"`. Modify/delete conflicts are staged as `UD` and `DU`, which that pattern misses. On the exact path the cutover produces, the cascade prints a success message, pushes an unresolved merge, and opens a release PR.

The same job's self-heal arm runs `git reset --hard origin/main` followed by `git push -f origin fork_integration` whenever `fork_integration` is behind `fork_upstream`, and the integration ruleset carries no non-fast-forward rule to stop it. That arm can destroy the cutover restore commit.

### Merging to the template is fleet distribution

`.github/actions` is `sync_all: true`, and `sync-template.yml` replaces each synced directory wholesale. A filter engine merged to the template reaches every fork on the next template-sync PR and generates their `fork_upstream` that night. The template's own branch protection currently requires only CodeQL, so a red harness is mergeable today.

## Decisions

Five choices the design left open, resolved.

**Never leave `main` in `sync.yml`.** `fork_upstream` carries no `.github/` at all, so the moment the workflow checks it out the engine and config vanish from the worktree. Rather than staging copies to a temp directory, the generation runs entirely through git plumbing with `GIT_INDEX_FILE` and `git write-tree` / `git commit-tree`, and the branch is written by ref update. This keeps `uses: ./.github/actions/upstream-filter` resolvable in sync, cascade, and init alike, and it retires the standing duplication that ADR-028 §7.1 records. The cost is honest: `sync.yml`'s 130-line integration step is the largest single edit in the program. Never leaving `main` means the primary working tree never moves: a step that genuinely needs a checked-out tree, such as AIPR's diff context, gets a disposable `git worktree add` rather than a treeless contortion.

**The engine never touches git.** One Python file with `--mode {generate,stamp,seed,verify}`, driven by a composite action, transforming a directory in place. The git surface, archive extraction, scratch-index serialization, and commit, lives beside it as scripts in the composite action directory per ADR-028, invoked by the workflows and testable locally as ordinary shell. The fixture corpus still drives only the engine: an engine that runs git commands makes that corpus mean less than it appears to.

**Standard library only, no `pip install`.** A YAML dependency resolved at runtime makes the generated tree a function of the runner image, which contradicts the reproducibility that the `Filter-Rev` trailer promises. The config file is a fixed, small schema and does not need a general parser. `cascade.yml` and `init-complete.yml` install nothing today and must not start.

**The config is a verdict map, and `main` is its only home.** Paired keep and strip lists let a name appear in both with nothing to catch it. One mapping from name to verdict per category, with `expected_kept` and `expected_absent` assertions alongside. `integration-cleanup.yml` resets `fork_integration` to `main` after every release, so a copy on that branch is derived, not durable.

**Fail closed and plant the config first.** When the config is absent the sync stops with a specific message rather than falling back to the old merge. Maintaining two generation paths costs more than the window it covers, and the window closes to zero if the config is planted on the fork before the template-sync PR is merged. `Handle Failure` gains deduplication in the same commit, because a missing config is a persistent halt and the nightly schedule would otherwise open one issue per day.

## Phases

Each phase is independently mergeable and leaves both the template and the running fork working.

### Phase 0: Standalone repairs

Defects found along the way that stand on their own merit and that later phases depend on.

- `cascade.yml` conflict detection becomes `[ -n "$(git ls-files -u)" ]` so modify/delete registers.
- The self-heal arm gains a guard so it cannot force-push over a restore commit.
- `SERVICE_SLUG` derives from `UPSTREAM_REPO_URL`.
- The `.mvn/community-maven.settings.xml` copy in `validate.yml` and `dependabot-validation.yml` becomes conditional.
- The dead Trivy install and the unused Node.js setup in `sync.yml` are removed, and the broken relative links in the published ADR pages are fixed. (A repo-wide sweep found 36 broken relative links across `doc/`; the remainder is a separate documentation chore, not part of this program.)

**Exit:** all five on template `main`, the fork's template-sync PR merged, one ordinary cascade observed green.

### Phase 1: Engine and proof, template only

The contract document first, freezing modes, exit codes, the halt code list, the JSON report schema, and the `Filter-Rev` formula. Then the engine, the fixture corpus, and a `dev-ci.yml` job that drives every halt path plus idempotence and determinism.

Fixtures live at `.github/local-actions/upstream-filter-tests/`, a path already excluded from both template sync and fork cleanup, which avoids the collision a top-level `tests/` would have with upstream trees.

**Exit:** the harness job is a required status check on template `main` *before* the action directory merges, and it is green. Merging the directory is fleet distribution, so the gate precedes the payload.

### Phase 2: Downstream workflows, still inert

The cascade gains the stamp step, an index-based assertion that fork-owned paths survived the merge, `-P` supplied through a validated `MAVEN_PROFILE` environment key, and a second invocation for the `testing/` reactor. `validate.yml` selects the profile by target branch and guards the Docker jobs against a JAR that will not exist on a filtered branch. Its `pull_request_target` actor gate also widens to admit the sync app's bot account and drops the dead `app/github-actions` arm, which is what makes sync-PR validation run at all. That stays inside the ADR-036 trust boundary: the restore-trusted-actions steps already exist to run trusted code against sync content, and `docker-push` remains excluded from `pull_request_target`.

Everything here runs against today's unfiltered tree. The stamp is a no-op while all versions agree, so a green run is not stamp validation and should not be recorded as such. The `-P` addition is the real change and it is the point: Azure compiles during a cascade for the first time.

**Exit:** the fork's template-sync PR merged and one ordinary cascade green with Azure in the reactor.

### Phase 3: Sync surgery, no filtered sync merged

Plant `.github/upstream-filter.yml` on the fork's `main` by ordinary PR and set the service slug variable. Then merge the template-sync PR carrying the new `sync.yml`. Then disable the scheduled sync.

**Exit:** one manually dispatched sync run inspected without merging its PR. The generated manifest matches the filter's own report for that day's upstream tip (88 files against the tip the prototype measured; upstream will have advanced), with no `provider/` or `devops/` paths, both injected Azure blocks present, and `Upstream-Sha` plus `Filter-Rev` trailers on the generated commit.

### Phase 4: Cutover

The one irreversible step, and the only phase that is not independently mergeable.

Freeze the three workflows that can react to the merge, merge the sync PR, run the restore on `fork_integration`, dispatch the cascade by hand, review the release PR, merge, unfreeze. The cascade will not self-trigger here because `fork_upstream` is already merged, so the monitor's commit count is zero.

**Exit:** `main` and `fork_integration` carry the 59 Azure files, `fork_upstream` carries no `provider/`, the merge base of `fork_integration` and `fork_upstream` contains neither Azure tree, a subsequent sync opens no PR, and the Docker build was green on the release PR.

### Phase 5: New-fork path and cleanup

`init-complete.yml` generates a filtered `fork_upstream` and seeds the Azure trees, rehearsed end to end in a sandbox before it ships. The seventh `fork-resources` allowlist entry lands. Stale dependabot branches and PRs close, the dependabot directory list drops `*-core-plus` and stops excluding the now fork-owned `testing/` Azure module, and the documentation surfaces are rewritten.

New fork initialization is frozen from now until this lands. A fork created before it gets a verbatim 421-file `fork_upstream` and needs a cutover of its own, which is the one thing this whole program exists to make unnecessary.

**Exit:** a sandbox fork initializes from scratch with a filtered `fork_upstream` and seeded Azure trees, with no cutover.

Implementation notes, recorded as shipped:

- The config is materialized exactly once per run into the runner's temp directory, from a hand-planted `.github/upstream-filter.yml` on `main` when one exists (the escape hatch for nonconventional services), else by `<service>` substitution of the fork-resources template. Generation, seeding, stamping, and the planted copy all read that one file, so the planted config always matches the first commit's `Filter-Rev`.
- The first generation is a single-parent commit on the upstream tip: `generate-branch.sh` accepts an empty base and skips the no-change comparison. A retried run finds the pushed branch, passes it as the base, and converges as an ordinary incremental generation; `fork_upstream` is never force-pushed.
- Seeding, stamping, and config planting happen on `fork_integration` between the sync-config apply and its push, so the seed rides the existing `-X theirs` merge to `main`, the push-protection handler covers its push, and the branch compiles with the azure profile from day one.
- `seed-source.sh` resolves each Azure tree independently against the newest commit containing it, walking the deletion commit's parents when simplified history returns nothing. The seed commit records both source SHAs as trailers.
- A run that fails after `INITIALIZATION_COMPLETE` is set resumes with configuration steps only, because settings-apply may already have armed the rulesets that would reject the branch pushes.

## Risks

**No compiler sees the generated tree before `main`.** A filter bug that produces a structurally plausible but wrong pom reaches production unopposed. Retired in Phase 2 on an unfiltered tree for roughly ten minutes of CI, where a failure means the build configuration is wrong rather than the filter. A second free gate already exists and is unused: pushing the restore commit to `fork_integration` triggers validation on that branch.

**The cutover restore can silently no-op.** Three independent mechanisms, none visible from inside a single workflow: the conflict detector misses `UD`, a filesystem-glob assertion still passes when git leaves an unmerged file on disk, and the self-heal arm can force-push the restore away. Retired by three one-line changes in Phases 0 and 2, each converting a silent wrong result into a red run.

**Merging the engine distributes it.** No staging exists between template `main` and every fork's next nightly sync. Retired by making the harness a required check before the engine directory is ever merged, which is a settings change rather than code.

## ADR-038 amendments

Four corrections, applied in one pass across the ADR and its catalog entry (which had repeated two of them).

1. The cascade stamp is defined by its post-condition, that no pre-bump version survives in the fork-owned poms, not by a count of `<parent><version>` sites.
2. The file counts become 421 to 88 against the current upstream tip.
3. The claim that Azure compilation is validated during the cascade becomes a statement of what Phase 2 makes true, since it is false today in both halves.
4. The `.fossa.yml` handling names `analyze.modules` as the key, and records that the Azure module entry is deliberately dropped rather than injected: the fork strips `.gitlab-ci.yml` and runs no FOSSA analysis of its own, so an injected entry would be a second fork-maintained block that nothing consumes.
