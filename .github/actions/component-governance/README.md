# Component Governance

The steps of the Component Governance pipeline, `.azuredevops/component-governance.yml`
(ADR-047). The pipeline runs in Azure DevOps, not in GitHub Actions, so this directory
has no `action.yml`: the pipeline calls the scripts directly. Both sync to every fork,
the directory with `.github/actions` and the pipeline as a `sync-config.json` file entry.

## What the pipeline does

```text
cg_scan   "Register shipped components"            (1ES Official, network isolated)
  resolve_inputs.py   descriptor -> MAVEN_ARGS, dockerImagesToScan, IgnoreDirectories, cgmanifest.json
  wait_images.py      wait for Validation's Docker Push of the commit, then drop the GitHub token
  JDK + Maven         the pom's Java release, checksum-verified
  [1ES CG step]       registers after isolation stops: Maven graph, images, cgmanifest
cg_notice "Generate NOTICE from Component Governance" (CG disabled for this job)
  fetch_notice.py     this build's snapshot -> NOTICE + gap report (artifact cg-notice)
  notice_pr.py        weekly, or with openNoticePr: draft PR chore/notice-refresh/<branch>
```

Triggers: `v*` tags (not `v*-upstream-*`), and every Monday 06:00 UTC on `main`, which also
opens or updates the NOTICE pull request. Parameters: `images` (`auto`, or an explicit comma
separated list) and `openNoticePr`, which opens the pull request from a manual run.

## Inputs

`.spi/service.yaml` carries a `componentGovernance` section, validated by the acceptance
resolver's descriptor contract (`service-descriptor.schema.json`):

```yaml
componentGovernance:
  upstream: https://community.opengroup.org/osdu/platform/system/partition   # required, no .git
  image: osdu-spi-partition                 # default: the repository name; set to the fork's SERVICE_NAME
  module: provider/partition-azure          # default: the Spring Boot module under provider/*-azure
  profiles: [core, azure]                   # default: [core, azure]
  ignoreDirectories: [partition-acceptance-test/python]   # not scanned; must not contain module
```

| Output | Value |
| --- | --- |
| `MAVEN_ARGS` | `--settings=<checkout>/.mvn/community-maven.settings.xml -P <profiles> -pl <module> -am`. Maven 3.9+ reads it when the Maven detector runs `dependency:tree`, so detection covers the shipped module and its parents only. |
| `dockerImagesToScan` | `ghcr.io/<owner>/<image>:sha-<12>`, plus `<image>-load:sha-<12>` when `deployments/shared-schemas` is not empty. Validation names both by the fork's `SERVICE_NAME` variable, which Azure DevOps cannot read, so a fork that sets it repeats it as `image`. |
| `cgmanifest.json` | The upstream commit of the newest generated upstream tree (its `Upstream-Sha`, which must equal its last parent), every `Seeded-From` commit, and the Application Insights agent version from `build/Dockerfile`. No detector sees these. |
| `cg-inputs.json` | Everything above, in the `cg-scan` artifact. |

## The image gate

The Component Governance step only warns when it cannot pull an image, and registers
the snapshot without it. `wait_images.py` fails the job first:

- Only a successful `Docker Push` check of a **push-event** Validation run counts. A
  pull request run attaches its checks to the head commit but publishes the merge commit.
- The Azure Pipelines GitHub App cannot read the Actions API, so the gate falls back to
  check suites whose head branch is `main`, and refuses when the repository has any pull
  request from `main`, which would make that ambiguous.
- A missing run means nothing until the commit's push to `main` has **settled**: it is
  more than 10 minutes old and no workflow it started is still running. The push is dated
  by the commit's earliest check suite of `main`, which every installed app with checks
  permission gets on push, not by the commit time, which can be much older. Validation's
  `Docker Push` job starts after its build, 7 to 12 minutes after the push in the forks
  and sometimes much later, so a running Validation holds the gate. Suites created after
  the grace period, such as scheduled workflows on the same tip, do not.
- A commit that changes only paths Validation's push filter ignores publishes no image,
  and the files it changes cannot change one. Once its push has settled, the gate steps to
  its first parent, up to 50 commits, and scans that commit's images. A push whose tip is
  documentation but which also carries code publishes the tip, which is why the gate must
  not leave a push that has not settled. The harness keeps the gate's copy of the filter
  equal to `validate.yml`.
- No qualifying run once the push has settled, or no finished run after 30 minutes, fails
  the job. Explicit `images` skip the gate with a warning.
- The checkout's GitHub credential is removed on every exit, and again by an `always()`
  step, so the scan never sees it.

## The NOTICE

`fetch_notice.py` finds the snapshot this build's scan job registered (definition, job
name, build ID), downloads its NOTICE through the Component Governance API, and checks
again that no later run replaced the snapshot. It fails when the scan log shows an image
it could not process, or the snapshot holds no operating system packages. The report
lists every registered component without an entry, by reason.

`notice_pr.py` commits the NOTICE to `chore/notice-refresh/<branch>` and opens or updates
a draft pull request into the built branch. It replaces that branch only when its tip was
written by this automation and carries `Source-Commit` and `Build-Id` trailers from an
older source commit or an earlier build, and pushes with a lease on the tip it saw. The
commit skips no CI, so the pull request's required checks run. A weekly run whose refresh
branch already holds the same NOTICE for the same commit pushes nothing, so an unchanged
`main` does not rerun those checks every week; it only opens a pull request if the branch
has none.

While `.github/upstream-filter.yml` still says `NOTICE: keep`, the same commit changes it
to `strip` and the pull request body gives the one-time cutover steps: the `port` label
for the ownership check, and keeping the fork's `NOTICE` in the one modify/delete conflict
the next cascade raises.

## Local testing

```bash
bash .github/local-actions/component-governance-tests/run-tests.sh
```

The harness drives the gate and the pull request step against fixture repositories and a
scripted HTTP API (`GITHUB_API_URL`), with no network.
