#!/usr/bin/env python3
"""Render JaCoCo CSV reports as a compact GitHub Markdown summary."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Coverage:
    instruction_missed: int = 0
    instruction_covered: int = 0
    branch_missed: int = 0
    branch_covered: int = 0
    line_missed: int = 0
    line_covered: int = 0
    method_missed: int = 0
    method_covered: int = 0

    def add(self, other: Coverage) -> None:
        for field_name in self.__dataclass_fields__:
            setattr(self, field_name, getattr(self, field_name) + getattr(other, field_name))


def _read_coverage(path: Path) -> Coverage:
    coverage = Coverage()
    with path.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            coverage.instruction_missed += int(row["INSTRUCTION_MISSED"])
            coverage.instruction_covered += int(row["INSTRUCTION_COVERED"])
            coverage.branch_missed += int(row["BRANCH_MISSED"])
            coverage.branch_covered += int(row["BRANCH_COVERED"])
            coverage.line_missed += int(row["LINE_MISSED"])
            coverage.line_covered += int(row["LINE_COVERED"])
            coverage.method_missed += int(row["METHOD_MISSED"])
            coverage.method_covered += int(row["METHOD_COVERED"])
    return coverage


def _format_ratio(covered: int, missed: int) -> str:
    total = covered + missed
    if total == 0:
        return "n/a (0/0)"
    return f"{covered / total:.1%} ({covered:,}/{total:,})"


def _module_name(csv_path: Path, root: Path) -> str:
    module_path = csv_path.parents[3]
    try:
        relative = module_path.resolve().relative_to(root.resolve())
        name = relative.as_posix()
    except ValueError:
        name = module_path.as_posix()
    return name.replace("|", r"\|") or "."


def discover_reports(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("jacoco.csv")
        if path.parent.name == "jacoco"
        and path.parent.parent.name == "site"
        and path.parent.parent.parent.name == "target"
    )


def render_summary(root: Path) -> str:
    reports = discover_reports(root)
    lines = ["# Test Coverage Report", ""]
    if not reports:
        lines.extend(["No JaCoCo CSV reports were generated.", ""])
        return "\n".join(lines)

    module_coverage: dict[str, Coverage] = {}
    total = Coverage()
    for report in reports:
        name = _module_name(report, root)
        coverage = _read_coverage(report)
        module_coverage.setdefault(name, Coverage()).add(coverage)
        total.add(coverage)

    lines.extend(
        [
            "| Module | Lines | Branches | Instructions | Methods |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for name, coverage in sorted(module_coverage.items()):
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{name}`",
                    _format_ratio(coverage.line_covered, coverage.line_missed),
                    _format_ratio(coverage.branch_covered, coverage.branch_missed),
                    _format_ratio(
                        coverage.instruction_covered, coverage.instruction_missed
                    ),
                    _format_ratio(coverage.method_covered, coverage.method_missed),
                ]
            )
            + " |"
        )
    lines.append(
        "| "
        + " | ".join(
            [
                "**Total**",
                _format_ratio(total.line_covered, total.line_missed),
                _format_ratio(total.branch_covered, total.branch_missed),
                _format_ratio(total.instruction_covered, total.instruction_missed),
                _format_ratio(total.method_covered, total.method_missed),
            ]
        )
        + " |"
    )
    lines.extend(["", f"_Generated from {len(reports)} JaCoCo CSV report(s)._", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    print(render_summary(args.root), end="")


if __name__ == "__main__":
    main()
