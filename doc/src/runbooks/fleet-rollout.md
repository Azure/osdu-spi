# Fleet Rollout

A change that every service fork needs, such as a template update, reaches the forks one pull request each. Each of those pull requests, and each merge to `main`, borrows the shared backing environment. This runbook rolls such a change out without starting more lanes than the environment can take. Its settings are in `.github/fleet/rollout.json` (ADR-045).

## Before you start

- The fleet is the `forks:` list in osdu-spi-stack `ops/environments/shared.yaml`. A fork is in a rollout once the stack declares it.
- `lanes` in `rollout.json` is the number of deploy lanes allowed at once.
- Check the environment is deployable with `spi status` before the first group.

## Open the pull requests

Dispatch the template sync for `lanes` forks:

```bash
gh workflow run sync-template.yml -R Azure/osdu-spi-<service>
```

Dispatch the next forks only after the previous ones show no pending runs.

## Watch

```bash
python3 .github/skills/spi-fleet/fleet.py watch --wait
```

Each fork is judged by the Validation run for its PR's head SHA.

| Result | What to do |
|---|---|
| `environment` | Deploy and Test timed out on the shared backing environment (an error titled `Environment`). Check `spi status`, then rerun the failed jobs once after the other lanes drain: `gh run rerun <id> --failed -R Azure/osdu-spi-<service>` |
| `real` | A failure of the change, or an environment failure that came back after its rerun. Stop the rollout and fix it forward in the template. Never patch a fork by hand. |

## Merge

```bash
python3 .github/skills/spi-fleet/fleet.py merge        # print the groups
python3 .github/skills/spi-fleet/fleet.py merge --go   # merge them
```

`merge` merges green, approved pull requests in fleet order. A service with an ordering entry, such as search, waits for the services it names. Before each group it counts the Validation runs already queued or running across the fleet and merges only into the free lanes, so a group can be smaller than `lanes`. After each group it waits for the push run on `main` for each merge SHA. It stops on any failed run, and on any pull request that did not merge.

A merge that changed only paths Validation ignores starts no push run. After `--grace` seconds (default 600) it shows as `unvalidated` and the rollout continues.

Each merge is appended to `fleet-merge-<date>.jsonl` as it happens, with its merge SHA and the `main-snapshot` digest it replaced, which is the last-good pin if a forward fix is slow. A `validated` record with the main run's result follows once that run finishes.

## Change the rollout

Raise `lanes` in `.github/fleet/rollout.json` once a rollout at the current value runs clean. A new environment timeout in Deploy and Test gets the annotation title `Environment` on its `::error` line. Run:

```bash
bash .github/local-actions/spi-fleet-tests/run-tests.sh
```
