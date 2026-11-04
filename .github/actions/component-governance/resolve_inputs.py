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

"""Resolve the inputs of the Component Governance scan from the checkout.

Reads the componentGovernance section of .spi/service.yaml, validated by the
acceptance resolver's descriptor contract, and sets the variables the
Component Governance step reads:

  MAVEN_ARGS                           -P <profiles> -pl <module> -am, so Maven
                                       detection covers the shipped module only
  dockerImagesToScan                   the images Validation published
  ComponentDetection.IgnoreDirectories the descriptor's ignoreDirectories

Writes cgmanifest.json (the OSDU upstream commits and the Application
Insights agent, which no detector sees) to the checkout and to $OUT, and the
resolved inputs to $OUT/cg-inputs.json for the image gate and the artifact.

Environment: OUT, BUILD_REPOSITORY_NAME, BUILD_SOURCEVERSION, CG_IMAGES
(auto or a comma separated list), CG_DESCRIPTOR (default .spi/service.yaml).
"""

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "acceptance-resolver"))

from cg_common import fail, git, warn, write_json  # noqa: E402
from resolve import Halt, parse_descriptor_yaml, validate_descriptor  # noqa: E402

DEFAULT_PROFILES = ["core", "azure"]
GENERATED_SUBJECTS = ("chore: generate filtered upstream tree", "chore: mirror upstream tree")
IMAGES_RE = re.compile(r"[A-Za-z0-9._/:@-]+(,[A-Za-z0-9._/:@-]+)*")


def load_descriptor(path):
    """The descriptor contract (schema v3) also limits the archetype to java-maven-azure."""
    try:
        with open(path, encoding="utf-8") as f:
            desc = parse_descriptor_yaml(f.read())
        validate_descriptor(desc)
    except FileNotFoundError:
        fail(f"{path} is missing")
    except Halt as e:
        fail(f"{path}: {e}")
    if "componentGovernance" not in desc:
        fail(f"{path} has no componentGovernance section; add one with the fork's upstream URL (runbook: Component Governance)")
    return desc


def existing_dir(root, value, key):
    """The descriptor contract already refused '.', '..' and absolute paths; the checkout must agree."""
    if os.path.realpath(os.path.join(root, value)) != os.path.join(root, *value.split("/")):
        fail(f"componentGovernance.{key}: {value} resolves through a symbolic link")
    if not os.path.isdir(os.path.join(root, value)):
        fail(f"componentGovernance.{key}: {value} does not exist")
    return value


def infer_module(service):
    """The Spring Boot module under provider/*-azure, as the docker-build action finds the shipped JAR."""
    candidates = []
    for top in sorted(os.listdir("provider")) if os.path.isdir("provider") else []:
        if not top.endswith("-azure") or not os.path.isdir(f"provider/{top}"):
            continue
        subs = sorted(f"provider/{top}/{s}" for s in os.listdir(f"provider/{top}") if os.path.isdir(f"provider/{top}/{s}"))
        for d in [f"provider/{top}"] + subs:
            pom = os.path.join(d, "pom.xml")
            if os.path.isfile(pom):
                with open(pom, encoding="utf-8") as f:
                    if "spring-boot-maven-plugin" in f.read():
                        candidates.append(d)
    preferred = [d for d in candidates if d.startswith(f"provider/{service}-azure")]
    picks = preferred if len(preferred) == 1 else candidates
    if len(picks) != 1:
        fail(f"Cannot infer the shipped module (Spring Boot modules under provider/*-azure: {candidates or 'none'}); "
             "set componentGovernance.module")
    return picks[0]


def generated(commit):
    return git("log", "-1", "--format=%s", commit) in GENERATED_SUBJECTS


def upstream_commits():
    """The upstream commit of the newest generated upstream tree reachable from HEAD, plus seed snapshots.

    generate-branch.sh makes upstream the last parent of a generated commit: the second after a base,
    the only one on the first generation. Seeded-From names the upstream commits the fork-owned trees
    were copied from at initialization.
    """
    grep = ["--grep=^Upstream-Sha: [0-9a-f]\\{40\\}$", "--grep=^Filter-Rev: ", "--all-match"]
    cands = [c for c in git("rev-list", "--topo-order", *grep, "HEAD").split() if generated(c)]
    if not cands:
        fail("No generated upstream commit is reachable from HEAD")
    chosen = cands[0]
    others = [c for c in git("rev-list", *grep, "HEAD", f"^{chosen}").split() if generated(c)]
    if others:
        fail(f"Ambiguous upstream provenance: generated commits {others} are not ancestors of {chosen}")
    up = "".join(git("log", "-1", "--format=%(trailers:key=Upstream-Sha,valueonly,separator=)", chosen).split())
    parents = git("log", "-1", "--format=%P", chosen).split()
    if len(parents) not in (1, 2) or up != parents[-1]:
        fail(f"Upstream-Sha of {chosen} is not its upstream parent (parents: {parents})")
    seeds = []
    for line in git("log", "HEAD", "--grep=^Seeded-From: ", "--format=%(trailers:key=Seeded-From,valueonly)").splitlines():
        if not line.strip():
            continue
        m = re.fullmatch(r"[A-Za-z0-9._/-]+ ([0-9a-f]{40})", line.strip())
        if not m:
            fail(f"Malformed Seeded-From trailer {line.strip()!r}; expected '<path> <40-hex commit>'")
        if subprocess.run(["git", "merge-base", "--is-ancestor", m.group(1), "HEAD"], capture_output=True).returncode != 0:
            fail(f"Seeded-From commit {m.group(1)} is not an ancestor of HEAD")
        seeds.append(m.group(1))
    shas = list(dict.fromkeys([up] + seeds))
    if not all(re.fullmatch(r"[0-9a-f]{40}", s) for s in shas):
        fail(f"Invalid upstream commit hashes: {shas}")
    return chosen, up, sorted(set(seeds)), shas


def main():
    env = os.environ
    root = os.path.realpath(env.get("BUILD_SOURCESDIRECTORY") or os.getcwd())
    os.chdir(root)
    out = env["OUT"]
    os.makedirs(out, exist_ok=True)

    descriptor = env.get("CG_DESCRIPTOR") or ".spi/service.yaml"
    desc = load_descriptor(descriptor)
    service = desc["service"]["name"]
    cg = desc["componentGovernance"]
    upstream = cg["upstream"]
    profiles = cg.get("profiles") or DEFAULT_PROFILES
    module = existing_dir(root, cg["module"], "module") if "module" in cg else infer_module(service)
    if not os.path.isfile(os.path.join(module, "pom.xml")):
        fail(f"Shipped module {module} has no pom.xml")
    ignore = [existing_dir(root, d, "ignoreDirectories") for d in (cg.get("ignoreDirectories") or [])]
    if any(module == d or module.startswith(d + "/") for d in ignore):
        fail(f"componentGovernance.ignoreDirectories must not contain the shipped module {module}")

    settings = os.path.join(root, ".mvn", "community-maven.settings.xml")
    if not os.path.isfile(settings):
        fail(".mvn/community-maven.settings.xml is missing")
    maven_args = f"--settings={settings} -P {','.join(profiles)} -pl {module} -am"

    owner, repo = env["BUILD_REPOSITORY_NAME"].lower().split("/", 1)
    sha = env["BUILD_SOURCEVERSION"]
    images = env.get("CG_IMAGES", "").strip()
    images_auto = images in ("", "auto")
    if images_auto:
        # Validation's Docker Push job publishes these for the commit: the service image, and the loader
        # image when the fork carries shared schemas. The acceptance image is test tooling and not scanned.
        refs = [f"ghcr.io/{owner}/{repo}:sha-{sha[:12]}"]
        if os.path.isdir("deployments/shared-schemas") and os.listdir("deployments/shared-schemas"):
            refs.append(f"ghcr.io/{owner}/{repo}-load:sha-{sha[:12]}")
        images = ",".join(refs)
    if not IMAGES_RE.fullmatch(images):
        fail(f"images: {images!r} is not a comma separated list of image references")

    generated_commit, up, seeds, shas = upstream_commits()
    registrations = [{"component": {"type": "git", "git": {"repositoryUrl": upstream, "commitHash": s}}} for s in shas]

    # The canonical image adds the Application Insights agent outside Maven (build/Dockerfile).
    agent = None
    if os.path.isfile("build/Dockerfile"):
        with open("build/Dockerfile", encoding="utf-8") as f:
            m = re.search(r'^ARG APPLICATIONINSIGHTS_AGENT_VERSION="?([0-9][0-9A-Za-z.\-]*)"?\s*$', f.read(), re.M)
        if m:
            agent = m.group(1)
            registrations.append({"component": {"type": "maven", "maven": {
                "groupId": "com.microsoft.azure", "artifactId": "applicationinsights-agent", "version": agent}}})
    if not agent:
        warn("build/Dockerfile declares no APPLICATIONINSIGHTS_AGENT_VERSION; the agent was not registered")

    manifest = {"$schema": "https://json.schemastore.org/component-detection-manifest.json", "version": 1,
                "registrations": registrations}
    write_json("cgmanifest.json", manifest)
    write_json(os.path.join(out, "cgmanifest.json"), manifest)

    resolved = {"service": service, "commit": sha, "upstream": upstream, "upstreamCommit": up,
                "generatedCommit": generated_commit, "seeds": seeds, "module": module, "profiles": profiles,
                "mavenArgs": maven_args, "images": images, "imagesAuto": images_auto,
                "imagesCommit": sha if images_auto else None, "ignoreDirectories": ignore,
                "applicationInsightsAgent": agent}
    write_json(os.path.join(out, "cg-inputs.json"), resolved)
    for k, v in resolved.items():
        print(f"{k}: {v}")
    print(f"##vso[task.setvariable variable=MAVEN_ARGS]{maven_args}")
    print(f"##vso[task.setvariable variable=dockerImagesToScan]{images}")
    if ignore:
        print(f"##vso[task.setvariable variable=ComponentDetection.IgnoreDirectories]{','.join(ignore)}")


if __name__ == "__main__":
    main()
