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

"""Fetch the NOTICE Component Governance generates from this run's scan.

Finds the snapshot the scan job of this build registered, downloads its NOTICE
through the Component Governance API (the same call the notice@0 task makes),
and writes to $NOTICE_OUT:

  NOTICE                 the generated file, LF line endings
  notice-excluded.json   registered components without an entry, by reason
  notice-report.json/md  counts and the components a reader should know are missing

Fails when the scan could not include a container image: Component Governance
only warns about that and registers the snapshot without the image.

Environment: NOTICE_OUT, CG_SCAN_PHASE (the scan job's display name),
SYSTEM_ACCESSTOKEN and the predefined SYSTEM_* / BUILD_* variables,
CG_POLL_ATTEMPTS (20), CG_POLL_SECONDS (30).
"""

import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)

from cg_common import POLL_SECONDS, ado_get, fail, write_json  # noqa: E402

API_VERSION = "api-version=7.1-preview.1"
GOVERNANCE_AREA = "7136235f-d277-4c27-9194-e3ada05fea2c"
CG_TASK = "ComponentGovernanceComponentDetection"
ENTRY_SEPARATOR = "\n---------------------------------------------------------\n"
UNSCANNED_RE = re.compile(r"Processing of image (\S+) \(kind \"DockerImage\"\) failed")


def find_snapshot(api, gid, prefix, phase, build):
    """Registration is processed asynchronously; wait until this build's snapshot of the scan job is visible."""
    attempts = int(os.environ.get("CG_POLL_ATTEMPTS", "20"))
    for attempt in range(1, attempts + 1):
        found = [(b, t) for b in ado_get(f"{api}/{gid}/branches?{API_VERSION}")["value"] for t in b.get("snapshotTypes", [])
                 if t["buildType"].lower().startswith(prefix) and t.get("phaseDisplayName") == phase
                 and str(t.get("latestScanBuildIdentifier")) == build]
        if found:
            if len(found) != 1:
                fail(f"Expected one snapshot for build {build} job '{phase}', found {len(found)}")
            return found[0]
        if attempt < attempts:
            print(f"Snapshot of build {build} is not visible yet (attempt {attempt}); waiting {POLL_SECONDS} s", flush=True)
            time.sleep(POLL_SECONDS)
    fail(f"No snapshot of build {build} job '{phase}' appeared after {attempts} attempts")


def label(item):
    """noDefinition/noCopyright items are ClearlyDefined coordinates; the others are component objects."""
    if isinstance(item, str):
        p = item.split("/")
        if len(p) < 5:
            return item
        return f"{p[3]}:{p[4]}" if p[2] == "-" else f"{p[2]}:{p[3]}:{p[4]}"
    kind = item.get("type") or "os"
    return f"{item.get('displayName')}:{item.get('displayVersion')}" + ("" if kind == "maven" else f" ({kind})")


def report(out, gid, tid, build, content, excluded):
    entries = set()
    for block in content.split(ENTRY_SEPARATOR)[1:]:
        lines = block.strip().splitlines()
        m = re.match(r"(\S+) (\S+) - (.+)$", lines[0].strip()) if lines else None
        if m:
            entries.add((m.group(1).lower(), m.group(2).lower()))
    # noCopyright components are in the NOTICE, without a copyright line; every other reason is a missing entry.
    gaps = {k: sorted({label(i) for i in v}) for k, v in sorted(excluded.items()) if v and k != "noCopyright"}
    os_packages = len(excluded.get("notSupported") or [])
    no_copyright = len(excluded.get("noCopyright") or [])
    data = {"governedRepository": gid, "snapshotType": tid, "build": build, "noticeEntries": len(entries),
            "noticeEntriesWithoutCopyright": no_copyright, "imagePackagesNotSupported": os_packages,
            "notInNotice": gaps, "excludedCounts": {k: len(v) for k, v in excluded.items()}}
    write_json(os.path.join(out, "notice-report.json"), data)

    print(f"NOTICE: {len(content)} characters, {len(entries)} entries ({no_copyright} without a copyright line)")
    print("excluded by reason:", data["excludedCounts"])
    md = ["## Component Governance NOTICE", "",
          f"Snapshot type {tid} of build {build}: {len(entries)} entries, {no_copyright} without a copyright line.", "",
          "Registered components that Component Governance leaves out of the NOTICE. Registrations include test",
          "scope, so `excluded` is mostly test dependencies. `notSupported` are the container image's operating",
          f"system packages ({os_packages}), which the Component Governance NOTICE does not cover. The NOTICE is not",
          "yet checked against the jar the image ships (ADR-047).", "",
          "| Reason | Count |", "| --- | --- |"]
    md += [f"| {k} | {len(v)} |" for k, v in gaps.items()]
    for k, v in gaps.items():
        print(f"  {k} ({len(v)}): " + ", ".join(v))
        md += ["", f"**{k}**: " + ", ".join(f"`{x}`" for x in v)]
    with open(os.path.join(out, "notice-report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(md) + "\n")
    print(f"##vso[task.uploadsummary]{os.path.join(out, 'notice-report.md')}")
    return os_packages


def check_images_scanned(collection, proj, build, phase, os_packages):
    """The Component Governance step only warns when it cannot scan an image. Fail instead: the snapshot would
    show the image's alerts as fixed until a complete scan replaces it."""
    timeline = ado_get(f"{collection}{proj}/_apis/build/builds/{build}/timeline?api-version=7.1")["records"]
    jobs = {r["id"] for r in timeline if r.get("type") == "Job" and r.get("name") == phase}
    steps = [r for r in timeline if r.get("type") == "Task" and r.get("parentId") in jobs and r.get("result") != "skipped"
             and (r.get("task") or {}).get("name") == CG_TASK]
    if len(steps) != 1 or steps[0].get("result") != "succeeded" or not steps[0].get("log"):
        fail(f"Expected one succeeded Component Governance step in job '{phase}', found "
             + (", ".join(f"{r.get('name')}={r.get('result')}" for r in steps) or "none"))
    scan_log = ado_get(steps[0]["log"]["url"], raw=True)
    unscanned = sorted({m.group(1) for m in UNSCANNED_RE.finditer(scan_log)})
    if unscanned or os_packages == 0:
        fail("The snapshot is missing container images: "
             + (", ".join(f"{i} could not be scanned" for i in unscanned) or "it has no operating system packages")
             + ". Rerun once the images are published.")


def main():
    env = os.environ
    out = env["NOTICE_OUT"]
    os.makedirs(out, exist_ok=True)
    collection = env["SYSTEM_COLLECTIONURI"]
    proj, repo, build = env["SYSTEM_TEAMPROJECTID"], env["BUILD_REPOSITORY_NAME"], env["BUILD_BUILDID"]
    phase = env["CG_SCAN_PHASE"]

    gov = ado_get(f"{collection}_apis/resourceareas/{GOVERNANCE_AREA}?{API_VERSION}")["locationUrl"]
    api = f"{gov.rstrip('/')}/{proj}/_apis/componentgovernance/governedrepositories"
    repos = [r for r in ado_get(f"{api}?{API_VERSION}")["value"] if (r.get("name") or "").lower() == repo.lower()]
    if len(repos) != 1:
        fail(f"Expected one governed repository named {repo}, found {len(repos)}")
    gid = repos[0]["id"]

    prefix = f'vsts://{env["SYSTEM_COLLECTIONID"]}/{proj}/{env["SYSTEM_DEFINITIONID"]}/'.lower()
    branch, stype = find_snapshot(api, gid, prefix, phase, build)
    tid = stype["typeId"]
    print(f"governed repository {gid}, branch {branch['moniker']}, snapshot type {tid}, build {build}")

    res = ado_get(f"{api}/{gid}/Notice?snapshotTypeId={tid}&format=text&{API_VERSION}")
    # The Notice API takes a snapshot type, not a snapshot: make sure no later run replaced this run's scan.
    latest = [str(t.get("latestScanBuildIdentifier")) for b in ado_get(f"{api}/{gid}/branches?{API_VERSION}")["value"]
              for t in b.get("snapshotTypes", []) if t["typeId"] == tid]
    if latest != [build]:
        fail(f"Snapshot type {tid} now belongs to build {latest}, not {build}: a concurrent run of this pipeline "
             "superseded it. Rerun when no other run of this branch is in progress.")
    content = res["content"].replace("\r\n", "\n")
    excluded = res.get("excludedComponents") or {}
    with open(os.path.join(out, "NOTICE"), "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    write_json(os.path.join(out, "notice-excluded.json"), excluded)

    os_packages = report(out, gid, tid, build, content, excluded)
    check_images_scanned(collection, proj, build, phase, os_packages)


if __name__ == "__main__":
    main()
