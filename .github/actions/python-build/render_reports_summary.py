#!/usr/bin/env python3
"""Render the Python build report summary (pytest JUnit + Cobertura coverage).

The Java lane scrapes JaCoCo CSV; the Python lane consumes the standard files
pytest already writes: one JUnit XML and one Cobertura XML per suite, kept in
distinct files so no suite overwrites another's results.

Report parsing never raises: a malformed or partial report is counted and
reported instead of failing the build a second time.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


JUNIT_SUBDIR = "junit"
COVERAGE_SUBDIR = "coverage"


@dataclass(frozen=True)
class SuiteResult:
    name: str
    tests: int
    failures: int
    errors: int
    skipped: int
    duration_seconds: float

    @property
    def passed(self) -> bool:
        return self.failures == 0 and self.errors == 0


@dataclass(frozen=True)
class CoverageResult:
    name: str
    lines_covered: int
    lines_valid: int
    branches_covered: int
    branches_valid: int


def _suite_name(path: Path, suffix: str) -> str:
    name = path.stem
    if name.endswith(suffix):
        name = name[: -len(suffix)]
    return name.replace("-", " ").replace("_", " ").strip() or path.stem


def _number(value: str | None, default: float = 0.0) -> float:
    try:
        return float(value) if value is not None else default
    except ValueError:
        return default


def collect_junit_results(reports_dir: Path) -> tuple[list[SuiteResult], int]:
    """Aggregate every ``*-junit.xml`` file below ``reports_dir/junit``."""

    results: list[SuiteResult] = []
    parse_errors = 0
    junit_dir = reports_dir / JUNIT_SUBDIR
    for report in sorted(junit_dir.glob("*.xml")):
        try:
            root = ElementTree.parse(report).getroot()
        except (ElementTree.ParseError, OSError):
            parse_errors += 1
            continue
        # pytest writes <testsuites> with aggregate attributes; older writers omit them
        # and only populate the child <testsuite> elements.
        if root.tag == "testsuites" and root.get("tests") is None:
            suites = list(root.findall("testsuite"))
        else:
            suites = [root]
        tests = failures = errors = skipped = 0
        duration = 0.0
        for suite in suites:
            tests += int(_number(suite.get("tests")))
            failures += int(_number(suite.get("failures")))
            errors += int(_number(suite.get("errors")))
            skipped += int(_number(suite.get("skipped")))
            duration += _number(suite.get("time"))
        results.append(
            SuiteResult(
                name=_suite_name(report, "-junit"),
                tests=tests,
                failures=failures,
                errors=errors,
                skipped=skipped,
                duration_seconds=round(duration, 2),
            )
        )
    return results, parse_errors


def collect_coverage_results(reports_dir: Path) -> tuple[list[CoverageResult], int]:
    """Aggregate every ``*-coverage.xml`` Cobertura file below ``reports_dir``."""

    results: list[CoverageResult] = []
    parse_errors = 0
    coverage_dir = reports_dir / COVERAGE_SUBDIR
    for report in sorted(coverage_dir.glob("*.xml")):
        try:
            root = ElementTree.parse(report).getroot()
        except (ElementTree.ParseError, OSError):
            parse_errors += 1
            continue
        results.append(
            CoverageResult(
                name=_suite_name(report, "-coverage"),
                lines_covered=int(_number(root.get("lines-covered"))),
                lines_valid=int(_number(root.get("lines-valid"))),
                branches_covered=int(_number(root.get("branches-covered"))),
                branches_valid=int(_number(root.get("branches-valid"))),
            )
        )
    return results, parse_errors


def format_duration(seconds: float) -> str:
    seconds = max(0.0, float(seconds))
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes, remainder = divmod(int(round(seconds)), 60)
    if minutes < 60:
        return f"{minutes}m {remainder}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes}m {remainder}s"


def _percentage(covered: int, valid: int) -> str:
    if valid <= 0:
        return "n/a"
    return f"{covered / valid * 100:.1f}% ({covered}/{valid})"


def render_summary(reports_dir: Path) -> str:
    """Render the markdown summary appended to the job step summary."""

    suites, junit_errors = collect_junit_results(reports_dir)
    coverage, coverage_errors = collect_coverage_results(reports_dir)

    lines: list[str] = ["### 🐍 Python Test Results", ""]
    if suites:
        lines += [
            "| Suite | Tests | Failures | Errors | Skipped | Duration |",
            "| --- | ---: | ---: | ---: | ---: | ---: |",
        ]
        totals = [0, 0, 0, 0]
        total_duration = 0.0
        for suite in suites:
            status = "" if suite.passed else " ❌"
            lines.append(
                f"| `{suite.name}`{status} | {suite.tests} | {suite.failures} | "
                f"{suite.errors} | {suite.skipped} | {format_duration(suite.duration_seconds)} |"
            )
            totals = [
                totals[0] + suite.tests,
                totals[1] + suite.failures,
                totals[2] + suite.errors,
                totals[3] + suite.skipped,
            ]
            total_duration += suite.duration_seconds
        lines.append(
            f"| **Total** | **{totals[0]}** | **{totals[1]}** | **{totals[2]}** | "
            f"**{totals[3]}** | **{format_duration(total_duration)}** |"
        )
    else:
        lines.append("No pytest JUnit reports were generated.")

    lines += ["", "### 🐍 Python Coverage", ""]
    if coverage:
        lines += [
            "| Suite | Lines | Branches |",
            "| --- | --- | --- |",
        ]
        for entry in coverage:
            lines.append(
                f"| `{entry.name}` | {_percentage(entry.lines_covered, entry.lines_valid)} "
                f"| {_percentage(entry.branches_covered, entry.branches_valid)} |"
            )
    else:
        lines.append("No Cobertura coverage reports were generated.")

    if junit_errors or coverage_errors:
        lines += [
            "",
            f"> ⚠️ Unreadable reports skipped: {junit_errors} JUnit, {coverage_errors} coverage.",
        ]

    return "\n".join(lines) + "\n"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reports-dir",
        default=".spi-build-reports",
        help="Directory containing junit/ and coverage/ report subdirectories",
    )
    args = parser.parse_args(argv)
    sys.stdout.write(render_summary(Path(args.reports_dir)))
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
