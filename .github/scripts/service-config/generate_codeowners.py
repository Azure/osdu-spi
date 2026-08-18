#!/usr/bin/env python3
"""Seed or preserve the fork-owned CODEOWNERS rule for `/.spi/`.

The service descriptor selects the build archetype, so its review must be owned
by the engineering system (ADR-039). Repository rulesets only honour
`require_code_owner_review` when CODEOWNERS names an owner that actually has
access, and an unknown team makes the rule silently ineffective. The exact team
differs per organization, so the owner is configuration, not a hardcoded name:

  * `--owners "@my-org/engineering-system"` (repository variable
    `SPI_ENGINEERING_OWNERS`) writes an active rule;
  * without valid owners a documented, commented placeholder is written and
    settings-apply reports it through the existing onboarding issue.

Usage:
  generate_codeowners.py --path CODEOWNERS --owners "@my-org/eng-system"
  generate_codeowners.py --path CODEOWNERS --check

Exit codes:
  0  file written/preserved, or (with --check) an active `/.spi/` rule exists
  1  with --check: no active `/.spi/` rule (placeholder or missing file)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import List

BEGIN_MARKER = "# BEGIN spi-service-descriptor (managed by SPI initialization — ADR-039)"
END_MARKER = "# END spi-service-descriptor"
OWNERS_VARIABLE = "SPI_ENGINEERING_OWNERS"

_OWNER_TOKEN_RE = re.compile(r"^@([^/]+)(?:/([^/]+))?$")
_BLOCK_RE = re.compile(
    re.escape(BEGIN_MARKER) + r".*?" + re.escape(END_MARKER) + r"\n?",
    re.DOTALL,
)


def _valid_slug(value: str, max_length: int) -> bool:
    return (
        1 <= len(value) <= max_length
        and re.fullmatch(r"[A-Za-z0-9-]+", value) is not None
        and value[0] != "-"
        and value[-1] != "-"
        and "--" not in value
    )


def _valid_owner(token: str) -> bool:
    match = _OWNER_TOKEN_RE.fullmatch(token)
    if not match:
        return False
    login, team = match.groups()
    return _valid_slug(login, 39) and (team is None or _valid_slug(team, 100))


def valid_owners(raw: str) -> List[str]:
    """Return the owners that are syntactically valid GitHub users/teams."""

    tokens = raw.replace(",", " ").split()
    return tokens if tokens and all(_valid_owner(token) for token in tokens) else []


def has_active_rule(text: str) -> bool:
    for line in text.splitlines():
        content = line.split("#", 1)[0].strip()
        if not content:
            continue
        tokens = content.split()
        if tokens[0] == "/.spi/" and len(tokens) > 1:
            if all(_valid_owner(owner) for owner in tokens[1:]):
                return True
    return False


def render_block(owners: List[str]) -> str:
    lines = [
        BEGIN_MARKER,
        "#",
        "# `.spi/service.yaml` selects this repository's build archetype, so it is",
        "# reviewed by the engineering system rather than by service maintainers alone.",
        "# Template-sync never overwrites `.spi/**` or this file.",
    ]
    if owners:
        lines += [
            "#",
            f"/.spi/ {' '.join(owners)}",
        ]
    else:
        lines += [
            "#",
            f"# TODO(spi): choose a GitHub team/user that has access to this repository",
            '# (for example "@my-org/engineering-system"), run:',
            "#",
            "# python3 .github/scripts/service-config/generate_codeowners.py \\",
            '#   --path CODEOWNERS --owners "@my-org/engineering-system"',
            "#",
            f"# Commit CODEOWNERS and set {OWNERS_VARIABLE} to the same value for future",
            "# initialization. Settings Apply is read-only and only reports this condition.",
            "#",
            "# The rule stays commented out until a valid owner is configured: an unknown owner",
            "# makes the ruleset's require_code_owner_review silently ineffective.",
            "#",
            "# /.spi/ @<org>/<engineering-system-team>",
        ]
    lines += [END_MARKER, ""]
    return "\n".join(lines)


def apply_block(existing: str, owners: List[str]) -> str:
    """Add or refresh the managed block, preserving any other CODEOWNERS content."""

    block = render_block(owners)
    if _BLOCK_RE.search(existing):
        return _BLOCK_RE.sub(block, existing, count=1)
    if not existing.strip():
        return block
    separator = "" if existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
    return f"{existing}{separator}{block}"


def _parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", default="CODEOWNERS", help="CODEOWNERS file to seed or inspect")
    parser.add_argument(
        "--owners",
        default=os.environ.get(OWNERS_VARIABLE, ""),
        help=f"Owners (defaults to the {OWNERS_VARIABLE} environment variable)",
    )
    parser.add_argument("--check", action="store_true", help="Report whether an active rule exists")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = _parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):  # pragma: no cover - stream already fixed
            pass
    path = Path(args.path)
    existing = path.read_text(encoding="utf-8") if path.is_file() else ""

    if args.check:
        if has_active_rule(existing):
            print(f"✅ {path} requires an owner for /.spi/")
            return 0
        print(f"⚠️ {path} has no active /.spi/ owner rule")
        return 1

    if has_active_rule(existing) and not _BLOCK_RE.search(existing):
        print(f"✅ {path} already owns /.spi/ — preserving the fork-owned file")
        return 0

    owners = valid_owners(args.owners)
    if args.owners and not owners:
        print(f"::warning::Ignoring invalid {OWNERS_VARIABLE} value; writing the documented placeholder instead")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(apply_block(existing, owners), encoding="utf-8")

    if owners:
        print(f"✅ {path} now requires {' '.join(owners)} for /.spi/")
    else:
        print(f"⚠️ {path} contains a placeholder rule for /.spi/; set {OWNERS_VARIABLE} to activate it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
