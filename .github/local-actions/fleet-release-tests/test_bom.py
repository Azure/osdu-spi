#!/usr/bin/env python3
# Copyright © Microsoft Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Behavior tests for the fleet bill of materials. Local git repositories, no network."""

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "bom", os.path.join(HERE, "..", "..", "scripts", "fleet-release", "bom.py"))
bom = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bom)

GIT_ENV = {
    **os.environ,
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
    "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
}


class Repo:
    def __init__(self, path):
        self.path = path
        os.makedirs(path, exist_ok=True)
        self.git("init", "-q", "-b", "main")

    def git(self, *args):
        return subprocess.run(["git", "-C", self.path, *args], env=GIT_ENV, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, message, files=None):
        for name, text in (files or {"f.txt": message}).items():
            full = os.path.join(self.path, name)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as fh:
                fh.write(text)
            self.git("add", name)
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def generated(self, branch, upstream_sha):
        self.git("checkout", "-q", branch)
        sha = self.commit(f"chore: generate filtered upstream tree\n\nUpstream-Sha: {upstream_sha}",
                          {f"up-{upstream_sha[:8]}.txt": upstream_sha})
        self.git("checkout", "-q", "main")
        return sha

    def merge(self, branch, message):
        self.git("merge", "-q", "--no-ff", branch, "-m", message)
        return self.git("rev-parse", "HEAD")


FLEET = """\
environment: shared
# the fleet
forks:
  - service: partition
    repo: Azure/osdu-spi-partition
    canonicalSource: fork
  - service: "search"
    repo: 'Azure/osdu-spi-search'   # quoted
    canonicalSource: fork
    tier: core
resources:
  postgres:
    walStorage: 8Gi
"""


class FleetListTest(unittest.TestCase):
    def test_reads_every_entry_and_stops_at_the_next_key(self):
        forks = bom.parse_forks(FLEET)
        self.assertEqual([f["service"] for f in forks], ["partition", "search"])
        self.assertEqual(forks[1]["repo"], "Azure/osdu-spi-search")
        self.assertEqual(forks[1]["tier"], "core")

    def test_a_fork_added_to_the_list_needs_no_code_change(self):
        extra = "".join(f"  - service: s{i}\n    repo: Azure/osdu-spi-s{i}\n" for i in range(14))
        self.assertEqual(len(bom.parse_forks("forks:\n" + extra)), 14)

    def test_an_entry_without_a_repo_fails(self):
        with self.assertRaises(bom.BomError):
            bom.parse_forks("forks:\n  - service: partition\n")


class TemplateTargetTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(self.tmp.name)
        self.synced = self.repo.commit("feat: workflow", {".github/template-workflows/validate.yml": "a"})
        self.docs = self.repo.commit("docs: page", {"doc/page.md": "b"})

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_docs_only_head_resolves_to_the_last_synced_change(self):
        target = bom.effective_target(self.repo.path, self.docs, [".github/template-workflows/validate.yml"])
        self.assertEqual(target, self.synced)

    def test_synced_paths_cover_directories_files_and_fork_workflows_only(self):
        with open(os.path.join(HERE, "..", "..", "sync-config.json")) as fh:
            paths = bom.synced_paths(json.load(fh))
        self.assertIn(".github/actions", paths)
        self.assertIn(".release-please-config.json", paths)
        self.assertIn(".github/template-workflows/release.yml", paths)
        self.assertNotIn(".github/workflows/fleet-release.yml", paths)
        self.assertNotIn(".github/.template-sync-commit", paths)


class UpstreamShaTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(self.tmp.name)
        self.repo.commit("chore: init")
        self.repo.git("branch", "fork_upstream")

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_nearest_sync_wins_over_older_trailers(self):
        self.repo.generated("fork_upstream", "a" * 40)
        self.repo.merge("fork_upstream", "Merge sync 1")
        self.repo.generated("fork_upstream", "b" * 40)
        self.repo.merge("fork_upstream", "Merge sync 2")
        release = self.repo.commit("chore: release 1.0.1")
        self.assertEqual(bom.nearest_upstream_sha(self.repo.path, release), "b" * 40)

    def test_syncs_accumulated_into_one_merge_resolve_to_the_newest(self):
        self.repo.generated("fork_upstream", "a" * 40)
        self.repo.generated("fork_upstream", "b" * 40)
        merged = self.repo.merge("fork_upstream", "Merge two syncs")
        self.assertEqual(bom.nearest_upstream_sha(self.repo.path, merged), "b" * 40)

    def test_unrelated_generated_commits_with_different_values_fail(self):
        self.repo.git("branch", "other")
        self.repo.generated("fork_upstream", "a" * 40)
        self.repo.generated("other", "c" * 40)
        self.repo.git("checkout", "-q", "fork_upstream")
        self.repo.git("merge", "-q", "--no-ff", "other", "-m", "join")
        self.repo.git("checkout", "-q", "main")
        merged = self.repo.merge("fork_upstream", "Merge both")
        with self.assertRaises(bom.BomError) as caught:
            bom.nearest_upstream_sha(self.repo.path, merged)
        self.assertIn("ambiguous", str(caught.exception))

    def test_history_without_trailers_gives_none(self):
        self.assertIsNone(bom.nearest_upstream_sha(self.repo.path, self.repo.git("rev-parse", "HEAD")))


ROOT_POM = """<project xmlns="http://maven.apache.org/POM/4.0.0"><properties>
<java.version>25</java.version><maven.compiler.release>${java.version}</maven.compiler.release>
<spring-boot.version>3.5.16</spring-boot.version><os-core-common.version>9.2.0</os-core-common.version>
</properties></project>"""
PROVIDER_POM = """<project><properties>
<core-lib-azure.version>4.0.0</core-lib-azure.version><os-core-common.version>1.0.0</os-core-common.version>
</properties></project>"""


class ToolchainTest(unittest.TestCase):
    def test_pins_come_from_the_build_files_and_the_root_pom_wins(self):
        pins = bom.toolchain([ROOT_POM, PROVIDER_POM], "service:\n  name: x\n  archetype: java-maven-azure\n")
        self.assertEqual(pins, {"archetype": "java-maven-azure", "java": "25", "spring-boot": "3.5.16",
                                "os-core-common": "9.2.0", "core-lib-azure": "4.0.0"})

    def test_a_fork_without_a_pom_records_only_its_archetype(self):
        self.assertEqual(bom.toolchain([], "service:\n  archetype: python-pytest\n"), {"archetype": "python-pytest"})


class FakeSource:
    def __init__(self, clones, releases, digests):
        self.clones, self.releases, self.digests = clones, releases, digests

    def latest_release(self, repo):
        return self.releases.get(repo)

    def clone(self, repo):
        return self.clones[repo]

    def upstream_repository(self, repo):
        return "https://example.com/upstream.git"

    def digest(self, image, tag):
        return self.digests.get(f"{image}:{tag}")


class ReadinessTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.template = Repo(os.path.join(self.tmp.name, "template"))
        self.old = self.template.commit("feat: old", {"build/Dockerfile": "1"})
        self.target = self.template.commit("feat: new", {"build/Dockerfile": "2"})
        self.fork = Repo(os.path.join(self.tmp.name, "fork"))
        self.repo = "Azure/osdu-spi-demo"
        self.fork_def = {"service": "demo", "repo": self.repo, "canonicalSource": "fork"}

    def tearDown(self):
        self.tmp.cleanup()

    def release_on(self, template_commit, tag="v1.0.0"):
        self.fork.commit("chore: sync", {bom.MARKER: template_commit + "\n", "pom.xml": ROOT_POM})
        self.fork.git("tag", tag)

    def entry(self, releases=None, digests=None):
        source = FakeSource({self.repo: self.fork.path},
                            {self.repo: "v1.0.0"} if releases is None else releases,
                            {"azure/osdu-spi-demo:1.0.0": "sha256:aa",
                             "azure/osdu-spi-demo-acceptance:1.0.0": "sha256:bb"} if digests is None else digests)
        return bom.fork_entry(self.fork_def, source, self.template.path, self.target)

    def test_a_release_on_the_target_records_its_digests_and_commit(self):
        self.release_on(self.target)
        entry = self.entry()
        self.assertIsNone(entry["excluded"])
        self.assertEqual(entry["version"], "1.0.0")
        self.assertEqual(entry["commit"], self.fork.git("rev-parse", "v1.0.0"))
        self.assertEqual([i["digest"] for i in entry["images"]], ["sha256:aa", "sha256:bb"])
        self.assertEqual(entry["toolchain"]["java"], "25")

    def test_a_release_before_the_target_is_excluded_with_a_reason(self):
        self.release_on(self.old)
        entry = self.entry()
        self.assertIn("before the target", entry["excluded"]["reason"])
        self.assertIsNone(entry["version"])
        self.assertEqual(entry["images"], [])

    def test_a_fork_without_a_release_is_excluded(self):
        self.assertEqual(self.entry(releases={})["excluded"], {"reason": "no release"})

    def test_a_release_without_its_service_image_is_excluded(self):
        self.release_on(self.target)
        entry = self.entry(digests={"azure/osdu-spi-demo-acceptance:1.0.0": "sha256:bb"})
        self.assertIn("no service image", entry["excluded"]["reason"])

    def test_a_version_tag_moved_off_the_release_commit_is_excluded(self):
        self.release_on(self.target)
        commit = self.fork.git("rev-parse", "v1.0.0")[:12]
        entry = self.entry(digests={"azure/osdu-spi-demo:1.0.0": "sha256:aa",
                                    f"azure/osdu-spi-demo:sha-{commit}": "sha256:cc"})
        self.assertIn("is not the image built from", entry["excluded"]["reason"])

    def test_a_release_on_a_template_commit_osdu_spi_lacks_is_excluded(self):
        self.release_on("f" * 40)
        self.assertIn("does not have", self.entry()["excluded"]["reason"])


class PublishTest(unittest.TestCase):
    BOM = {"schema": 1, "fleet": {"tag": "fleet-2026.11.04", "templateTarget": "a" * 40}, "forks": []}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "bom.json")
        with open(self.path, "w") as fh:
            json.dump(self.BOM, fh)
        self.args = argparse.Namespace(bom=self.path, repo="Azure/osdu-spi")

    def tearDown(self):
        self.tmp.cleanup()

    def published(self, content):
        def fake_run(*cmd, cwd=None, check=True):
            if cmd[:3] == ("gh", "release", "download"):
                with open(os.path.join(cmd[cmd.index("-D") + 1], "bom.json"), "w") as fh:
                    json.dump(content, fh)
            return subprocess.CompletedProcess(cmd, 0, "", "")
        return fake_run

    def test_a_retry_with_the_same_bom_changes_nothing(self):
        with mock.patch.object(bom, "find_release", return_value={"draft": False, "id": 1}), \
                mock.patch.object(bom, "run", side_effect=self.published(self.BOM)) as run:
            bom.publish(self.args)
        self.assertFalse(any(c.args[:3] == ("gh", "release", "create") for c in run.call_args_list))

    def test_a_retry_with_a_different_bom_is_refused(self):
        changed = {**self.BOM, "forks": [{"service": "x"}]}
        with mock.patch.object(bom, "find_release", return_value={"draft": False, "id": 1}), \
                mock.patch.object(bom, "run", side_effect=self.published(changed)):
            with self.assertRaises(bom.BomError):
                bom.publish(self.args)

    def test_a_draft_left_by_a_failed_run_is_refused(self):
        with mock.patch.object(bom, "find_release", return_value={"draft": True, "id": 1}):
            with self.assertRaises(bom.BomError):
                bom.publish(self.args)

    def test_a_new_release_is_created_on_the_target_and_not_marked_latest(self):
        missing = subprocess.CompletedProcess([], 1, "", "Not Found")
        with mock.patch.object(bom, "find_release", return_value=None), \
                mock.patch.object(bom, "gh_api", return_value=missing), \
                mock.patch.object(bom, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            bom.publish(self.args)
        create = run.call_args.args
        self.assertEqual(create[:4], ("gh", "release", "create", "fleet-2026.11.04"))
        self.assertIn("--latest=false", create)
        self.assertEqual(create[create.index("--target") + 1], "a" * 40)


if __name__ == "__main__":
    sys.exit(unittest.main())
