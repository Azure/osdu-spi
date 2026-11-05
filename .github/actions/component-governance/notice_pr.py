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

"""Open or update a draft pull request that replaces NOTICE with the generated one.

Pushes chore/notice-refresh/<base> with the checkout's GitHub App token and
opens a draft pull request into the built branch, or updates the open one.
Weekly scheduled runs of main do this, and manual runs with openNoticePr.
The branch is only ever replaced by a refresh from a newer commit of the base
branch, or a later build of the same commit, and only at the tip this run saw.
A refresh that already holds this NOTICE for the same commit is left as it is,
so an unchanged base does not rerun the pull request's checks every week.

While the fork's upstream filter still keeps upstream's NOTICE, the refresh
also changes that verdict to strip, so syncs stop overwriting the generated
file, and the pull request body explains the one-time cutover (ADR-047).

Environment: NOTICE_OUT (from fetch_notice.py), BUILD_SOURCESDIRECTORY,
BUILD_REPOSITORY_NAME, BUILD_SOURCEBRANCH, BUILD_SOURCEVERSION, BUILD_BUILDID,
SYSTEM_COLLECTIONURI, SYSTEM_TEAMPROJECT, GITHUB_API_URL.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)

from cg_common import BOT_EMAIL, BOT_NAME, checkout_token, fail, git, github_or_fail  # noqa: E402

FILTER = ".github/upstream-filter.yml"
TITLE = "chore(notice): refresh NOTICE from Component Governance"
VERDICT_RE = re.compile(r"(?P<indent>[ ]+)NOTICE:(?P<sep>[ ]*)(?P<verdict>[a-z]+)(?P<rest>[ ]*(#.*)?)")


def notice_verdict(lines):
    """The index and match of NOTICE's verdict under top_level in the upstream filter config."""
    section = None
    for i, line in enumerate(lines):
        if line and not line[0].isspace() and not line.startswith("#"):
            section = line.split(":", 1)[0].strip()
        elif section == "top_level":
            m = VERDICT_RE.fullmatch(line.rstrip("\r"))
            if m:
                return i, m
    return None, None


def strip_upstream_notice():
    """Changes NOTICE: keep to strip. Returns True when it changed the file."""
    if not os.path.isfile(FILTER):
        return False
    with open(FILTER, encoding="utf-8", newline="") as f:
        lines = f.read().split("\n")
    i, m = notice_verdict(lines)
    if m is None or m["verdict"] != "keep":
        return False
    cr = "\r" if lines[i].endswith("\r") else ""
    lines[i] = f"{m['indent']}NOTICE:{m['sep']}strip{m['rest'] or ''}{cr}"
    with open(FILTER, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines))
    return True


def refuse_unless_older(token, repo, head):
    """The tip this run may replace and the source commit it was generated from: none, or this automation's
    refresh from an older source or an earlier build."""
    remote = git("ls-remote", "origin", f"refs/heads/{head}").split()
    if not remote:
        return "", ""
    git("fetch", "--depth=1", "origin", f"refs/heads/{head}")
    authors = git("log", "-1", "--format=%ae %ce", "FETCH_HEAD").split()
    if any(a != BOT_EMAIL for a in authors):
        fail(f"{head} has commits from someone else ({' '.join(authors)}); merge or close its pull request and "
             "delete the branch before the next refresh.")
    trailers = git("log", "-1", "--format=%(trailers:key=Source-Commit,valueonly,separator=%x20)%x00"
                   "%(trailers:key=Build-Id,valueonly,separator=%x20)", "FETCH_HEAD").split("\x00")
    theirs, their_build = (t.strip() for t in trailers)
    ours, our_build = os.environ["BUILD_SOURCEVERSION"], os.environ["BUILD_BUILDID"]
    if not theirs or not their_build.isdigit():
        fail(f"{head} has no Source-Commit/Build-Id trailers, so its age is unknown; close its pull request and "
             "delete the branch before the next refresh.")
    if theirs == ours:
        if int(their_build) >= int(our_build):
            fail(f"{head} was refreshed by build {their_build}, not older than this build {our_build}; not replacing it.")
    else:
        status = github_or_fail(token, f"repos/{repo}/compare/{theirs}...{ours}")["status"]
        if status != "ahead":
            fail(f"{head} holds a NOTICE generated from {theirs}, which is not older than this run's {ours} "
                 f"(compare: {status}); not replacing it.")
    return remote[0], theirs


def body(base, run_url, report, cutover):
    text = (f"Replaces `NOTICE` with the Component Governance NOTICE for `{base}`.\n\n"
            f"Generated by {run_url}.\n\n"
            "Component Governance cannot produce entries for some shipped components (listed below); "
            "they are not yet supplemented.\n\n")
    if cutover:
        text += ("### One-time cutover: NOTICE becomes fork-owned\n\n"
                 f"This pull request also changes `NOTICE: keep` to `NOTICE: strip` in `{FILTER}`, so upstream "
                 "syncs stop replacing the generated file (ADR-047).\n\n"
                 "1. `NOTICE` is still upstream-owned on this branch, so the ownership check fails: add the `port` "
                 "label and re-run Check Paths.\n"
                 "2. The next sync that regenerates `fork_upstream` removes upstream's `NOTICE` there, and the "
                 "cascade stops once on a modify/delete conflict on `NOTICE` and pushes nothing. In "
                 "`fork_integration`, merge `main` first, then `fork_upstream`, and keep this repository's file "
                 "(`git add NOTICE`); merging `fork_upstream` alone deletes it. Later syncs no longer touch it "
                 "(runbook: Component Governance).\n\n")
    return text + report


def main():
    env = os.environ
    os.chdir(env["BUILD_SOURCESDIRECTORY"])
    repo = env["BUILD_REPOSITORY_NAME"]
    base = env["BUILD_SOURCEBRANCH"].removeprefix("refs/heads/")
    head = "chore/notice-refresh/" + base
    with open(os.path.join(env["NOTICE_OUT"], "NOTICE"), encoding="utf-8") as f:
        notice = f.read()
    current = None
    if os.path.exists("NOTICE"):
        with open("NOTICE", encoding="utf-8") as f:
            current = f.read()
    if current == notice:
        print(f"NOTICE on {base} already matches the Component Governance NOTICE; no pull request.")
        return

    token = checkout_token()
    expected, source = refuse_unless_older(token, repo, head)
    run_url = f'{env["SYSTEM_COLLECTIONURI"]}{env["SYSTEM_TEAMPROJECT"]}/_build/results?buildId={env["BUILD_BUILDID"]}'
    with open("NOTICE", "w", encoding="utf-8", newline="\n") as f:
        f.write(notice)
    cutover = strip_upstream_notice()
    owner = repo.split("/")[0]
    # A weekly run of an unchanged base would otherwise push the same refresh again and rerun its checks.
    if source == env["BUILD_SOURCEVERSION"] and not git("diff", "--name-only", expected, "--", "NOTICE", FILTER):
        prs = github_or_fail(token, f"repos/{repo}/pulls", query={"head": f"{owner}:{head}", "base": base, "state": "all"})
        if prs:
            print(f"{head} already holds this NOTICE for {source} (pull request #{prs[0]['number']}, "
                  f"{prs[0]['state']}); nothing to push.")
            return
        print(f"{head} already holds this NOTICE for {source} but has no pull request; opening one.")
    else:
        git("checkout", "-B", head)
        git("add", "NOTICE", *([FILTER] if cutover else []))
        # The environment outranks git config, so an agent's GIT_AUTHOR_* cannot claim the commit. No [skip ci]:
        # the pull request's required checks must run on this commit.
        identity = {"GIT_AUTHOR_NAME": BOT_NAME, "GIT_AUTHOR_EMAIL": BOT_EMAIL,
                    "GIT_COMMITTER_NAME": BOT_NAME, "GIT_COMMITTER_EMAIL": BOT_EMAIL}
        git("commit", "-m", TITLE,
            "-m", f"Generated by {run_url} from the Component Governance snapshot of {base}.",
            "-m", f"Source-Commit: {env['BUILD_SOURCEVERSION']}\nBuild-Id: {env['BUILD_BUILDID']}", env=identity)
        git("push", f"--force-with-lease=refs/heads/{head}:{expected}", "origin", f"HEAD:refs/heads/{head}")
        print(f"pushed {head} at {git('rev-parse', 'HEAD')}" + (" (upstream NOTICE stripped)" if cutover else ""))

    with open(os.path.join(env["NOTICE_OUT"], "notice-report.md"), encoding="utf-8") as f:
        report = f.read()
    text = body(base, run_url, report, cutover)
    existing = github_or_fail(token, f"repos/{repo}/pulls", query={"head": f"{owner}:{head}", "base": base, "state": "open"})
    if existing:
        pr = github_or_fail(token, f"repos/{repo}/pulls/{existing[0]['number']}", "PATCH", {"title": TITLE, "body": text})
        print(f"updated pull request #{pr['number']} {pr['html_url']} (author {pr['user']['login']})")
    else:
        pr = github_or_fail(token, f"repos/{repo}/pulls", "POST",
                            {"title": TITLE, "head": head, "base": base, "body": text, "draft": True})
        print(f"opened pull request #{pr['number']} {pr['html_url']} (author {pr['user']['login']})")


if __name__ == "__main__":
    main()
