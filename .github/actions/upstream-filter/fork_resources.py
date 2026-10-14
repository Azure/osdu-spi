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

"""Renders the fork resources that name fork-owned paths from the filter config's
fork_owned list: the Dependabot directories, the CODEOWNERS ownership lines and the
CONTRIBUTING.md ownership row.

    fork_resources.py explicit     --config CFG
    fork_resources.py dependabot   --config CFG --checkout DIR  < template > rendered
    fork_resources.py codeowners   --config CFG                 < template > rendered
    fork_resources.py contributing --config CFG                 < template > rendered

A config without fork_owned, or no config at all, passes the template through byte for
byte. `explicit` exits 0 when the config lists fork_owned and 1 when it does not.

Exit codes: 0 rendered, 1 not explicit, 2 config or template error, 3 no fork-owned
tree holds a pom.xml, so Dependabot has no directory to watch.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from upstream_filter import Halt, load_config  # noqa: E402

DEPENDABOT_DEFAULTS = (
    re.compile(r'^(\s*)- "/provider/\*-azure"\s*$'),
    re.compile(r'^(\s*)- "/testing/\*-test-azure"\s*$'),
)
CODEOWNERS_DEFAULTS = (
    re.compile(r"^/provider/<service>-azure/\s+<owners>\s*$"),
    re.compile(r"^/testing/<service>-test-azure/\s+<owners>\s*$"),
)
CONTRIBUTING_DEFAULT = "`provider/*-azure/`, `testing/*-test-azure/`"
# Paths go unescaped into YAML strings, CODEOWNERS patterns and Markdown cells.
RENDER_SAFE_PATH = re.compile(r"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$")


class TemplateError(Exception):
    pass


def _printable(name):
    # A rejected name goes to the log; escaped, it can't open a line that Actions reads as a command.
    return name.encode("unicode_escape").decode("ascii")


def explicit_paths(config):
    if not config or not os.path.isfile(config):
        return None
    cfg = load_config(config)
    if "fork_owned" not in cfg:
        return None
    paths = list(cfg["fork_owned"])
    unsafe = [p for p in paths if not RENDER_SAFE_PATH.fullmatch(p)]
    if unsafe:
        raise Halt("CONFIG_INVALID", f"fork_owned paths must be letters, digits, '.', '_', '-' and '/': {', '.join(_printable(p) for p in unsafe)}")
    return paths


def maven_directories(paths, checkout):
    """Each fork-owned tree with a root pom; a tree without one contributes the modules
    one level down that have their own, as the reference services nest them."""
    dirs = []
    for path in paths:
        root = os.path.join(checkout, path)
        if os.path.isfile(os.path.join(root, "pom.xml")):
            dirs.append(f"/{path}")
            continue
        if os.path.isdir(root):
            for child in sorted(os.listdir(root)):
                if not os.path.isfile(os.path.join(root, child, "pom.xml")):
                    continue
                if not RENDER_SAFE_PATH.fullmatch(child):
                    print(f"warning: skipping module {path}/{_printable(child)}: name is not letters, digits, '.', '_' and '-'", file=sys.stderr)
                    continue
                dirs.append(f"/{path}/{child}")
    return dirs


def replace_pair(lines, patterns, render, what):
    """Swaps the two adjacent default lines for the rendered ones."""
    for i in range(len(lines) - 1):
        first = patterns[0].match(lines[i])
        if first and patterns[1].match(lines[i + 1]):
            return lines[:i] + render(first, lines[i]) + lines[i + 2:]
    raise TemplateError(f"the template no longer carries the default {what} lines")


def render_dependabot(text, paths, checkout):
    dirs = maven_directories(paths, checkout)
    if not dirs:
        return None
    lines = text.splitlines(keepends=True)

    def render(match, line):
        newline = "\n" if line.endswith("\n") else ""
        return [f'{match.group(1)}- "{d}"{newline}' for d in dirs]

    return "".join(replace_pair(lines, DEPENDABOT_DEFAULTS, render, "Dependabot directory"))


def render_codeowners(text, paths):
    lines = text.splitlines(keepends=True)

    def render(_match, line):
        column = line.index("<owners>")
        newline = "\n" if line.endswith("\n") else ""
        return [f"{('/' + p + '/').ljust(column - 1)} <owners>{newline}" for p in paths]

    return "".join(replace_pair(lines, CODEOWNERS_DEFAULTS, render, "CODEOWNERS ownership"))


def render_contributing(text, paths):
    if text.count(CONTRIBUTING_DEFAULT) != 1:
        raise TemplateError("the template no longer carries the default ownership paths once")
    return text.replace(CONTRIBUTING_DEFAULT, ", ".join(f"`{p}/`" for p in paths))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("kind", choices=["explicit", "dependabot", "codeowners", "contributing"])
    parser.add_argument("--config")
    parser.add_argument("--checkout", default=".")
    args = parser.parse_args(argv)

    try:
        paths = explicit_paths(args.config)
    except Halt as halt:
        print(f"error: {halt.code}: {halt.detail}", file=sys.stderr)
        return 2
    if args.kind == "explicit":
        return 0 if paths else 1

    raw = sys.stdin.buffer.read()
    if not paths:
        sys.stdout.buffer.write(raw)
        return 0
    text = raw.decode("utf-8")
    try:
        if args.kind == "dependabot":
            rendered = render_dependabot(text, paths, args.checkout)
            if rendered is None:
                print(f"error: no fork-owned tree holds a pom.xml: {', '.join(paths)}", file=sys.stderr)
                return 3
        elif args.kind == "codeowners":
            rendered = render_codeowners(text, paths)
        else:
            rendered = render_contributing(text, paths)
    except TemplateError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    sys.stdout.buffer.write(rendered.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
