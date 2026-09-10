# Fork Lifecycle

This runbook takes a service fork from nothing to a repository whose pull requests are proven against a stack environment, and back to nothing. It covers the tier described in [Fork Tiers](../architecture/fork_tiers.md) as the service repository itself: a repository created from this template inside the organization that owns the service. A customer-tier fork follows [Adoption](../workflows/adoption.md) instead.

Each step ends with the observation that proves it worked. Do not move on without it.

## Before you start

- Admin on the GitHub organization that will hold the fork, so you can create the repository and read its variables.
- The organization already carries `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` as organization secrets, or you can set them on the repository as [Initialization](../workflows/initialization.md) describes.
- The `spi` CLI installed from a release of `Azure/osdu-spi-stack`, connected to the environment the fork will borrow: `spi connect --resource-group <rg> --cluster <cluster>`, then `spi status` reports deployable.
- `az` logged in to the subscription that holds that environment, with rights to update federated credentials on both of its identities, the deployer and the no-access identity.

## Establish

### 1. Clear the name

A repository name that was used before leaves container packages behind in GHCR when the repository is deleted. A package no longer linked to any repository refuses pushes from a new repository's workflow token, so the first Docker Push on the recreated fork fails.

```bash
gh api --paginate "orgs/<org>/packages?package_type=container" --jq '.[] | "\(.name) \(.repository.full_name // "unlinked")"'
```

Delete any unlinked package that carries the service's name (`<service>`, `<service>-acceptance`, `<service>-fork`). GitHub keeps a deleted package restorable for thirty days.

```bash
gh api --method DELETE "orgs/<org>/packages/container/<service>-acceptance"
```

Proof: the listing no longer shows an unlinked package with the service's name.

### 2. Create the repository from the template

```bash
gh repo create <org>/<service> --template Azure/osdu-spi --public
```

Proof: within a minute the repository has an open issue titled "Repository Initialization Required".

### 3. Name the upstream

Reply to that issue with the upstream repository, as a full URL for GitLab or `owner/name` for GitHub.

```
https://community.opengroup.org/osdu/platform/system/<service>
```

Initialization appends `.git` itself.

The reply starts the `Initialize Complete` workflow. It generates the filtered `fork_upstream`, seeds the Azure trees on `fork_integration`, deploys the fork workflows, applies the rulesets, and closes the issue. Expect four to six minutes.

Proof: the issue is closed, and the repository has the three branches and the two initialization variables.

```bash
gh api repos/<org>/<service>/branches --jq '.[].name'
gh variable list --repo <org>/<service>
```

`UPSTREAM_REPO_URL` names the upstream and `INITIALIZATION_COMPLETE` is `true`.

### 4. Add the service descriptor

The deploy lane needs `.spi/service.yaml` to know which suites to bake and run. Write it as [Service Descriptor](service-descriptor.md) describes and open a pull request with it.

Proof: on that pull request, the Deploy Gate job reports "repository is not onboarded to a stack" and names the five missing values. That is the correct refusal at this point; the Validation Summary is still green.

## Onboard

### 5. Trust the fork from the environment

```bash
spi onboard <service> --repo <org>/<service>
```

The plan prints three phases: the repository values and the `spi-stack` environment, the federated credentials on the environment's deploy and no-access identities, and the trusted-repositories annotation on the cluster. A repository created for the first time shows every row missing. A repository recreated under a name that was trusted before shows the credentials as drifted, because the OIDC subject carries the repository id and the id changed with the recreation. Both are what `--write` fixes.

```bash
spi onboard <service> --repo <org>/<service> --write
```

Proof: every row reads correct. The five values are on the repository:

```bash
gh variable list --repo <org>/<service>
gh secret list --repo <org>/<service>
```

`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `SPI_STACK_RESOURCE_GROUP`, and `SPI_STACK_CLUSTER` are variables; `AZURE_CLIENT_ID` is a secret.

Onboard cannot prove the credential itself, because only a workflow run in the fork's `spi-stack` environment can mint the fork's OIDC token. The next step does.

### 6. Prove a change

Push a build-relevant change to the descriptor pull request, or open a new one. A change under `provider/`, `testing/`, `.mvn/`, or a `pom.xml` counts; a change confined to `.github/`, docs, or other dotfiles does not, and Check Paths skips the build.

Proof: the Deploy and Test job runs. Its "Log in as deploy identity" step succeeding is the proof of the credential. The pull request comment from Validation Summary lists every job and one verdict line per suite, and the job's Restore step returns the service to the canonical image.

Merge the pull request. The push to `main` runs the lane again on the merged digest.

## Operate

- **Every same-repository pull request that pushes an image borrows the environment.** A docs-only change skips the build and never borrows. Pull requests that do borrow wait on each other through the per-service concurrency group.
- **A pull request from another repository never borrows.** The gate names the refusal; a maintainer who wants to prove such a change pushes it to a branch in the fork.
- **`spi onboard <service> --repo <org>/<service>`** without `--write` is the drift check. Run it when the lane's login step starts failing.
- **A required reviewer on the `spi-stack` environment** holds every borrow for a human. Add one in the repository's environment settings; the workflow needs no change.

## Retire

Order matters: revoke trust before the repository disappears, or the environment keeps a credential for a repository id that no longer exists.

### 7. Revoke trust

```bash
spi onboard <service> --remove
spi onboard <service> --remove --write
```

Proof: `spi onboard --list` no longer lists the repository for the service. The repository's own values and environment are left to its owner; deleting the repository removes them.

### 8. Delete the repository and its packages

```bash
gh repo delete <org>/<service>
```

Then delete the container packages the repository published, as in step 1. A package left behind blocks the next repository of the same name.

Proof: the package listing shows nothing under the service's name.
