#!/usr/bin/env python3
"""Decide one suite's verdict from its Surefire and Failsafe reports.

Usage: suite-verdict.py --exit-code N --reports DIR

Prints one line for the run summary and exits 0 for pass, 1 for fail. The
console is not consulted: -q hides the summary lines and
-Dmaven.test.failure.ignore turns a failing suite into a zero exit, so only
the report XML says what ran. A pass needs a zero exit, at least one test
that was not skipped, and no failures or errors.
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ET

REPORT_DIRS = ("surefire-reports", "failsafe-reports")


def count(reports):
    totals = {"tests": 0, "skipped": 0, "failures": 0, "errors": 0}
    files = [p for p in pathlib.Path(reports).rglob("TEST-*.xml")
             if p.parent.name in REPORT_DIRS]
    for path in files:
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            return None, f"unreadable report {path.name}"
        for key in totals:
            totals[key] += int(root.get(key, 0))
    return totals, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exit-code", type=int, required=True)
    parser.add_argument("--reports", required=True)
    args = parser.parse_args()

    totals, problem = count(args.reports)
    if problem:
        print(f"FAIL: {problem}")
        return 1
    ran = totals["tests"] - totals["skipped"]
    broken = totals["failures"] + totals["errors"]
    if args.exit_code == 124:
        print(f"FAIL: timed out after {ran} tests")
        return 1
    if args.exit_code != 0:
        print(f"FAIL: exit {args.exit_code}, {ran} tests ran, {broken} failed or errored")
        return 1
    if broken:
        print(f"FAIL: {broken} of {ran} tests failed or errored despite a zero exit")
        return 1
    if ran == 0:
        print(f"FAIL: no tests executed ({totals['skipped']} skipped)")
        return 1
    print(f"pass: {ran} tests, {totals['skipped']} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
