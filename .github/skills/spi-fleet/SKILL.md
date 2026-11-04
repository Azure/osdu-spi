---
name: spi-fleet
description: Roll one change out across every SPI service fork without overloading the shared backing environment. Use when a template change, Dependabot batch, or other fleet-wide pull request has to reach all forks, when watching those pull requests, or when merging them in groups.
---

# spi-fleet

The fleet is the `forks:` list in osdu-spi-stack `ops/environments/shared.yaml`. `.github/fleet/rollout.json` sets `lanes`, the number of deploy lanes allowed at once, and the few merge-ordering exceptions. `fleet.py` reads both, so a new fork needs no edit here.

## Never

- Start more than `lanes` validations at once. Every fork PR and every main merge borrows the shared backing environment, and the environment has no queue across forks. Dispatch `gh workflow run sync-template.yml -R <repo>` for `lanes` forks, then wait until `watch` shows no pending runs before dispatching more.
- Rerun a failed run without the person's go. Rerun an environment failure once, after the other lanes drain: `gh run rerun <id> --failed -R Azure/osdu-spi-<service>`.
- Patch a fork by hand to get it green. Stop the line and fix forward in the template.
- Approve a pull request, or merge without the person's go.

## Watch

```bash
python3 .github/skills/spi-fleet/fleet.py watch --wait            # template-sync PRs, poll until nothing is pending
python3 .github/skills/spi-fleet/fleet.py watch --prefix release-please--   # any head-branch prefix
python3 .github/skills/spi-fleet/fleet.py watch --main            # the latest push run on each main
```

Each fork is judged by the Validation run for its PR's head SHA. A failure is an environment failure when Validation raised it with the annotation title `Environment`: the environment stayed undeployable, the pin stayed refused, or the digest never went live. Anything else is a failure of the change, and so is an environment failure that has already been rerun once. Exit codes: 0 green, 1 real failure, 2 pending, 3 environment failure that waits for a rerun.

## Merge

```bash
python3 .github/skills/spi-fleet/fleet.py merge          # print the groups
python3 .github/skills/spi-fleet/fleet.py merge --go     # merge them, after the person says go
```

`merge` re-reads every PR first. It merges green, approved PRs in fleet order, and ordering exceptions follow `rollout.json`. Before each group it counts the Validation runs already queued or running across the whole fleet, PR and main alike, and merges only into the lanes left free. It waits for each merge SHA's push run on main and stops the line on any failure, or on any PR that did not merge. A merge whose push changed only paths Validation ignores shows no run; after `--grace` seconds (default 600) it is reported `unvalidated` and the line carries on.

Each merge is written to `fleet-merge-<date>.jsonl` as it happens, with the PR, merge SHA, image and the `main-snapshot` digest it replaced, and a second record follows with the main run's result. When a forward fix is slow, that digest is the last-good pin the person can choose.

## Change the rollout

Raise `lanes` in `rollout.json` once a rollout at the current value runs clean. An ordering entry may name only forks in the fleet list; `fleet.py` refuses to run otherwise. A new environment failure is classified by giving its `::error` in `validate.yml` the title `Environment`, not by adding a rule here. Run `bash .github/local-actions/spi-fleet-tests/run-tests.sh`.
