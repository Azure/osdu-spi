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

"""Print the Java release a root pom declares.

Reads maven.compiler.release, then java.version, from the pom's own
<properties> (profiles and parents are not consulted) and defaults to 17 when
neither is set. Exits 1 on a release the build images do not carry.

Usage: resolve.py [pom.xml]
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

# Each release needs a runtime-<n> stage in build/Dockerfile and a maven-<n>
# stage in build/acceptance.Dockerfile.
SUPPORTED = ("17", "25")
DEFAULT = "17"
KEYS = ("maven.compiler.release", "java.version")


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def pom_properties(path):
    props = {}
    for child in ET.parse(path).getroot():
        if isinstance(child.tag, str) and local_name(child.tag) == "properties":
            for prop in child:
                if isinstance(prop.tag, str):
                    props[local_name(prop.tag)] = (prop.text or "").strip()
    return props


def expand(value, props, seen=()):
    ref = re.fullmatch(r"\$\{([^}]+)\}", value)
    if not ref:
        return value
    name = ref.group(1)
    if name in seen or name not in props:
        return None
    return expand(props[name], props, seen + (name,))


def resolve(path):
    if not os.path.isfile(path):
        return DEFAULT, f"no {path}; using the default"
    props = pom_properties(path)
    for key in KEYS:
        if key in props:
            release = expand(props[key], props)
            if release is None:
                raise ValueError(f"{key} in {path} is '{props[key]}', which does not resolve within the pom")
            return release, f"{key} in {path}"
    return DEFAULT, f"neither {' nor '.join(KEYS)} is set in {path}; using the default"


def main(argv):
    path = argv[1] if len(argv) > 1 else "pom.xml"
    try:
        release, source = resolve(path)
    except (ValueError, ET.ParseError) as err:
        print(f"::error::Cannot resolve the Java release: {err}", file=sys.stderr)
        return 1
    if release not in SUPPORTED:
        print(f"::error::Java release {release} ({source}) is not supported; "
              f"the build images carry {', '.join(SUPPORTED)}", file=sys.stderr)
        return 1
    print(f"Java release {release} ({source})", file=sys.stderr)
    print(release)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
