#!/usr/bin/env python3
"""Read and validate the fork-owned service descriptor for the copied workflows.

Emits the fixed `read-service-config` output contract (ADR-039). The descriptor
never yields shell commands, credentials or deployment targets — only closed
enums, names and paths.

Usage:
  read_service_config.py --root . --service-name partition --format github \
      --output "$GITHUB_OUTPUT" --summary "$GITHUB_STEP_SUMMARY"
  read_service_config.py --root . --format json --redact

Exit codes:
  0  descriptor valid, or absent (legacy Java inference / no lane)
  1  descriptor present but invalid — fail closed
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import descriptor as descriptor_module  # noqa: E402  (path set above for standalone use)


def _parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Repository root to inspect")
    parser.add_argument(
        "--service-name",
        default="",
        help="Fallback service name used when the descriptor is absent",
    )
    parser.add_argument("--format", choices=["github", "json"], default="github")
    parser.add_argument("--output", default="", help="File receiving key=value outputs")
    parser.add_argument("--summary", default="", help="File receiving a Markdown summary")
    parser.add_argument(
        "--redact",
        action="store_true",
        help="Report stable error codes instead of messages (for issue bodies)",
    )
    return parser.parse_args(argv)


def _render_summary(config: descriptor_module.ResolvedConfig, redact: bool) -> str:
    lines = ["### 🧭 Service configuration", ""]
    if config.descriptor_present:
        lines.append(f"- Descriptor: `{descriptor_module.DESCRIPTOR_PATH}` (schemaVersion {config.schema_version or 'unknown'})")
    else:
        lines.append(f"- Descriptor: none — `{descriptor_module.DESCRIPTOR_PATH}` not found")
    lines.append(f"- Build lane: `{config.build_lane}`")
    if config.archetype:
        lines.append(f"- Archetype: `{config.archetype}`")
    if config.build_lane == "python":
        lines.append(f"- Python runtime: `{config.python_runtime_version or 'default'}`")
        lines.append(f"- Application module: `{config.app_module or 'not declared'}`")
        if config.python_runtime_extras:
            lines.append(f"- Runtime extras: `{config.python_runtime_extras}`")
    if config.fallback != "none":
        lines.append(f"- Fallback: `{config.fallback}`")
    for warning in config.warnings:
        lines.append(f"- ⚠️ {warning}")
    for error in config.errors:
        lines.append(f"- ❌ {error.render(redact=redact)}")
    lines.append("")
    return "\n".join(lines)


def main(argv=None) -> int:
    args = _parse_args(argv)
    descriptor_module.configure_stdio()
    config = descriptor_module.resolve(Path(args.root), service_name=args.service_name)

    # In JSON mode every diagnostic goes to stderr so stdout stays machine-readable.
    annotations = sys.stderr if args.format == "json" else sys.stdout

    if args.format == "json":
        print(json.dumps(config.to_json_dict(redact=args.redact), indent=2, sort_keys=True))
    else:
        outputs = config.outputs()
        # $GITHUB_OUTPUT is line-based: a value carrying a newline would define extra
        # outputs. The parser and schema already make this impossible, so treat it as a
        # tamper signal and fail closed rather than writing the file.
        for key, value in outputs.items():
            if "\n" in value or "\r" in value:
                sys.stderr.write(
                    f"::error::Refusing to publish multi-line output '{key}' from "
                    f"{descriptor_module.DESCRIPTOR_PATH}\n"
                )
                return 1
        rendered = "".join(f"{key}={value}\n" for key, value in outputs.items())
        if args.output:
            with open(args.output, "a", encoding="utf-8") as stream:
                stream.write(rendered)
        else:
            sys.stdout.write(rendered)

    summary = _render_summary(config, args.redact)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as stream:
            stream.write(summary)
    elif args.format == "github":
        sys.stderr.write(summary)

    for warning in config.warnings:
        annotations.write(f"::warning::{warning}\n")
    for error in config.errors:
        annotations.write(
            f"::error::{descriptor_module.DESCRIPTOR_PATH} {error.render(redact=args.redact)}\n"
        )

    return 0 if config.valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
