# Adoption (Customer-Tier Onboarding)

This runbook takes an organization outside the service repository's own org from nothing to a live-syncing, buildable customer-tier fork. The result is described in [Fork Tiers](../architecture/fork_tiers.md): a true GitHub fork that mirrors the service repository's `main`, builds with your own credentials, and can contribute PRs back.

Adoption replaces initialization. A fork of an initialized repository inherits every deployed workflow and all configuration from the parent's `main`; what it lacks is state (branches, labels, rulesets, settings, variables), and the `Adopt Fork` workflow supplies exactly that.

## Prerequisites

### 1. Create your organization's GitHub App

The workflows authenticate their write operations through a GitHub App, never through personal tokens. Create one in your org (`Settings > Developer settings > GitHub Apps`) with these repository permissions:

| Permission | Level | Used for |
|---|---|---|
| Contents | Read and write | Branch pushes, releases |
| Pull requests | Read and write | Sync, cascade, and release PRs; auto-merge |
| Administration | Read and write | Rulesets, repository settings |
| Variables | Read and write | Repository variables (a separate permission; Administration does not cover it) |
| Secrets | Read-only | The settings cadence reads secret names for deploy-readiness checks |
| Workflows | Read and write | Workflow file updates arriving through sync |
| Issues | Read and write | Tracking and failure issues, labels |

Generate a private key, and install the App on your organization (covering the fork you are about to create).

### 2. Fork the service repository

Fork the service repository into your organization through GitHub (keep "Copy the default branch only" checked). It must be a true GitHub fork: contribution PRs can only be opened from within the parent's fork network, and adoption auto-detects your upstream from the fork's parent.

After forking, open the fork's **Actions** tab and enable workflows (GitHub disables inherited workflows on new forks until a person enables them). Nothing runs until you do, including adoption itself.

That bulk enable does not reach workflows carrying a `schedule:` trigger. On a new fork they stay in state `disabled_fork`, which suppresses manual dispatch as well.

In this repository, those are:

- `sync.yml`
- `cascade-monitor.yml`
- `settings-apply.yml`
- `codeql.yml`
- `ghcr-retention.yml`
- `sync-template.yml`
- `scorecard.yml`

Adoption re-enables the fork-disabled workflows for you, but it deliberately leaves `sync-template.yml` disabled (ADR-039 gates template sync off at this tier because the mirror is the single delivery channel for workflow and configuration updates) and `scorecard.yml` disabled (it is inert on a fork as noted under [Gotchas](#gotchas)).

### 3. Set the required secrets

On the fork (`Settings > Secrets and variables > Actions`):

| Secret | Required | Purpose |
|---|---|---|
| `RELEASE_APP_ID` | Yes | Your GitHub App's ID |
| `RELEASE_APP_PRIVATE_KEY` | Yes | Your GitHub App's private key (PEM) |
| `GITLAB_TOKEN` | For OSDU Java services | Community Maven registry access for builds |
| `OPENGROUP_MAVEN_USERNAME` | For OSDU Java services | Community Maven credentials used by validation |
| `OPENGROUP_MAVEN_TOKEN` | For OSDU Java services | Community Maven credentials used by validation |
| `AZURE_API_KEY`, `AZURE_API_BASE`, `AZURE_API_VERSION` | Optional | AI-enhanced PR descriptions; everything degrades to templated text without them |

Set the build secrets before merging your first sync PR: mirror-mode sync PRs build the full profile set, so they need registry access from the start.

## Run Adoption

Dispatch the **Adopt Fork** workflow from the Actions tab. No inputs are needed in the normal case; `upstream_repo_url` exists as an override for the unusual situation where the repository is not a GitHub fork.

What it does, in order:

1. Refuses if the repository is already initialized (`INITIALIZATION_COMPLETE` is set). This protects first-tier forks, which also carry this workflow.
2. Mints a token from your App and detects the upstream from the fork's GitHub parent.
3. Creates `fork_upstream` and `fork_integration` at the merge base with the upstream's default branch: the tip itself on a fresh fork, the fork point on a fork whose `main` was already customized. Local commits stay local instead of being reverted by the first sync.
4. Creates the system labels the sync and cascade machinery uses.
5. Sets `UPSTREAM_REPO_URL` and `SYNC_MODE=mirror`.
6. Applies the branch rulesets (the deploy and integration-test required checks are automatically stripped because the deploy-tier credentials are absent).
7. Enables auto-merge and merge commits (the cascade's release PRs depend on both).
8. Enables secret scanning and push protection (best effort; a warning tells you to enable them manually if the API declines).
9. Re-enables the workflows that forking left disabled, apart from `sync-template.yml` and `scorecard.yml`.
10. Sets `INITIALIZATION_COMPLETE=true`, last, and writes a summary.

**Re-run semantics**: the completion variable is both the guard and the final step. If adoption fails partway, fix the cause and dispatch it again; completed steps skip or reconcile. After a fully successful run, re-dispatching refuses by design.

## First Sync and Cascade

1. Dispatch **Sync Upstream** (it also runs nightly). It opens a PR into `fork_upstream` whose tip commit is merge-shaped, carries `Upstream-Sha` and `Filter-Rev: mirror` trailers, and whose tree is byte-identical to the parent's `main`.
2. Review and merge the sync PR. The cascade triggers automatically, merges `main` and `fork_upstream` into `fork_integration`, builds the full profile set, and opens a release PR to `main` with auto-merge armed.
3. **Always merge release PRs with a merge commit, never squash.** Squashing breaks the branch ancestry the cascade monitor relies on.

## Gotchas

- **CODEOWNERS**: the fork inherits the parent's `CODEOWNERS` with handles from the parent organization. Replace it with your own reviewers or delete it; unresolvable handles fail the file's validation.
- **Release conflicts**: your release automation and the parent's both write `CHANGELOG.md` and `.release-please-manifest.json`. When both sides have released since your last sync, the cascade can hit a shallow conflict in those files. Resolution recipe: keep both changelog entries, keep your own manifest value. This is the accepted trade-off of ADR-039.
- **Standing differences**: any change you keep on `main` that is not upstream shows up as your side of every future cascade merge until it is contributed upstream or reverted. Prefer contributing back (the loop exists for exactly that).
- **Container images**: builds publish to your own namespace, `ghcr.io/<your-org>`, automatically. No registry configuration is needed for the default GHCR flow.
- **Contribution PRs**: the first PR a new contributor opens against the parent requires a maintainer there to approve the workflow run before checks execute. Credential-bearing jobs never run for external heads regardless; build and validation give the real signal.
- **`scorecard.yml`**: inherited but guarded to the template's own repository name; it is inert on your fork.
- **Adopt before customizing** (recommended, not required): adoption pins the sync branches at the merge base with the upstream, so local commits made before adoption stay local instead of being reverted by the first sync. They still become standing differences that surface in every cascade until contributed upstream or reverted.
