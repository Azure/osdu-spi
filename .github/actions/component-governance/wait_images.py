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

"""Wait until Validation has published the images the scan registers.

The Component Governance step only warns when it cannot pull an image and then
registers a snapshot without it. This gate fails the job first, so a missing
image never replaces a complete snapshot.

With images "auto" the gate looks for a successful push-event Docker Push run
of the built commit, through the GitHub API with the checkout's GitHub App
token. A push whose files Validation's push filter ignores publishes no image;
once that push has settled the gate steps to the first parent and scans that
commit's images, which the ignored files cannot change. Explicit images are
scanned unverified.

The checkout's GitHub credential is removed on every exit, so the scan never
sees it.

Environment: OUT (holds cg-inputs.json), BUILD_REPOSITORY_NAME,
CG_IMAGE_WAIT_SECONDS (1800), CG_IMAGE_GRACE_SECONDS (600), CG_POLL_SECONDS
(30), GITHUB_API_URL, CG_GITHUB_TOKEN (default: the checkout's credential).
"""

import datetime
import json
import os
import re
import sys
import time
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)

from cg_common import POLL_SECONDS, checkout_token, drop_credentials, fail, git, github, warn, write_json  # noqa: E402

CHECK = "Docker Push"  # the validate.yml job that pushes every :sha-<commit> image
# validate.yml on.push.paths-ignore; the component governance harness keeps the two equal.
VALIDATION_IGNORED = (
    ".github/workflows/**",
    ".github/template-workflows/**",
    ".github/ISSUE_TEMPLATE/**",
    ".github/actions/**",
    ".github/*.md",
    ".github/*.json",
    ".github/*.yml",
    ".github/*.yaml",
    ".github/.template-sync-commit",
    ".vscode/**",
    "docs/**",
    "**.md",
    "**.txt",
    "LICENSE",
)
MAX_SKIPPED = 50


def glob_re(pattern):
    """GitHub path filter syntax: ** matches across directories, * within one."""
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**", i):
            out, i = out + ".*", i + 2
        elif pattern[i] == "*":
            out, i = out + "[^/]*", i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(out)


IGNORED_RES = [glob_re(p) for p in VALIDATION_IGNORED]


def ignored_only(commit):
    """True when the commit changes only files a push of it would not validate, compared with its first parent."""
    parents = git("log", "-1", "--format=%P", commit).split()
    if not parents:
        return False
    files = [f for f in git("diff", "--name-only", "--no-renames", "-z", parents[0], commit, "--").split("\0") if f]
    return bool(files) and all(any(r.fullmatch(f) for r in IGNORED_RES) for f in files)


def publishing_runs(token, repo, sha):
    """Docker Push check runs that published :sha-<commit>.

    A pull_request run attaches its checks to the PR head but checks out and publishes the merge commit, so only
    runs of the push event count: they check out exactly the commit. The Actions API names the event. Without
    access to it (the Azure Pipelines GitHub App has no Actions permission), count check suites of main: only a
    push to main, a dispatch on main, or a pull request whose head is this repository's main produce them, and
    the last is refused because it would publish a merge commit.
    """
    runs = [c for c in github(token, f"repos/{repo}/commits/{sha}/check-runs",
                              query={"check_name": CHECK, "filter": "all", "per_page": 100})["check_runs"]
            if (c.get("app") or {}).get("slug") == "github-actions"]
    try:
        push = github(token, f"repos/{repo}/actions/runs", query={"head_sha": sha, "event": "push", "per_page": 100})
        suites = {r["check_suite_id"] for r in push["workflow_runs"]}
        return [c for c in runs if c["check_suite"]["id"] in suites], "push-event workflow runs"
    except urllib.error.HTTPError as e:
        if e.code not in (403, 404):
            raise
    owner = repo.split("/")[0]
    if github(token, f"repos/{repo}/pulls", query={"head": f"{owner}:main", "state": "all", "per_page": 1}):
        fail("This repository has pull requests from main, so a Docker Push check of main can come from a pull request "
             "run that published a merge commit; without Actions read access the event cannot be told apart. Queue "
             "the run with explicit images.")
    heads = {c["check_suite"]["id"]: github(token, f"repos/{repo}/check-suites/{c['check_suite']['id']}")["head_branch"]
             for c in runs}
    return [c for c in runs if heads[c["check_suite"]["id"]] == "main"], "check suites of main"


def push_state(token, repo, sha, grace_seconds):
    """When the commit was pushed to main, and whether a workflow that push started is still running.

    Every GitHub App installed with checks permission gets a check suite of main as soon as the commit is pushed
    there, before any workflow starts, so the earliest one dates the push; the commit time can be much older.
    Workflow suites created within the grace period after it belong to that push (scheduled workflows on the
    same tip come later). Validation's Docker Push job starts only after its build, often more than 10 minutes
    after the push, so while such a suite is unfinished the run can still appear.
    """
    suites = [(datetime.datetime.fromisoformat(s["created_at"].replace("Z", "+00:00")).timestamp(), s)
              for s in github(token, f"repos/{repo}/commits/{sha}/check-suites", query={"per_page": 100})["check_suites"]
              if s.get("head_branch") == "main"]
    if not suites:
        return None, False
    pushed = min(t for t, _ in suites)
    running = any(t - pushed < grace_seconds and s["status"] != "completed"
                  and (s.get("app") or {}).get("slug") == "github-actions" for t, s in suites)
    return pushed, running


def wait(token, repo, commit):
    """Returns the commit whose published images to scan: the built commit or a first-parent ancestor.

    A missing Docker Push run means nothing until the commit has settled: its push to main (or, for a commit
    never pushed to main, the start of the wait) is older than the grace period, and no workflow that push
    started is still running. Only then does an ignored-paths commit fall back to its parent, or a missing run
    fail the job.
    """
    wait_seconds = int(os.environ.get("CG_IMAGE_WAIT_SECONDS", "1800"))
    grace_seconds = int(os.environ.get("CG_IMAGE_GRACE_SECONDS", "600"))
    start = time.time()
    skipped = 0
    ready = False

    def settled(c):
        pushed, running = push_state(token, repo, c, grace_seconds)
        return not running and time.time() - (pushed or start) >= grace_seconds

    while True:
        try:
            runs, method = publishing_runs(token, repo, commit)
            ready = not runs and settled(commit)
        except urllib.error.HTTPError as e:
            if e.code < 500 and e.code != 429:
                fail(f"GitHub API returned HTTP {e.code} for {e.url}")
            print(f"GitHub query failed (HTTP {e.code}); retrying", flush=True)
            runs = None
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"GitHub query failed ({e}); retrying", flush=True)
            runs = None
        if runs:
            done = [c for c in runs if c["status"] == "completed"]
            if any(c["conclusion"] == "success" for c in done):
                print(f"{CHECK} succeeded for {commit} (matched by {method})", flush=True)
                return commit
            if len(done) == len(runs):
                fail(f"{CHECK} for {commit} ended without success "
                     f"({', '.join(sorted({str(c['conclusion']) for c in done}))}); its images were not published, so "
                     "nothing is registered")
        elif runs is not None and ready and ignored_only(commit):
            if skipped == MAX_SKIPPED:
                fail(f"No published image within {MAX_SKIPPED} first-parent commits of {commit}")
            parent = git("log", "-1", "--format=%P", commit).split()[0]
            print(f"{commit} changes only files Validation's push filter ignores, so it published no image; "
                  f"its first parent {parent} ships the same image", flush=True)
            commit, skipped = parent, skipped + 1
            continue
        elif runs is not None and ready:
            fail(f"No push-triggered {CHECK} run exists for {commit}: Validation published no image for it, for "
                 "example a commit that never reached main or a push Validation skipped. Queue the run with explicit "
                 "images, or scan a commit that has a published image.")
        if time.time() - start > wait_seconds:
            fail(f"{CHECK} for {commit} did not finish within {wait_seconds // 60} minutes")
        print(f"Waiting for {CHECK} of {commit} ({int(time.time() - start)} s)", flush=True)
        time.sleep(POLL_SECONDS)


def main():
    env = os.environ
    os.chdir(env.get("BUILD_SOURCESDIRECTORY") or os.getcwd())
    path = os.path.join(env["OUT"], "cg-inputs.json")
    with open(path, encoding="utf-8") as f:
        inputs = json.load(f)
    try:
        if not inputs["imagesAuto"]:
            warn(f"Scanning explicitly requested images, not verified before registration: {inputs['images']}")
            return
        token = env.get("CG_GITHUB_TOKEN") or checkout_token()
        built = inputs["commit"]
        chosen = wait(token, env["BUILD_REPOSITORY_NAME"], built)
        if chosen != built:
            images = inputs["images"].replace(f":sha-{built[:12]}", f":sha-{chosen[:12]}")
            inputs.update(images=images, imagesCommit=chosen)
            write_json(path, inputs)
            print(f"##vso[task.setvariable variable=dockerImagesToScan]{images}")
        print(f"Scanning {inputs['images']}, published for {chosen}", flush=True)
    finally:
        drop_credentials()


if __name__ == "__main__":
    main()
