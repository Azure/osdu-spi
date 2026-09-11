# Fork Lifecycle

Create, initialize, test, and retire a service repository. This page covers the service repository tier described in [Fork Tiers](../architecture/fork_tiers.md): a repository created from this template inside the organization that owns the service. A customer fork follows [Customer Fork Adoption](../workflows/adoption.md) instead.

Each step ends with an expected result. Check it before you move on.

## Prerequisites

- `gh` signed in as an admin of the GitHub organization that will hold the repository, so you can create it and read its variables.
- `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` set as organization secrets, or ready to set on the repository as [Initialization](../workflows/initialization.md) describes.
- The `spi` CLI, installed from a release of `Azure/osdu-spi-stack` and connected to the stack environment the repository will test against: run `spi connect --resource-group <rg> --cluster <cluster>`, then check that `spi status` reports the environment as deployable.
- `az` signed in to the subscription that holds that environment, with rights to update federated credentials on both of its identities: the deploy identity and the no-access identity.

## Create and initialize

### 1. Delete orphaned container packages

Deleting a repository leaves its container packages in GHCR. A package that is no longer linked to a repository rejects pushes from a new repository's workflow token, so a repository recreated under a name that was used before fails its first Docker Push.

List the organization's container packages and the repository each one is linked to:

```bash
gh api --paginate "orgs/<org>/packages?package_type=container" --jq '.[] | "\(.name) \(.repository.full_name // "unlinked")"'
```

Delete each unlinked package named `<service>`, `<service>-acceptance`, or `<service>-fork`. For example:

```bash
gh api --method DELETE "orgs/<org>/packages/container/<service>-acceptance"
```

GitHub keeps a deleted package restorable for thirty days.

**Expected result:** the listing shows no unlinked package with the service's name. For a name that was never used, there is nothing to delete.

### 2. Create the repository from the template

```bash
gh repo create <org>/<service> --template Azure/osdu-spi --public
```

**Expected result:** within a minute, the repository has an open issue titled "Repository Initialization Required".

### 3. Configure the upstream repository

Reply to the initialization issue with the upstream repository: a full URL for GitLab, or `owner/name` for GitHub. Leave off `.git`; initialization adds it.

```
https://community.opengroup.org/osdu/platform/system/<service>
```

The reply starts the `Initialize Complete` workflow, which takes four to six minutes. It creates the filtered `fork_upstream` branch, adds the Azure provider and test code to `fork_integration`, deploys the fork workflows, applies the rulesets, and closes the issue.

**Expected result:** the issue is closed, the repository has the `main`, `fork_upstream`, and `fork_integration` branches, `UPSTREAM_REPO_URL` names the upstream, and `INITIALIZATION_COMPLETE` is `true`.

```bash
gh api repos/<org>/<service>/branches --jq '.[].name'
gh variable list --repo <org>/<service>
```

### 4. Add the service descriptor

The deploy lane reads `.spi/service.yaml` to learn which test suites to build into the acceptance image and run. Clone the repository and create a branch for the descriptor:

```bash
gh repo clone <org>/<service>
cd <service>
git switch -c add-service-descriptor
```

Write `.spi/service.yaml` as [Service Descriptor](service-descriptor.md) describes. Then commit it and open a pull request against `main`:

```bash
git add .spi/service.yaml
git commit -m "chore: add service descriptor"
git push -u origin add-service-descriptor
gh pr create --base main --fill
```

Leave the pull request open; step 6 uses it.

**Expected result:** the Deploy Gate job reports "repository is not onboarded to a stack" and lists the five missing values. This is expected before onboarding, and the Validation Summary check still passes.

## Onboard to a stack environment

Onboarding lets the repository's workflows borrow the stack environment. A borrow deploys a candidate image of the service to the stack, runs the descriptor's suites against it, and restores the canonical image afterward.

### 5. Onboard the repository

Run the onboarding plan first. It changes nothing:

```bash
spi onboard <service> --repo <org>/<service>
```

The plan has three groups of rows: the repository values and its `spi-stack` environment, the federated credentials on the environment's deploy and no-access identities, and the trusted-repositories annotation on the cluster. For a new repository, every row reads missing. For a repository recreated under a name that was onboarded before, the credentials read drifted: the OIDC subject includes the repository id, and recreating the repository changed the id. In either case, apply the plan:

```bash
spi onboard <service> --repo <org>/<service> --write
```

**Expected result:** running the plan again shows every row as correct, and the repository has the five values:

```bash
gh variable list --repo <org>/<service>
gh secret list --repo <org>/<service>
```

`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `SPI_STACK_RESOURCE_GROUP`, and `SPI_STACK_CLUSTER` are variables; `AZURE_CLIENT_ID` is a secret.

Onboarding can't test the credential itself, because only a workflow run in the repository's `spi-stack` environment can get the repository's OIDC token. Step 6 tests it.

### 6. Test a change in the environment

Push a change that triggers a build to the descriptor pull request, or open a new pull request. Changes under `provider/`, `testing/`, or `.mvn/`, or to a `pom.xml`, trigger a build. A pull request that changes only `.github/`, other dot-directories such as `.spi/`, or Markdown files skips the build and deploys nothing.

**Expected result:** the Deploy and Test job runs, and its "Log in as deploy identity" step succeeds, which confirms the federated credential. The Validation Summary comment on the pull request lists every job and one result line per suite. The job's Restore step returns the service to its canonical image.

Merge the pull request. The push to `main` runs the deploy lane again with the image built from the merge.

## Operate the repository

- **Pull requests that push an image borrow the environment.** A docs-only change skips the build and deploys nothing. Pull requests queue behind each other in a per-service concurrency group, so only one run at a time deploys the service.
- **Pull requests from other repositories never borrow.** The Deploy Gate reports why. To test such a change, a maintainer pushes it to a branch in this repository.
- **Check for drift** by running `spi onboard <service> --repo <org>/<service>` without `--write`. Run it when the "Log in as deploy identity" step starts failing.
- **Require approval before each borrow** by adding a required reviewer to the repository's `spi-stack` environment in its settings. The workflow needs no change.

## Retire the repository

Remove the repository from the environment before you delete it. Otherwise the environment keeps a credential for a repository id that no longer exists.

### 7. Remove the repository from the environment

The first command shows what will be removed; the second removes it:

```bash
spi onboard <service> --remove
spi onboard <service> --remove --write
```

**Expected result:** `spi onboard --list` no longer lists the repository for the service. The repository's own values and `spi-stack` environment stay in place until the repository is deleted.

### 8. Delete the repository and its packages

```bash
gh repo delete <org>/<service>
```

Then delete the container packages the repository published, as in step 1. A package left behind blocks the next repository created with the same name.

**Expected result:** the package listing from step 1 shows nothing with the service's name.
