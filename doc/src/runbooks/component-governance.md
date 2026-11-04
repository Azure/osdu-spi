# Component Governance

Each service fork registers what its image ships with Component Governance (CG) and keeps its `NOTICE` generated from that registration. The pipeline is `.azuredevops/component-governance.yml`, synced from the template, and it runs in Azure DevOps. This runbook connects a fork, runs it the first time, and makes `NOTICE` fork-owned. [ADR-046](../adr/046-component-governance-notice.md) records the decision, and the README in `.github/actions/component-governance/` describes each step.

## Before you start

- The fork has synced a template that contains `.azuredevops/component-governance.yml`. That sync also brings the acceptance resolver that accepts the `componentGovernance` section: add the section only after it, or the fork's descriptor check fails.
- Access to the OpenEnergyPlatform `OSDU-SPI` Azure DevOps project with permission to create pipelines, and use of the `github.com_Azure` service connection (the Azure Pipelines GitHub App).
- The fork's latest push to `main` published its image: Validation's Docker Push job succeeded.

## 1. Declare the fork's inputs

Add the section to `.spi/service.yaml` in a pull request to the fork:

```yaml
componentGovernance:
  upstream: https://community.opengroup.org/osdu/platform/system/partition
```

`upstream` is the OSDU community project, as in `NOTICE-OSDU-SPI`, without `.git`. Add the optional keys only where the defaults are wrong:

| Key | Default | Set it when |
|---|---|---|
| `module` | The Spring Boot module under `provider/*-azure` | The fork ships a module elsewhere, or has several under `provider/*-azure`. Indexer Queue sets `indexer-queue-azure-enqueue` |
| `profiles` | `[core, azure]` | The module builds with other profiles. Indexer Queue sets `[azure]` |
| `ignoreDirectories` | none | Directories that hold dependency files no image ships, such as Python acceptance suites (`crs-catalog_acceptance_test`, `testing`) or upstream's `data/` images |

The descriptor check runs on the pull request: an unknown key, a URL outside `community.opengroup.org/osdu`, or an ignored directory that contains the module fails it.

## 2. Create the pipeline

In `OSDU-SPI`, **Pipelines** > **New pipeline** > **GitHub** > the fork (`Azure/osdu-spi-<service>`, through the `github.com_Azure` connection) > **Existing Azure Pipelines YAML file** > branch `main`, path `/.azuredevops/component-governance.yml`. Save it without running and name it `<Service> CG`.

The first run asks for permission to use the `adme-custom-pool-eus2` pool, the `github.com_Azure` connection and the `1ESPipelineTemplates` repository. A project administrator grants them to this pipeline only.

## 3. Run it on main

Queue the pipeline on `main` with **Open a NOTICE pull request into the built branch** checked and images left at `auto`.

**Expected result:** both jobs succeed. The **Register shipped components** job logs the resolved inputs and `Docker Push succeeded for <sha>`. CG lists the fork as a governed repository, with the shipped module's Maven components, the image's operating system packages, the upstream commit and the Application Insights agent. The **Generate NOTICE** job publishes the `cg-notice` artifact, adds the gap report to the run summary, and opens a draft pull request from `chore/notice-refresh/main`.

## 4. Merge the first NOTICE pull request

The first refresh also changes `NOTICE: keep` to `NOTICE: strip` in `.github/upstream-filter.yml`, so upstream syncs stop replacing the generated file.

1. Read the gap report in the pull request body. It lists the shipped components the generated NOTICE has no entry for.
2. `NOTICE` is upstream-owned until this merges, so the ownership check fails. Add the `port` label and re-run Check Paths.
3. Mark the pull request ready, get it reviewed and merge it. Validation publishes the image that ships the new `NOTICE`.
4. The next upstream sync removes upstream's `NOTICE` from `fork_upstream`, and the cascade stops on one modify/delete conflict on `NOTICE` in `fork_integration`. Resolve it by keeping the fork's file:

    ```bash
    git checkout fork_integration && git merge origin/fork_upstream
    git add NOTICE && git commit --no-edit && git push origin fork_integration
    ```

    Later syncs never touch `NOTICE` again.

## Routine operation

The pipeline registers `main` every Monday at 06:00 UTC and every `v*` release tag. Compliance is read from `main`. To refresh `NOTICE`, queue a run on `main` with the pull request option; a refresh only replaces an older one, and nothing is opened when `NOTICE` already matches.

## Failures

| Message | Cause | What to do |
|---|---|---|
| `No push-triggered Docker Push run exists for <sha>` | Validation published no image for the commit | Rerun Validation on `main`, or queue with the image listed explicitly |
| `has pull requests from main` | The gate cannot tell a push run from a pull request run without Actions access | Queue with the image listed explicitly |
| `Docker Push for <sha> ended without success` | The image was not published | Fix the build, then rerun |
| `<image> could not be scanned` | The scan could not pull an image after the gate passed | Rerun; the snapshot is replaced by the next complete scan |
| `Snapshot type ... now belongs to build` | Two runs of the same branch overlapped | Rerun when no other run is in progress |
| `has commits from someone else` or `has no Source-Commit/Build-Id trailers` | The refresh branch was edited by hand | Merge or close its pull request, delete the branch, rerun |
| `componentGovernance...` from the descriptor check | The section does not match the contract | Fix `.spi/service.yaml` as the message says |
