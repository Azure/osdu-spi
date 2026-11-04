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

"""Build and publish the fleet bill of materials.

build    reads the fleet list from the stack declaration, resolves each fork's
         latest release against a frozen template target, and writes bom.json.
publish  creates the fleet-YYYY.MM.DD release with bom.json attached, or
         succeeds without change when that release already holds the same BOM.

Needs git and gh on PATH; gh reads GH_TOKEN. GHCR is read anonymously.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

STACK_REPO = "Azure/osdu-spi-stack"
FLEET_PATH = "ops/environments/shared.yaml"
MARKER = ".github/.template-sync-commit"
DESCRIPTOR = ".spi/service.yaml"
IMAGE_SUFFIXES = ("", "-acceptance", "-load")
TOOLCHAIN_PROPERTIES = {
    "java": ("maven.compiler.release", "java.version"),
    "spring-boot": ("spring-boot.version",),
    "os-core-common": ("os-core-common.version",),
    "core-lib-azure": ("core-lib-azure.version",),
    "surefire": ("maven-surefire-plugin.version", "surefire.version"),
    "failsafe": ("maven-failsafe-plugin.version", "failsafe.version"),
}
NOTE = ("Records what each fork released and the stack version current at the time. "
        "It does not record what any environment runs.")
OCI_ACCEPT = ", ".join((
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
))


class BomError(Exception):
    pass


def run(*cmd, cwd=None, check=True):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise BomError(f"{' '.join(cmd)} failed: {proc.stderr.strip()}")
    return proc


def git(repo_dir, *args, check=True):
    return run("git", "-C", repo_dir, *args, check=check)


def gh_api(path, raw=False, check=True):
    cmd = ["gh", "api", path]
    if raw:
        cmd += ["-H", "Accept: application/vnd.github.raw"]
    return run(*cmd, check=check)


def unquote(value):
    value = value.split(" #", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def parse_forks(text):
    """Parses the top-level forks: list of flat maps from the stack declaration."""
    forks, current, inside = [], None, False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            inside = line.rstrip() == "forks:"
            continue
        if not inside:
            continue
        body = line.strip()
        if body.startswith("- "):
            current = {}
            forks.append(current)
            body = body[2:].strip()
        if current is None or ":" not in body:
            raise BomError(f"unexpected line in forks: {line!r}")
        key, value = body.split(":", 1)
        current[key.strip()] = unquote(value)
    for fork in forks:
        if not fork.get("service") or not fork.get("repo"):
            raise BomError(f"fork entry without service or repo: {fork}")
    return forks


def synced_paths(sync_config):
    rules = sync_config["sync_rules"]
    paths = [d["path"] for d in rules.get("directories", [])]
    paths += [f["path"] for f in rules.get("files", [])]
    paths += [w["path"] for w in rules.get("workflows", {}).get("template_workflows", [])]
    return paths


def effective_target(template_dir, target, paths):
    sha = git(template_dir, "log", "-1", "--format=%H", target, "--", *paths).stdout.strip()
    if not sha:
        raise BomError(f"no commit at or before {target} touches a synced path")
    return sha


def is_ancestor(repo_dir, ancestor, descendant):
    return git(repo_dir, "merge-base", "--is-ancestor", ancestor, descendant, check=False).returncode == 0


def commit_exists(repo_dir, sha):
    return git(repo_dir, "cat-file", "-e", f"{sha}^{{commit}}", check=False).returncode == 0


def nearest_upstream_sha(repo_dir, commit):
    """Walks first-parent history from commit to the nearest change that brought in
    generated upstream commits, and returns their Upstream-Sha. Fails when the newest
    generated commits there disagree."""
    for step in git(repo_dir, "rev-list", "--first-parent", commit).stdout.split():
        parents = git(repo_dir, "rev-list", "--parents", "-n", "1", step).stdout.split()[1:]
        span = [f"{parents[0]}..{step}"] if parents else ["-n", "1", step]
        log = git(repo_dir, "log", "--format=%H%x09%(trailers:key=Upstream-Sha,valueonly,separator=%x2C)",
                  *span).stdout
        generated = {}
        for line in log.splitlines():
            sha, _, values = line.partition("\t")
            values = {v.strip() for v in values.split(",") if v.strip()}
            if values:
                generated[sha] = values
        if not generated:
            continue
        newest = [g for g in generated
                  if not any(o != g and is_ancestor(repo_dir, g, o) for o in generated)]
        found = set().union(*(generated[g] for g in newest))
        if len(found) != 1:
            raise BomError(f"ambiguous Upstream-Sha at {step[:12]}: {', '.join(sorted(found))}")
        return found.pop()
    return None


def pom_properties(text):
    props = {}
    for child in ET.fromstring(text):
        if isinstance(child.tag, str) and child.tag.rsplit("}", 1)[-1] == "properties":
            for prop in child:
                if isinstance(prop.tag, str):
                    props[prop.tag.rsplit("}", 1)[-1]] = (prop.text or "").strip()
    return props


def expand(value, props, seen=()):
    ref = re.fullmatch(r"\$\{([^}]+)\}", value)
    if not ref:
        return value
    name = ref.group(1)
    if name in seen or name not in props:
        return None
    return expand(props[name], props, seen + (name,))


def toolchain(poms, descriptor):
    """Neutral map of the pins the build files declare. Root pom properties win over
    provider pom properties of the same name."""
    props = {}
    for text in reversed(poms):
        props.update(pom_properties(text))
    pins = {}
    if descriptor:
        match = re.search(r"^\s+archetype:\s*(\S+)", descriptor, re.M)
        if match:
            pins["archetype"] = unquote(match.group(1))
    for key, names in TOOLCHAIN_PROPERTIES.items():
        for name in names:
            if name in props:
                value = expand(props[name], props)
                if value:
                    pins[key] = value
                break
    return pins


def ghcr_digest(image, tag):
    """Digest of ghcr.io/<image>:<tag>, or None when the package or tag is absent."""
    scope = urllib.request.quote(f"repository:{image}:pull", safe=":/")
    try:
        with urllib.request.urlopen(f"https://ghcr.io/token?scope={scope}", timeout=30) as resp:
            token = json.load(resp)["token"]
    except urllib.error.HTTPError as err:
        if err.code in (401, 403, 404):
            return None
        raise
    req = urllib.request.Request(f"https://ghcr.io/v2/{image}/manifests/{tag}", method="HEAD",
                                 headers={"Authorization": f"Bearer {token}", "Accept": OCI_ACCEPT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.headers["Docker-Content-Digest"]
    except urllib.error.HTTPError as err:
        if err.code in (401, 403, 404):
            return None
        raise


class GitHubSource:
    """Live reads; tests substitute a fake with the same methods."""

    def __init__(self, work_dir):
        self.work_dir = work_dir

    def fleet_text(self):
        return gh_api(f"repos/{STACK_REPO}/contents/{FLEET_PATH}", raw=True).stdout

    def stack_version(self):
        return json.loads(gh_api(f"repos/{STACK_REPO}/releases/latest").stdout)["tag_name"]

    def latest_release(self, repo):
        proc = gh_api(f"repos/{repo}/releases/latest", check=False)
        if proc.returncode != 0:
            if "404" in proc.stderr or "Not Found" in proc.stderr:
                return None
            raise BomError(f"reading the latest release of {repo} failed: {proc.stderr.strip()}")
        return json.loads(proc.stdout)["tag_name"]

    def upstream_repository(self, repo):
        proc = gh_api(f"repos/{repo}/actions/variables/UPSTREAM_REPO_URL", check=False)
        return json.loads(proc.stdout)["value"] if proc.returncode == 0 else None

    def service_name(self, repo):
        proc = gh_api(f"repos/{repo}/actions/variables/SERVICE_NAME", check=False)
        return json.loads(proc.stdout)["value"] if proc.returncode == 0 else None

    def clone(self, repo):
        path = os.path.join(self.work_dir, repo.replace("/", "__") + ".git")
        if not os.path.isdir(path):
            run("git", "clone", "--quiet", "--bare", "--filter=blob:none",
                f"https://github.com/{repo}.git", path)
        return path

    def digest(self, image, tag):
        return ghcr_digest(image, tag)


def read_at(repo_dir, commit, path):
    proc = git(repo_dir, "show", f"{commit}:{path}", check=False)
    return proc.stdout if proc.returncode == 0 else None


def provider_poms(repo_dir, commit):
    names = git(repo_dir, "ls-tree", "-r", "--name-only", commit, "--", "provider").stdout.split()
    return sorted(n for n in names if re.fullmatch(r"provider/[^/]+-azure/pom\.xml", n))


def fork_entry(fork, source, template_dir, target):
    entry = {
        "service": fork["service"],
        "repo": fork["repo"],
        "canonicalSource": fork.get("canonicalSource"),
        "tier": fork.get("tier"),
        "version": None,
        "tag": None,
        "commit": None,
        "upstreamRepository": None,
        "upstreamSha": None,
        "images": [],
        "toolchain": {},
        "excluded": None,
    }

    def exclude(reason):
        entry["excluded"] = {"reason": reason}
        return entry

    tag = source.latest_release(fork["repo"])
    if not tag:
        return exclude("no release")
    clone = source.clone(fork["repo"])
    commit = git(clone, "rev-parse", f"{tag}^{{commit}}", check=False).stdout.strip()
    if not commit:
        return exclude(f"release {tag} has no tag in the repository")
    recorded = (read_at(clone, commit, MARKER) or "").strip()
    if not recorded:
        return exclude(f"{tag} records no template sync commit")
    if not commit_exists(template_dir, recorded):
        return exclude(f"{tag} records template commit {recorded[:12]}, which osdu-spi does not have")
    if not is_ancestor(template_dir, target, recorded):
        return exclude(f"{tag} is on template {recorded[:12]}, before the target {target[:12]}")

    version = tag[1:] if tag.startswith("v") else tag
    image = source.service_name(fork["repo"]) or fork["repo"].split("/", 1)[1]
    owner = fork["repo"].split("/", 1)[0].lower()
    images = []
    for suffix in IMAGE_SUFFIXES:
        digest = source.digest(f"{owner}/{image.lower()}{suffix}", version)
        if digest:
            images.append({"name": f"ghcr.io/{owner}/{image.lower()}{suffix}", "digest": digest})
    if not images or images[0]["name"] != f"ghcr.io/{owner}/{image.lower()}":
        return exclude(f"no service image ghcr.io/{owner}/{image.lower()}:{version}")
    built = source.digest(f"{owner}/{image.lower()}", f"sha-{commit[:12]}")
    if built and built != images[0]["digest"]:
        return exclude(f"image tag {version} is not the image built from {commit[:12]}")

    poms = [p for p in [read_at(clone, commit, "pom.xml")] +
            [read_at(clone, commit, n) for n in provider_poms(clone, commit)] if p]
    entry.update({
        "version": version,
        "tag": tag,
        "commit": commit,
        "upstreamRepository": source.upstream_repository(fork["repo"]),
        "upstreamSha": nearest_upstream_sha(clone, commit),
        "images": images,
        "toolchain": toolchain(poms, read_at(clone, commit, DESCRIPTOR)),
    })
    return entry


def build(args, source):
    with open(os.path.join(args.template_dir, ".github", "sync-config.json")) as fh:
        paths = synced_paths(json.load(fh))
    target = git(args.template_dir, "rev-parse", f"{args.template_target}^{{commit}}").stdout.strip()
    effective = effective_target(args.template_dir, target, paths)
    if args.fleet_file:
        with open(args.fleet_file) as fh:
            fleet_text = fh.read()
    else:
        fleet_text = source.fleet_text()
    forks = parse_forks(fleet_text)
    if not forks:
        raise BomError("the fleet list is empty")
    return {
        "schema": 1,
        "fleet": {
            "tag": f"fleet-{args.date.replace('-', '.')}",
            "date": args.date,
            "templateTarget": target,
            "effectiveTarget": effective,
            "environment": "shared",
            "stack": source.stack_version(),
        },
        "note": NOTE,
        "forks": [fork_entry(f, source, args.template_dir, effective) for f in forks],
    }


def canonical(bom):
    return json.dumps(bom, indent=2, sort_keys=True) + "\n"


def release_notes(bom):
    lines = [NOTE, "", "| Service | Version | Commit |", "| --- | --- | --- |"]
    for fork in bom["forks"]:
        if fork["excluded"]:
            lines.append(f"| {fork['service']} | excluded: {fork['excluded']['reason']} | |")
        else:
            lines.append(f"| {fork['service']} | {fork['version']} | {fork['commit'][:12]} |")
    return "\n".join(lines) + "\n"


def find_release(repo, tag):
    proc = run("gh", "api", "--paginate", f"repos/{repo}/releases?per_page=100",
               "--jq", f'.[] | select(.tag_name == "{tag}") | {{draft, id}}')
    found = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    return found[0] if found else None


def publish(args):
    with open(args.bom) as fh:
        bom = json.load(fh)
    tag = bom["fleet"]["tag"]
    target = bom["fleet"]["templateTarget"]
    existing = find_release(args.repo, tag)
    if existing:
        if existing["draft"]:
            raise BomError(f"a draft release for {tag} exists from an earlier run; "
                           f"a maintainer deletes it before this run is retried")
        with tempfile.TemporaryDirectory() as tmp:
            got = run("gh", "release", "download", tag, "-R", args.repo, "-p", "bom.json", "-D", tmp,
                      check=False)
            if got.returncode != 0:
                raise BomError(f"release {tag} exists without bom.json: {got.stderr.strip()}")
            with open(os.path.join(tmp, "bom.json")) as fh:
                published = json.load(fh)
        if canonical(published) != canonical(bom):
            raise BomError(f"release {tag} already holds a different bom.json; a fleet release is never rewritten")
        print(f"{tag} already holds this bom.json; nothing to publish")
        return
    if gh_api(f"repos/{args.repo}/git/ref/tags/{tag}", check=False).returncode == 0:
        raise BomError(f"tag {tag} exists without a release")
    with tempfile.TemporaryDirectory() as tmp:
        bom_path = os.path.join(tmp, "bom.json")
        notes_path = os.path.join(tmp, "notes.md")
        with open(bom_path, "w") as fh:
            fh.write(canonical(bom))
        with open(notes_path, "w") as fh:
            fh.write(release_notes(bom))
        run("gh", "release", "create", tag, bom_path, "-R", args.repo, "--target", target,
            "--title", tag, "--notes-file", notes_path, "--latest=false")
    print(f"published {tag} at {target[:12]}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("--date", required=True, help="YYYY-MM-DD")
    b.add_argument("--template-target", required=True)
    b.add_argument("--template-dir", default=".")
    b.add_argument("--fleet-file")
    b.add_argument("--work-dir")
    b.add_argument("--out", default="bom.json")
    b.add_argument("--summary", help="append the release notes table to this file")
    p = sub.add_parser("publish")
    p.add_argument("--bom", default="bom.json")
    p.add_argument("--repo", required=True)
    args = parser.parse_args(argv)

    try:
        if args.command == "build":
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date):
                raise BomError(f"date {args.date!r} is not YYYY-MM-DD")
            work_dir = args.work_dir or tempfile.mkdtemp(prefix="fleet-bom-")
            bom = build(args, GitHubSource(work_dir))
            with open(args.out, "w") as fh:
                fh.write(canonical(bom))
            if args.summary:
                with open(args.summary, "a") as fh:
                    fh.write(f"## {bom['fleet']['tag']}\n\n" + release_notes(bom))
            for fork in bom["forks"]:
                state = f"excluded: {fork['excluded']['reason']}" if fork["excluded"] else fork["version"]
                print(f"{fork['service']}: {state}", file=sys.stderr)
        else:
            publish(args)
    except BomError as err:
        print(f"::error::{err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
