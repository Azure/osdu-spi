#!/usr/bin/env python3
"""Watch and merge one fleet-wide pull request across the SPI forks, a few lanes at a time.

The fleet is the `forks:` list in osdu-spi-stack's ops/environments/shared.yaml. The number of
lanes and the merge-ordering exceptions come from .github/fleet/rollout.json. A failure is an
environment failure when Validation raised it with the annotation title "Environment"; anything
else is a failure of the change. Needs only `gh` and Python 3.9+.

Exit codes: 0 green or nothing to do, 1 a real failure, 2 still pending, 3 an environment
failure that waits for the person's go to rerun once.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = HERE.parent.parent / "fleet" / "rollout.json"
STACK_REPO = "Azure/osdu-spi-stack"
FLEET_PATH = "ops/environments/shared.yaml"
WORKFLOW = "Validation"
ENVIRONMENT_TITLE = "Environment"
MERGEABLE = {"CLEAN", "UNSTABLE", "HAS_HOOKS"}
EXIT_OK, EXIT_REAL, EXIT_PENDING, EXIT_ENVIRONMENT = 0, 1, 2, 3


class GhError(RuntimeError):
    pass


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode:
        raise GhError(f"gh {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def gh_json(*args: str):
    out = gh(*args)
    return json.loads(out) if out.strip() else None


# Fleet and rollout config ----------------------------------------------------------------------


def parse_forks(text: str) -> list[dict]:
    """Reads the top-level `forks:` block: a list of flat `key: value` maps."""
    forks: list[dict] = []
    inside = False
    current: dict | None = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        line = re.sub(r"\s+#.*$", "", raw.rstrip())
        if not raw[0].isspace() and not raw.startswith("-"):
            inside = line.strip() == "forks:"
            current = None
            continue
        if not inside:
            continue
        item = line.strip()
        if item.startswith("- "):
            current = {}
            forks.append(current)
            item = item[2:].strip()
        if current is not None and ":" in item:
            key, value = item.split(":", 1)
            current[key.strip()] = value.strip().strip("'\"")
    return [f for f in forks if f.get("service") and f.get("repo")]


def load_fleet(fleet_file: str | None) -> list[dict]:
    if fleet_file:
        text = Path(fleet_file).read_text()
    else:
        content = gh_json("api", f"repos/{STACK_REPO}/contents/{FLEET_PATH}")["content"]
        text = base64.b64decode(content).decode()
    forks = parse_forks(text)
    if not forks:
        raise SystemExit(f"no forks found in {fleet_file or STACK_REPO + ':' + FLEET_PATH}")
    return forks


def load_config(path: Path, fleet: list[dict]) -> dict:
    config = json.loads(path.read_text())
    if config.get("schema") != 1:
        raise SystemExit(f"{path}: unsupported schema {config.get('schema')!r}")
    if not isinstance(config.get("lanes"), int) or config["lanes"] < 1:
        raise SystemExit(f"{path}: lanes must be a positive integer")
    known = {f["service"] for f in fleet}
    named = {o["service"] for o in config.get("ordering", [])} | {a for o in config.get("ordering", []) for a in o.get("after", [])}
    if named - known:
        raise SystemExit(f"{path}: ordering names services not in the fleet list: {', '.join(sorted(named - known))}")
    return config


def ordered_groups(services: list[str], config: dict, waiting: set[str], lanes: int) -> tuple[list[list[str]], list[str]]:
    """Splits services into groups of at most `lanes`, in fleet order, placing each ordering
    exception after the services it names. A service whose predecessor is still waiting (its PR
    is open but not mergeable) is held, along with anything ordered after it."""
    after = {o["service"]: set(o.get("after", [])) for o in config.get("ordering", [])}
    held: set[str] = set()
    changed = True
    while changed:
        changed = False
        for s in services:
            if s not in held and after.get(s, set()) & (waiting | held):
                held.add(s)
                changed = True
    remaining = [s for s in services if s not in held]
    groups: list[list[str]] = []
    while remaining:
        ready = [s for s in remaining if not after.get(s, set()) & set(remaining)] or remaining[:]
        group = ready[:lanes]
        groups.append(group)
        remaining = [s for s in remaining if s not in group]
    return groups, [s for s in services if s in held]


# Reading state ------------------------------------------------------------------------------


def find_pr(repo: str, prefix: str) -> dict | None:
    prs = gh_json(
        "pr", "list", "-R", repo, "--state", "open", "--limit", "50", "--json",
        "number,url,headRefName,headRefOid,author,mergeStateStatus,reviewDecision,statusCheckRollup",
    ) or []
    matches = [p for p in prs if p["headRefName"].startswith(prefix)]
    return max(matches, key=lambda p: p["number"]) if matches else None


def latest_run(repo: str, query: str) -> dict | None:
    runs = gh_json("api", f"repos/{repo}/actions/runs?{query}&per_page=50")["workflow_runs"]
    runs = [r for r in runs if r["name"] == WORKFLOW]
    return max(runs, key=lambda r: r["id"]) if runs else None


def environment_failures(repo: str, run_id: int) -> tuple[list[str], list[str]]:
    """Names of the failed jobs, and the messages of failure annotations titled Environment."""
    jobs = gh_json("api", f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    failed, messages = [], []
    for job in jobs:
        if job.get("conclusion") not in ("failure", "timed_out"):
            continue
        failed.append(job["name"])
        check_run = job["check_run_url"].rsplit("/", 1)[1]
        for annotation in gh_json("api", f"repos/{repo}/check-runs/{check_run}/annotations") or []:
            if annotation.get("annotation_level") == "failure" and annotation.get("title") == ENVIRONMENT_TITLE:
                messages.append(annotation.get("message", ""))
    return failed, messages


def judge_run(repo: str, run: dict | None) -> dict:
    if run is None:
        return {"verdict": "no-run"}
    out = {"run": run["id"], "attempt": run.get("run_attempt", 1), "runUrl": run["html_url"]}
    if run["status"] != "completed":
        return {**out, "verdict": "pending"}
    if run["conclusion"] in ("success", "skipped", "neutral"):
        return {**out, "verdict": "green"}
    failed, messages = environment_failures(repo, run["id"])
    out.update(failedJobs=failed, cause=messages[0] if messages else "")
    if not messages:
        return {**out, "verdict": "real", "response": "stop"}
    if out["attempt"] > 1:
        return {**out, "verdict": "real", "response": "stop", "note": "already rerun once"}
    return {**out, "verdict": "environment", "response": "rerun failed jobs once, after the other lanes drain"}


def pr_row(fork: dict, prefix: str) -> dict:
    row = {"service": fork["service"], "repo": fork["repo"]}
    pr = find_pr(fork["repo"], prefix)
    if pr is None:
        return {**row, "verdict": "no-pr"}
    event = "pull_request_target" if pr["headRefName"].startswith("sync/") else "pull_request"
    run = latest_run(fork["repo"], f"head_sha={pr['headRefOid']}&event={event}")
    blockers = [
        c.get("name") or c.get("context")
        for c in pr.get("statusCheckRollup") or []
        if (c.get("conclusion") or c.get("state") or "").upper() in ("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED")
        and (c.get("name") or c.get("context")) != WORKFLOW
    ]
    return {**row, "pr": pr["number"], "url": pr["url"], "head": pr["headRefOid"],
            "mergeState": pr["mergeStateStatus"], "review": pr.get("reviewDecision") or "",
            "otherFailures": [b for b in blockers if b], **judge_run(fork["repo"], run)}


def main_row(fork: dict) -> dict:
    run = latest_run(fork["repo"], "branch=main&event=push")
    row = {"service": fork["service"], "repo": fork["repo"], **judge_run(fork["repo"], run)}
    if run:
        row["head"] = run["head_sha"]
    return row


# Output -------------------------------------------------------------------------------------


def describe(row: dict) -> str:
    verdict = row["verdict"]
    if verdict in ("environment", "real"):
        detail = row["response"]
        if row.get("note"):
            detail += f" ({row['note']})"
        if row.get("cause"):
            detail += f"; {row['cause']}"
        return f"{verdict}: {detail}; failed {', '.join(row.get('failedJobs', []))}; {row.get('runUrl', '')}"
    if verdict == "unvalidated":
        return f"unvalidated ({row.get('note', '')})"
    extra = []
    if row.get("review") == "REVIEW_REQUIRED":
        extra.append("needs approval")
    if row.get("mergeState") and row["mergeState"] not in MERGEABLE and row.get("review") != "REVIEW_REQUIRED":
        extra.append(f"merge state {row['mergeState']}")
    if row.get("otherFailures"):
        extra.append("other checks failing: " + ", ".join(row["otherFailures"]))
    return verdict + (f" ({'; '.join(extra)})" if extra else "")


def print_rows(rows: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps(rows, indent=2))
        return
    if not rows:
        return
    width = max(len(r["service"]) for r in rows)
    for r in rows:
        ref = f"#{r['pr']}" if "pr" in r else (r.get("head", "")[:7] or "-")
        print(f"{r['service']:<{width}}  {ref:<8}  {describe(r)}")


def exit_code(rows: list[dict]) -> int:
    verdicts = {r["verdict"] for r in rows}
    if "real" in verdicts:
        return EXIT_REAL
    if "environment" in verdicts:
        return EXIT_ENVIRONMENT
    if "pending" in verdicts:
        return EXIT_PENDING
    return EXIT_OK


# Verbs --------------------------------------------------------------------------------------


def still_open(row: dict) -> bool:
    """A run is pending, or a PR is open whose Validation run has not appeared yet."""
    return row["verdict"] == "pending" or (row["verdict"] == "no-run" and "pr" in row)


def cmd_watch(args, fleet: list[dict], config: dict) -> int:
    while True:
        rows = [main_row(f) if args.main else pr_row(f, args.prefix) for f in fleet]
        waiting = [r["service"] for r in rows if still_open(r)]
        if not args.wait or not waiting:
            print_rows(rows, args.json)
            return exit_code(rows)
        print(f"{datetime.now(timezone.utc):%H:%M:%SZ} pending: {', '.join(waiting)}", file=sys.stderr)
        time.sleep(args.interval)


def active_lanes(forks: list[dict]) -> int:
    """Validation runs queued or in progress across the whole fleet, PR and main alike."""
    count = 0
    for fork in forks:
        for status in ("in_progress", "queued"):
            runs = gh_json("api", f"repos/{fork['repo']}/actions/runs?status={status}&per_page=50")["workflow_runs"]
            count += sum(1 for r in runs if r["name"] == WORKFLOW)
    return count


def image_name(repo: str) -> str:
    """The image Validation pushes: the SERVICE_NAME variable, else the repository name."""
    try:
        name = gh("variable", "get", "SERVICE_NAME", "-R", repo).strip()
    except GhError:
        name = ""
    owner, repo_name = repo.split("/", 1)
    return f"{owner}/{name or repo_name}".lower()


def ghcr_digest(image: str, tag: str) -> str | None:
    try:
        with urllib.request.urlopen(f"https://ghcr.io/token?scope=repository:{image}:pull", timeout=20) as r:
            token = json.load(r)["token"]
        request = urllib.request.Request(
            f"https://ghcr.io/v2/{image}/manifests/{tag}", method="HEAD",
            headers={"Authorization": f"Bearer {token}", "Accept": ", ".join([
                "application/vnd.oci.image.index.v1+json",
                "application/vnd.docker.distribution.manifest.list.v2+json",
                "application/vnd.oci.image.manifest.v1+json",
                "application/vnd.docker.distribution.manifest.v2+json"])})
        with urllib.request.urlopen(request, timeout=20) as r:
            return r.headers.get("Docker-Content-Digest")
    except (urllib.error.URLError, KeyError, ValueError):
        return None


def wait_for_main(merged: list[dict], interval: int, timeout: int, grace: int) -> list[dict]:
    """Waits for each merge SHA's push run. A merge that shows no run within `grace` seconds was
    path-filtered by validate.yml's push trigger, borrowed nothing, and is reported as such."""
    started = time.time()
    while True:
        for m in merged:
            if m.get("verdict") in (None, "no-run", "pending"):
                run = latest_run(m["repo"], f"head_sha={m['mergeSha']}&event=push")
                m.update(judge_run(m["repo"], run))
                if m["verdict"] == "no-run" and time.time() - started > grace:
                    m.update(verdict="unvalidated", note="no push Validation run; the push was path-filtered")
        open_ = [m["service"] for m in merged if m["verdict"] in ("no-run", "pending")]
        if not open_:
            return merged
        if time.time() - started > timeout:
            for m in merged:
                if m["verdict"] in ("no-run", "pending"):
                    m["verdict"] = "pending"
            return merged
        print(f"{datetime.now(timezone.utc):%H:%M:%SZ} main runs pending: {', '.join(open_)}", file=sys.stderr)
        time.sleep(interval)


def merge_one(row: dict) -> dict:
    repo, number = row["repo"], row["pr"]
    state = gh_json("pr", "view", str(number), "-R", repo, "--json", "state,mergeCommit,headRefOid")
    if state["state"] == "OPEN":
        if state["headRefOid"] != row["head"]:
            return {**row, "verdict": "skipped", "note": "head moved since it was checked"}
        gh("pr", "merge", str(number), "-R", repo, "--merge", "--match-head-commit", row["head"])
        state = gh_json("pr", "view", str(number), "-R", repo, "--json", "state,mergeCommit")
    if state["state"] != "MERGED" or not state.get("mergeCommit"):
        return {**row, "verdict": "skipped", "note": f"pull request is {state['state'].lower()}"}
    return {**row, "mergeSha": state["mergeCommit"]["oid"], "verdict": "no-run"}


def append_log(log: Path, record: dict) -> None:
    with log.open("a") as fh:
        fh.write(json.dumps({"at": datetime.now(timezone.utc).isoformat(timespec="seconds"), **record}) + "\n")


def wait_for_capacity(all_forks: list[dict], lanes: int, interval: int, timeout: int) -> int:
    started = time.time()
    while True:
        free = lanes - active_lanes(all_forks)
        if free > 0 or time.time() - started > timeout:
            return free
        print(f"{datetime.now(timezone.utc):%H:%M:%SZ} {lanes - free} lanes busy; waiting", file=sys.stderr)
        time.sleep(interval)


def cmd_merge(args, fleet: list[dict], config: dict, all_forks: list[dict]) -> int:
    lanes = args.lanes or config["lanes"]
    rows = {r["service"]: r for r in (pr_row(f, args.prefix) for f in fleet)}
    eligible = [
        s for s, r in rows.items()
        if r["verdict"] == "green" and r.get("mergeState") in MERGEABLE
        and r.get("review") != "REVIEW_REQUIRED" and not r.get("otherFailures")
    ]
    held = [r for s, r in rows.items() if r["verdict"] != "no-pr" and s not in eligible]
    waiting = {r["service"] for r in held}
    groups, held_for_order = ordered_groups(eligible, config, waiting, lanes)

    for r in held:
        print(f"held      {r['service']}: {describe(r)}")
    for service in held_for_order:
        print(f"held      {service}: green, but ordered after a fork that is not ready")
    for i, group in enumerate(groups, 1):
        print(f"group {i}   {', '.join(group)}")
    if not groups:
        print("nothing is ready to merge")
        return exit_code(held) if held else EXIT_OK
    if not args.go:
        print(f"plan only; rerun with --go to merge {lanes} at a time")
        return EXIT_OK

    log = Path(args.log)
    queue = [list(g) for g in groups]
    while queue:
        group = queue.pop(0)
        free = wait_for_capacity(all_forks, lanes, args.interval, args.timeout)
        if free <= 0:
            print(f"stopped: no free lane within {args.timeout}s; merge log: {log}")
            return EXIT_PENDING
        if free < len(group):
            queue.insert(0, group[free:])
            group = group[:free]
        merged, skipped = [], []
        for service in group:
            row = rows[service]
            image = image_name(row["repo"])
            previous = ghcr_digest(image, "main-snapshot")
            result = merge_one(row)
            if result["verdict"] == "skipped":
                print(f"skipped   {service} #{row['pr']}: {result['note']}")
                skipped.append(result)
                continue
            result["previousMainDigest"] = previous
            append_log(log, {"event": "merged", "service": service, "repo": row["repo"], "pr": row["pr"],
                             "mergeSha": result["mergeSha"], "image": f"ghcr.io/{image}",
                             "previousMainDigest": previous})
            print(f"merged    {service} #{row['pr']} {result['mergeSha'][:12]}")
            merged.append(result)
        merged = wait_for_main(merged, args.interval, args.timeout, args.grace)
        for m in merged:
            append_log(log, {"event": "validated", "service": m["service"], "mergeSha": m["mergeSha"],
                             "run": m.get("run"), "result": m["verdict"], "cause": m.get("cause")})
        if merged:
            print_rows(merged, False)
        code = exit_code(merged)
        if code != EXIT_OK:
            print(f"stopped: a main run did not pass; merge log: {log}")
            return code
        if skipped:
            print(f"stopped: {', '.join(m['service'] for m in skipped)} did not merge; merge log: {log}")
            return EXIT_PENDING
    print(f"all groups merged; merge log: {log}")
    return EXIT_OK


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be 1 or more")
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fleet-file", help="read forks: from this file instead of osdu-spi-stack main")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG), help="rollout config (default: %(default)s)")
    parser.add_argument("--only", help="comma-separated services to act on")
    sub = parser.add_subparsers(dest="verb", required=True)

    watch = sub.add_parser("watch", help="report each fork's PR, or its main run, by Validation verdict")
    watch.add_argument("--prefix", default="template-sync/", help="head branch prefix of the fleet PR")
    watch.add_argument("--main", action="store_true", help="report the latest push run on main instead")
    watch.add_argument("--wait", action="store_true", help="poll until no run is pending or awaited")
    watch.add_argument("--interval", type=positive_int, default=60)
    watch.add_argument("--json", action="store_true")

    merge = sub.add_parser("merge", help="merge green PRs in groups of N, waiting for each group's main runs")
    merge.add_argument("--prefix", default="template-sync/")
    merge.add_argument("--lanes", type=positive_int, help="lanes at once (default: lanes in the rollout config)")
    merge.add_argument("--go", action="store_true", help="merge; without it, print the plan only")
    merge.add_argument("--interval", type=positive_int, default=60)
    merge.add_argument("--timeout", type=positive_int, default=7200, help="seconds to wait for lanes or main runs")
    merge.add_argument("--grace", type=positive_int, default=600,
                       help="seconds a merge may show no push run before it counts as path-filtered")
    merge.add_argument("--log", default=f"fleet-merge-{datetime.now(timezone.utc):%Y%m%d}.jsonl")

    args = parser.parse_args(argv)
    all_forks = load_fleet(args.fleet_file)
    config = load_config(Path(args.config), all_forks)
    fleet = all_forks
    if args.only:
        wanted = {s.strip() for s in args.only.split(",")}
        unknown = wanted - {f["service"] for f in all_forks}
        if unknown:
            raise SystemExit(f"not in the fleet list: {', '.join(sorted(unknown))}")
        fleet = [f for f in all_forks if f["service"] in wanted]
    if args.verb == "watch":
        return cmd_watch(args, fleet, config)
    return cmd_merge(args, fleet, config, all_forks)


if __name__ == "__main__":
    sys.exit(main())
