#!/usr/bin/env python3
"""Aggregate Surefire and Failsafe XML reports for GitHub Actions outputs."""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


@dataclass
class TestMetrics:
    tests: int = 0
    failures: int = 0
    errors: int = 0
    skipped: int = 0
    duration_seconds: float = 0.0
    report_files: int = 0
    parse_errors: int = 0

    def add(self, other: TestMetrics) -> None:
        self.tests += other.tests
        self.failures += other.failures
        self.errors += other.errors
        self.skipped += other.skipped
        self.duration_seconds += other.duration_seconds
        self.report_files += other.report_files
        self.parse_errors += other.parse_errors


def _tag(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _attribute_metrics(element: ET.Element) -> TestMetrics:
    return TestMetrics(
        tests=int(element.attrib.get("tests", 0)),
        failures=int(element.attrib.get("failures", 0)),
        errors=int(element.attrib.get("errors", 0)),
        skipped=int(element.attrib.get("skipped", 0))
        + int(element.attrib.get("disabled", 0)),
        duration_seconds=float(element.attrib.get("time", 0) or 0),
    )


def _parse_report(path: Path) -> TestMetrics:
    root = ET.parse(path).getroot()
    if _tag(root) == "testsuite":
        metrics = _attribute_metrics(root)
    elif _tag(root) == "testsuites" and "tests" in root.attrib:
        metrics = _attribute_metrics(root)
    elif _tag(root) == "testsuites":
        metrics = TestMetrics()
        for child in root:
            if _tag(child) == "testsuite":
                metrics.add(_attribute_metrics(child))
    else:
        return TestMetrics()
    metrics.report_files = 1
    return metrics


def discover_reports(test_dir: Path) -> list[Path]:
    reports: set[Path] = set()
    for report_dir in ("surefire-reports", "failsafe-reports"):
        reports.update(
            path.resolve()
            for path in test_dir.rglob(f"target/{report_dir}/*.xml")
            if path.is_file()
        )
    return sorted(reports)


def collect_metrics(test_dir: Path) -> TestMetrics:
    total = TestMetrics()
    for report in discover_reports(test_dir):
        try:
            total.add(_parse_report(report))
        except (ET.ParseError, OSError, TypeError, ValueError):
            total.parse_errors += 1
    return total


def format_duration(seconds: float) -> str:
    rounded = int(round(seconds))
    hours, remainder = divmod(rounded, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{seconds:.1f}s"


def write_github_output(path: Path, metrics: TestMetrics) -> None:
    values = {
        "tests": metrics.tests,
        "failures": metrics.failures,
        "errors": metrics.errors,
        "skipped": metrics.skipped,
        "duration_seconds": f"{metrics.duration_seconds:.3f}",
        "duration_display": format_duration(metrics.duration_seconds),
        "report_files": metrics.report_files,
        "parse_errors": metrics.parse_errors,
    }
    with path.open("a", encoding="utf-8") as stream:
        for key, value in values.items():
            stream.write(f"{key}={value}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-dir", type=Path, required=True)
    parser.add_argument("--github-output", type=Path, required=True)
    args = parser.parse_args()
    write_github_output(args.github_output, collect_metrics(args.test_dir))


if __name__ == "__main__":
    main()
