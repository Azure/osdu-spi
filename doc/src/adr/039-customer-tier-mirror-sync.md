# ADR-039: Customer-Tier Forks and Mirror-Mode Sync

## Context

ADR-038 defines how a service fork receives upstream changes: sync generates a filtered `fork_upstream` from the upstream project's tip, the cascade merges it with the fork-owned Azure trees, and `main` becomes the finished product. Shared code, the Azure implementation, the workflows, and the filter configuration all live together on `main`.

A consumer organization outside the fork's own organization needs to act as a full developer on that product: a live-syncing fork of the service repository in their own org, building and deploying with their own credentials, with a contribution path back. Two structural facts shape the design.

First, contribution requires the fork network. A pull request's head branch must live in the target repository's fork network, so the consumer repository must be a true GitHub fork of the service repository. A template instantiation, however configured, can never open a PR against it. A fork also inherits every deployed workflow from the parent's `main`, but not the initialization workflows, which the parent's own initialization deleted.

Second, the parent's `main` is already the finished product. Running the ADR-038 filter against it would destroy what the consumer wants: the engine halts on top-level entries the per-service config never classifies (`.github/`, `build/`, `CHANGELOG.md`, `doc/`, `Dockerfile`), and it strips the entire `provider/` tree wholesale, which at this tier is the code the consumer needs most. The filter is a tool for reducing an upstream project's tree to the product. Applied to the product itself it has nothing to do but damage.

The tiers also cannot be told apart by looking at the tree. `.github/upstream-filter.yml` is present on both: fork-owned at the first tier, and arriving through the sync itself at the second, where deleting it would create a permanent difference against the upstream that ships it.

## Decision

**A second tier of forks mirrors the first tier verbatim. The tier is selected by a repository variable, adoption replaces initialization, and every filter-dependent step is off at the mirror tier.**

```text
Upstream project repository
        |
        |  sync, filter mode: classify, strip, inject (ADR-038)
        v
Service repository main        (the finished product)
        |
        |  sync, mirror mode: verbatim tip, same plumbing
        v
Customer fork main             (the same product, plus local work)
```

The customer fork runs the same three-branch model, the same workflows, and the same cascade. Only the sync's tree source and the filter-dependent steps differ.

### The tier is a repository variable

The repository variable `SYNC_MODE` selects the behavior: `mirror` selects the customer tier, and unset or `filter` preserves existing behavior. No first-tier fork or template sets the variable, so every existing repository is unaffected. A variable is the only reliable selector: the filter configuration file exists on both tiers, arrives at the customer tier through the mirror, and cannot be removed there without permanently diverging from upstream. The adoption workflow sets the variable once; `sync.yml`, `cascade.yml`, `sync-template.yml`, and `validate.yml` read it.

### Mirror generation reuses the generate-not-merge plumbing

Mirror mode changes one thing inside `generate-branch.sh`: the tree. Instead of extracting, filtering, and re-serializing, the generated tree is the upstream tip's own tree object. Everything else is shared with filter mode: the no-op detection by tree equality, the merge-shaped commit whose first parent is the previous `fork_upstream` tip and whose second parent is the upstream tip, the first-generation single-parent case, and the `Upstream-Sha` trailer. The `Filter-Rev` trailer carries the literal sentinel `mirror`, so every commit on a mirror `fork_upstream` still states exactly how it was produced. The filter engine never runs, no report is produced, and the config argument is accepted but never read.

Keeping one code path matters more than the two lines it saves. The sync branch, the PR into `fork_upstream`, duplicate detection, the meta commit, the cascade trigger, and the release PR all behave identically at both tiers because they only ever see a commit and a tree.

### Filter-dependent steps are off, not vacuous

Two cascade steps exist to defend the first tier's ownership split: the assertion that the fork-owned Azure trees survived the merge, and the version stamp on the fork-owned poms. At the mirror tier there is no ownership split. The Azure trees are upstream-owned content that arrived through the mirror, so the assertion can only pass vacuously, and the stamp is strictly a liability: any rewrite it ever made would land in pom lines the upstream also owns and edits, creating a permanent divergence and a merge conflict on every future upstream version bump. Both steps are gated off when `SYNC_MODE` is `mirror`, regardless of the config file's presence.

Template sync is off entirely at this tier. Workflow and configuration updates reach the customer fork through the mirror of the parent's `main`, which is where the template's changes land after the parent's own template sync. A second delivery channel would fight the first: it would overwrite files the mirror also delivers and would plant a filter config derived from the wrong repository name. One channel, the mirror, carries everything.

Validation regains coverage instead. At the first tier, sync PRs build `core` only because the filtered tree has no `provider/`. At the mirror tier `fork_upstream` carries the full product, so sync PRs build the full profile set and a broken Azure module fails on the sync PR rather than later inside the cascade. Container validation follows the same rule: the Docker build worker, skipped on provider-less filter-mode sync PRs, runs at the mirror tier where the Azure JAR exists, so the required Docker check reports a real result instead of a pass for a skipped build.

### Adoption replaces initialization

A fork of an initialized repository needs no content: `main` is the parent's `main` at fork time, and it carries the engine, the rulesets, the label definitions, and the settings scripts. What it lacks is state. The shipped `Adopt Fork` workflow (`workflow_dispatch`) supplies it:

- `fork_upstream` and `fork_integration` created at the merge base with the upstream's default branch: for a fresh fork that is the tip itself, and for a fork whose `main` was customized before adoption it is the fork point. Pre-adoption local commits must never enter the `fork_upstream` lineage, or the first mirror sync's three-way merge would revert them off `main`
- the system labels from `.github/labels.json`
- the branch rulesets via the same idempotent script the settings cadence uses
- repository settings the cascade depends on (auto-merge, merge commits)
- the variables: `UPSTREAM_REPO_URL` (auto-detected from the fork's GitHub parent, overridable by input), `SYNC_MODE=mirror`, and `INITIALIZATION_COMPLETE` last

The workflow refuses to run where `INITIALIZATION_COMPLETE` is already `true`, which protects every first-tier fork inheriting it. Ordering is the idempotency design: the completion variable is both the entry guard and the final mutation, so a partially failed adoption is simply re-dispatched and completed steps skip or reconcile. Authentication uses the consumer organization's own GitHub App, the same two secrets every other write path already requires.

## Consequences

### Positive

- A consumer organization operates a full developer loop on a service repository without any access to the parent organization: live sync in, their own build and release, contribution PRs back through the fork network.
- One engine, one sync workflow, one cascade at both tiers. Mirror mode is a tree-source switch plus three gates, not a parallel machinery.
- The filter runs exactly once per change, at the first tier. The mirror tier inherits its output verbatim, so a classification decision never has to be made twice.
- Every existing repository is untouched. The mode variable defaults to today's behavior, and nothing at the first tier reads it as anything but unset.

### Negative

- Releases on both tiers touch the same files. The customer's release automation commits to `CHANGELOG.md` and the release manifest on their `main`, and the mirror delivers the parent's own edits to the same files, so a sync that follows releases on both sides can conflict there. The conflicts are shallow and mechanical (keep both changelog entries, keep the local manifest value) and flow through the existing cascade conflict process. Making those files fork-owned at the mirror tier would itself require editing mirrored configuration, which is the same permanent-difference problem in different clothes.
- Any customer change to `main` outside their own feature work is a standing difference against the mirror and will surface in every sync until it is contributed upstream or reverted. This is inherent to being a mirror, not a defect: the model tolerates it because `main` only receives the mirror through merges, never resets.
- Sync PR validation at the mirror tier builds the full profile set, so it needs the consumer's build secrets before the first sync merges, slightly earlier than the first tier requires them.
- The fork-owned path assertion is off at this tier, so an upstream deletion of the Azure trees would mirror through silently. At this tier that is correct behavior: the parent repository is the authority on its own product.

### Neutral

- The `Filter-Rev: mirror` sentinel keeps the trailer contract intact, so tooling that reads generation provenance needs no special case.
- `Adopt Fork` ships to every fork as an inert workflow. First-tier forks carry it but cannot run it past the guard.
- The deploy and integration-test required checks are stripped by the existing readiness filter at adoption time, exactly as on a first-tier fork that has not onboarded to deployment.

## Alternatives Considered

- **Template instantiation pointing at the service repository as upstream.** Rejected. No fork network, so no contribution path; and initialization would run the filter against the finished product, which halts by design.
- **A permissive per-tier filter configuration instead of a mode.** Rejected. The wholesale `provider/` strip is hardcoded ahead of any configuration, and a config that classified the entire product tree would be a maintenance surface whose only purpose is to make the filter do nothing.
- **Selecting the mode from the tree or the config file.** Rejected. The config file exists on both tiers and arrives at the mirror tier through the sync itself; structure-based detection would misclassify exactly when it matters most, mid-transition.
- **Plain merge sync at the mirror tier.** Rejected. The generate-not-merge plumbing is already proven, produces identical no-op and provenance semantics at both tiers, and avoids reintroducing a second sync mechanism that the duplicate-prevention and meta-commit layers would have to special-case.
- **Disabling release automation at the mirror tier to avoid the changelog conflicts.** Rejected. The consumer needs their own release line for their own deployments; a recurring shallow conflict is a fair price for it.

---

[← ADR-038](038-upstream-filter-transform.md) | :material-arrow-up: [Catalog](index.md)
