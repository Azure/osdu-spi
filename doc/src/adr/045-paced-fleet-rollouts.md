# ADR-045: Paced Fleet Rollouts

## Status

Accepted (2026-11-04)

## Context

A template change reaches every service fork through a sync PR, and every sync PR and every merge to `main` runs a Borrow, Prove, Restore lane (ADR-041) on the shared backing environment. Lanes queue per service only, so a change sent to all forks at once starts every lane together. On 10/27 and 11/2 six and seven of thirteen lanes failed on the environment, and reruns stretched those rollouts to 3.5 and 7.5 hours. Five lanes at once ran clean.

Telling an environment failure from a failure of the change meant reading each failed run. Matching error text after the fact goes stale silently when a message is reworded or its cause is fixed.

## Decision

**The fleet list is the `forks:` declaration in osdu-spi-stack. No rollout starts more than `lanes` deploy lanes at once. An environment failure is marked where Validation raises it.**

- `.github/fleet/rollout.json` holds two settings: `lanes`, the number of deploy lanes allowed at once, and `ordering`, the few services that must merge after named others. An ordering entry may name only forks in the fleet list, so a fork that leaves the stack fails the next run instead of lingering.
- Deploy and Test gives its three environment timeouts the annotation title `Environment`: not deployable after 10 minutes, pin still refused after 10 minutes, and digest not live after 15 minutes. Any other failure is a failure of the change. An environment failure is rerun once, after the other lanes drain, and a second one is treated as a failure of the change.
- `.github/skills/spi-fleet/fleet.py` watches and merges a fleet-wide PR in groups of `lanes`, keyed on the Validation run for each head or merge SHA.

## Consequences

### Positive

- A new fork joins every rollout when the stack declares it.
- The classification sits on the same line as the error, so rewording a message cannot break it, and a test fails if one of the three loses its title.
- Raising `lanes` is a one-line change, made when a rollout at the current value runs clean.

### Negative

- Pacing is cooperative. Dispatching to every fork by hand, or the daily template-sync cron, still starts lanes together. Admission in the stack is the step after this one if paced rollouts still fail on the environment.
- A stack-side refusal that Validation does not time out on, such as a pin refused for a moved tag, is reported as a failure of the change, and the person decides whether to rerun.

## Alternatives Considered

- **Classify failures by matching error text in a data file.** A reworded message or a fixed cause leaves a stale rule with nothing to flag it.
- **A fixed merge order or a canary class table.** Both need editing whenever a fork joins.
- **A fleet registry in osdu-spi.** The stack's `forks:` list already exists, and every lane depends on it.
- **Stagger the sync cron per fork.** The workflow file is identical in every fork.
- **Stack lane admission now.** Doing it safely needs leases, fencing and fairness, and five lanes at once already ran clean.

---
