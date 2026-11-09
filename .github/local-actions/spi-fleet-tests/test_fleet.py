"""Behavior tests for the spi-fleet script and the rollout config. No network."""
import contextlib
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / ".github" / "skills" / "spi-fleet"))
import fleet  # noqa: E402

SERVICES = ["partition", "entitlements", "legal", "schema", "file", "storage", "indexer", "search",
            "workflow", "indexer-queue", "unit", "crs-catalog", "crs-conversion"]
FLEET = [{"service": s, "repo": f"Azure/osdu-spi-{s}"} for s in SERVICES]
CONFIG = fleet.load_config(ROOT / ".github" / "fleet" / "rollout.json", FLEET)


def fleet_yaml(n):
    entries = "".join(
        f"  - service: svc{i}\n    repo: Azure/osdu-spi-svc{i}  # note\n    canonicalSource: fork\n" for i in range(n)
    )
    return f"cluster: shared\nforks:\n{entries}resources:\n  postgres:\n    walStorage: 8Gi\n"


class FleetList(unittest.TestCase):
    def test_reads_every_entry_of_a_growing_list(self):
        forks = fleet.parse_forks(fleet_yaml(14))
        self.assertEqual(len(forks), 14)
        self.assertEqual(forks[13], {"service": "svc13", "repo": "Azure/osdu-spi-svc13", "canonicalSource": "fork"})

    def test_ignores_keys_outside_the_forks_block(self):
        forks = fleet.parse_forks("other:\n  - service: x\n    repo: y\n" + fleet_yaml(1))
        self.assertEqual([f["service"] for f in forks], ["svc0"])

    def test_reads_the_stack_declaration_shape(self):
        forks = fleet.parse_forks("forks:\n  - service: 'search'\n    repo: \"Azure/osdu-spi-search\"\n")
        self.assertEqual(forks, [{"service": "search", "repo": "Azure/osdu-spi-search"}])


class RolloutConfig(unittest.TestCase):
    def load(self, config, forks=FLEET):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "rollout.json"
            path.write_text(json.dumps(config))
            return fleet.load_config(path, forks)

    def test_lanes_is_a_positive_integer(self):
        self.assertGreater(CONFIG["lanes"], 0)
        with self.assertRaises(SystemExit):
            self.load({"schema": 1, "lanes": 0})

    def test_rejects_an_unknown_schema(self):
        with self.assertRaises(SystemExit):
            self.load({"schema": 2, "lanes": 5})

    def test_an_ordering_entry_for_a_fork_that_left_the_fleet_fails_loudly(self):
        forks = [f for f in FLEET if f["service"] != "indexer"]
        with self.assertRaises(SystemExit) as raised:
            self.load(json.loads((ROOT / ".github" / "fleet" / "rollout.json").read_text()), forks)
        self.assertIn("indexer", str(raised.exception))


class EnvironmentTitles(unittest.TestCase):
    def test_validate_titles_every_environment_timeout(self):
        text = (ROOT / ".github" / "template-workflows" / "validate.yml").read_text()
        titled = re.findall(r"::error title=Environment::([a-z ]+after \d+ minutes)", text)
        self.assertEqual(sorted(titled), sorted([
            "environment is not deployable after 10 minutes",
            "pin still refused after 10 minutes",
            "digest not live after 15 minutes",
        ]))


class Grouping(unittest.TestCase):
    services = ["partition", "storage", "indexer", "search", "unit", "file", "legal"]

    def test_groups_hold_at_most_n_and_search_follows_its_predecessors(self):
        groups, held = fleet.ordered_groups(self.services, CONFIG, set(), 2)
        self.assertTrue(all(len(g) <= 2 for g in groups))
        self.assertEqual(sorted(s for g in groups for s in g), sorted(self.services))
        where = {s: i for i, g in enumerate(groups) for s in g}
        self.assertGreater(where["search"], max(where["storage"], where["indexer"]))
        self.assertEqual(held, [])

    def test_search_is_held_while_storage_is_not_ready(self):
        groups, held = fleet.ordered_groups(["search", "unit"], CONFIG, {"storage"}, 5)
        self.assertEqual((groups, held), ([["unit"]], ["search"]))

    def test_a_new_fork_needs_no_ordering_entry(self):
        groups, _ = fleet.ordered_groups(["svc14", "partition"], CONFIG, set(), 5)
        self.assertEqual(groups, [["svc14", "partition"]])


def run(conclusion, attempt=1, status="completed"):
    return {"id": 7, "run_attempt": attempt, "html_url": "u", "status": status, "conclusion": conclusion, "head_sha": "abc"}


class RunVerdicts(unittest.TestCase):
    def judge(self, r, annotations=()):
        jobs = {"jobs": [{"id": 1, "name": "Deploy and Test", "conclusion": "failure", "check_run_url": "x/9"}]}
        anns = [{"annotation_level": level, "title": title, "message": m} for level, title, m in annotations]
        with mock.patch.object(fleet, "gh_json", side_effect=lambda *a: jobs if a[1].endswith("per_page=100") else anns):
            return fleet.judge_run("Azure/x", r)

    def test_pending_and_green(self):
        self.assertEqual(self.judge(run(None, status="in_progress"))["verdict"], "pending")
        self.assertEqual(self.judge(run("success"))["verdict"], "green")

    def test_an_environment_title_is_an_environment_failure(self):
        verdict = self.judge(run("failure"), [("failure", "Environment", "digest not live after 15 minutes")])
        self.assertEqual((verdict["verdict"], verdict["cause"]), ("environment", "digest not live after 15 minutes"))

    def test_untitled_and_notice_annotations_are_real(self):
        verdict = self.judge(run("failure"), [
            ("failure", "", "pin refused while the environment is deployable"),
            ("notice", "Environment", "digest not live after 15 minutes"),
        ])
        self.assertEqual((verdict["verdict"], verdict["response"]), ("real", "stop"))

    def test_an_environment_failure_after_a_rerun_is_real(self):
        verdict = self.judge(run("failure", attempt=2), [("failure", "Environment", "digest not live after 15 minutes")])
        self.assertEqual((verdict["verdict"], verdict["note"]), ("real", "already rerun once"))

    def test_exit_codes_rank_real_over_environment_over_pending(self):
        rows = [{"verdict": "pending"}, {"verdict": "environment"}]
        self.assertEqual(fleet.exit_code(rows), fleet.EXIT_ENVIRONMENT)
        self.assertEqual(fleet.exit_code(rows + [{"verdict": "real"}]), fleet.EXIT_REAL)
        self.assertEqual(fleet.exit_code([{"verdict": "green"}, {"verdict": "no-pr"}]), fleet.EXIT_OK)


class SyncPrVerdicts(unittest.TestCase):
    def row(self, rollup, run_lookup=None):
        pr = {"number": 7, "url": "u", "headRefName": "sync/upstream-1", "headRefOid": "abc",
              "mergeStateStatus": "CLEAN", "reviewDecision": "APPROVED", "statusCheckRollup": rollup}
        lookup = mock.Mock(return_value=run_lookup)
        with mock.patch.object(fleet, "find_pr", return_value=pr), mock.patch.object(fleet, "latest_run", lookup):
            return fleet.pr_row({"service": "partition", "repo": "Azure/x"}, "sync/"), lookup

    def status(self, state):
        return {"__typename": "StatusContext", "context": "Sync Build", "state": state, "targetUrl": "https://run"}

    def test_a_filter_mode_sync_pr_is_judged_by_its_sync_build_status(self):
        for state, verdict in (("PENDING", "pending"), ("SUCCESS", "green"), ("FAILURE", "real"), ("ERROR", "real")):
            row, lookup = self.row([self.status(state)])
            self.assertEqual(row["verdict"], verdict, state)
            lookup.assert_not_called()

    def test_a_failed_sync_build_stops_and_is_not_listed_as_another_failure(self):
        row, _ = self.row([self.status("FAILURE")])
        self.assertEqual((row["response"], row["otherFailures"]), ("stop", []))
        self.assertEqual(fleet.exit_code([row]), fleet.EXIT_REAL)

    def test_without_a_sync_build_status_the_validation_run_decides(self):
        row, lookup = self.row([], run_lookup=run("success"))
        self.assertEqual(row["verdict"], "green")
        lookup.assert_called_once()


class MergePlan(unittest.TestCase):
    def rows(self):
        def row(service, verdict="green", merge_state="CLEAN", review="APPROVED"):
            return {"service": service, "repo": f"Azure/osdu-spi-{service}", "pr": 1, "head": "h",
                    "verdict": verdict, "mergeState": merge_state, "review": review, "otherFailures": []}
        return {
            "storage": row("storage", verdict="pending"),
            "search": row("search"),
            "unit": row("unit"),
            "file": row("file", review="REVIEW_REQUIRED", merge_state="BLOCKED"),
            "legal": row("legal"),
        }

    def test_plan_without_go_merges_nothing(self):
        rows = self.rows()
        forks = [{"service": s, "repo": r["repo"]} for s, r in rows.items()]
        args = mock.Mock(prefix="template-sync/", lanes=1, go=False, log="unused.jsonl", interval=0, timeout=0, grace=0)
        out = io.StringIO()
        with mock.patch.object(fleet, "pr_row", side_effect=lambda f, p: rows[f["service"]]), \
             mock.patch.object(fleet, "gh") as gh, mock.patch.object(fleet, "merge_one") as merge_one, \
             contextlib.redirect_stdout(out):
            code = fleet.cmd_merge(args, forks, CONFIG, forks)
        self.assertEqual(code, fleet.EXIT_OK)
        gh.assert_not_called()
        merge_one.assert_not_called()
        text = out.getvalue()
        self.assertIn("group 1   unit", text)
        self.assertIn("group 2   legal", text)
        self.assertIn("held      search: green, but ordered after", text)
        self.assertIn("held      file: green (needs approval)", text)


class MergeRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = Path(self.tmp.name) / "merge.jsonl"
        self.merged = []

    def tearDown(self):
        self.tmp.cleanup()

    def go(self, services, lanes, busy=0, skip=(), main_verdict="green"):
        rows = {s: {"service": s, "repo": f"Azure/osdu-spi-{s}", "pr": 1, "head": "h", "verdict": "green",
                    "mergeState": "CLEAN", "review": "APPROVED", "otherFailures": []} for s in services}
        forks = [{"service": s, "repo": r["repo"]} for s, r in rows.items()]
        args = mock.Mock(prefix="template-sync/", lanes=lanes, go=True, log=str(self.log),
                         interval=0, timeout=0, grace=0)
        waves = []

        def merge_one(row):
            if row["service"] in skip:
                return {**row, "verdict": "skipped", "note": "head moved since it was checked"}
            self.merged.append(row["service"])
            return {**row, "mergeSha": "m" * 40, "verdict": "no-run"}

        def wait(merged, *_):
            waves.append([m["service"] for m in merged])
            return [{**m, "verdict": main_verdict, "response": "stop"} for m in merged]

        with mock.patch.object(fleet, "pr_row", side_effect=lambda f, p: rows[f["service"]]), \
             mock.patch.object(fleet, "active_lanes", return_value=busy), \
             mock.patch.object(fleet, "image_name", side_effect=lambda r: r.lower()), \
             mock.patch.object(fleet, "ghcr_digest", return_value="sha256:old"), \
             mock.patch.object(fleet, "merge_one", side_effect=merge_one), \
             mock.patch.object(fleet, "wait_for_main", side_effect=wait), \
             contextlib.redirect_stdout(io.StringIO()):
            code = fleet.cmd_merge(args, forks, CONFIG, forks)
        return code, waves

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_lanes_already_in_use_shrink_the_group(self):
        code, waves = self.go(["unit", "legal", "file"], lanes=3, busy=1)
        self.assertEqual(code, fleet.EXIT_OK)
        self.assertEqual(waves, [["unit", "legal"], ["file"]])

    def test_no_free_lane_merges_nothing(self):
        code, waves = self.go(["unit"], lanes=2, busy=2)
        self.assertEqual((code, waves, self.merged), (fleet.EXIT_PENDING, [], []))

    def test_a_skipped_merge_stops_before_the_next_group(self):
        code, waves = self.go(["unit", "legal", "file"], lanes=2, skip={"legal"})
        self.assertEqual(code, fleet.EXIT_PENDING)
        self.assertEqual(waves, [["unit"]])
        self.assertNotIn("file", self.merged)

    def test_a_group_where_every_merge_skipped_still_stops(self):
        code, waves = self.go(["unit", "legal"], lanes=1, skip={"unit"})
        self.assertEqual((code, self.merged), (fleet.EXIT_PENDING, []))

    def test_each_merge_is_logged_before_its_main_run_is_judged(self):
        self.go(["unit"], lanes=1, main_verdict="real")
        kinds = [(e["event"], e["service"]) for e in self.events()]
        self.assertEqual(kinds, [("merged", "unit"), ("validated", "unit")])
        self.assertEqual(self.events()[0]["previousMainDigest"], "sha256:old")
        self.assertEqual(self.events()[1]["result"], "real")


class MainRuns(unittest.TestCase):
    def test_a_merge_with_no_push_run_after_the_grace_period_is_unvalidated(self):
        clock = iter([0, 700, 700, 700])
        with mock.patch.object(fleet, "latest_run", return_value=None), \
             mock.patch.object(fleet.time, "time", side_effect=lambda: next(clock)), \
             mock.patch.object(fleet.time, "sleep"), contextlib.redirect_stderr(io.StringIO()):
            out = fleet.wait_for_main([{"service": "unit", "repo": "Azure/x", "mergeSha": "m"}], 0, 7200, 600)
        self.assertEqual(out[0]["verdict"], "unvalidated")
        self.assertEqual(fleet.exit_code(out), fleet.EXIT_OK)

    def test_a_late_push_run_inside_the_grace_period_is_waited_for(self):
        runs = iter([None, run("success")])
        with mock.patch.object(fleet, "latest_run", side_effect=lambda *a: next(runs)), \
             mock.patch.object(fleet.time, "sleep"), contextlib.redirect_stderr(io.StringIO()):
            out = fleet.wait_for_main([{"service": "unit", "repo": "Azure/x", "mergeSha": "m"}], 0, 7200, 600)
        self.assertEqual(out[0]["verdict"], "green")


class Watch(unittest.TestCase):
    def test_wait_keeps_polling_while_a_pr_has_no_run_yet(self):
        rows = iter([{"service": "unit", "pr": 1, "verdict": "no-run"}, {"service": "unit", "pr": 1, "verdict": "green"}])
        args = mock.Mock(main=False, wait=True, prefix="template-sync/", interval=0, json=False)
        with mock.patch.object(fleet, "pr_row", side_effect=lambda f, p: next(rows)), \
             mock.patch.object(fleet.time, "sleep") as sleep, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = fleet.cmd_watch(args, [{"service": "unit", "repo": "Azure/x"}], CONFIG)
        self.assertEqual((code, sleep.call_count), (fleet.EXIT_OK, 1))


class Arguments(unittest.TestCase):
    def test_lanes_must_be_positive(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            fleet.main(["merge", "--lanes", "0"])

    def test_printing_no_rows_prints_nothing(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            fleet.print_rows([], False)
        self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
