from __future__ import annotations

import csv
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


def _load_module(name: str, relative_path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {relative_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


coverage = _load_module(
    "render_coverage_summary",
    ".github/actions/java-build/render_coverage_summary.py",
)
junit = _load_module(
    "summarize_junit",
    ".github/actions/integration-test/summarize_junit.py",
)


class CoverageSummaryTests(unittest.TestCase):
    def test_renders_module_and_total_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "provider" / "demo" / "target" / "site" / "jacoco"
            report.mkdir(parents=True)
            with (report / "jacoco.csv").open("w", encoding="utf-8", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(
                    [
                        "GROUP",
                        "PACKAGE",
                        "CLASS",
                        "INSTRUCTION_MISSED",
                        "INSTRUCTION_COVERED",
                        "BRANCH_MISSED",
                        "BRANCH_COVERED",
                        "LINE_MISSED",
                        "LINE_COVERED",
                        "COMPLEXITY_MISSED",
                        "COMPLEXITY_COVERED",
                        "METHOD_MISSED",
                        "METHOD_COVERED",
                    ]
                )
                writer.writerow(["g", "p", "C", 20, 80, 2, 8, 5, 15, 1, 3, 2, 6])

            summary = coverage.render_summary(root)

            self.assertIn("`provider/demo`", summary)
            self.assertIn("75.0% (15/20)", summary)
            self.assertIn("80.0% (8/10)", summary)
            self.assertIn("**Total**", summary)
            self.assertIn("Generated from 1 JaCoCo CSV report", summary)

    def test_reports_missing_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertIn(
                "No JaCoCo CSV reports were generated",
                coverage.render_summary(Path(directory)),
            )


class JunitSummaryTests(unittest.TestCase):
    def test_aggregates_surefire_and_failsafe_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            surefire = root / "a" / "target" / "surefire-reports"
            failsafe = root / "b" / "target" / "failsafe-reports"
            surefire.mkdir(parents=True)
            failsafe.mkdir(parents=True)
            (surefire / "TEST-one.xml").write_text(
                '<testsuite tests="3" failures="1" errors="0" skipped="1" time="2.5"/>',
                encoding="utf-8",
            )
            (failsafe / "TEST-two.xml").write_text(
                '<testsuites tests="2" failures="0" errors="1" time="1.25"/>',
                encoding="utf-8",
            )
            (failsafe / "broken.xml").write_text("<testsuite", encoding="utf-8")

            metrics = junit.collect_metrics(root)

            self.assertEqual(5, metrics.tests)
            self.assertEqual(1, metrics.failures)
            self.assertEqual(1, metrics.errors)
            self.assertEqual(1, metrics.skipped)
            self.assertEqual(3.75, metrics.duration_seconds)
            self.assertEqual(2, metrics.report_files)
            self.assertEqual(1, metrics.parse_errors)

    def test_formats_duration(self):
        self.assertEqual("12.3s", junit.format_duration(12.3))
        self.assertEqual("2m 5s", junit.format_duration(125))
        self.assertEqual("1h 1m 1s", junit.format_duration(3661))

    def test_uses_testsuites_aggregate_without_double_counting_children(self):
        with tempfile.TemporaryDirectory() as directory:
            report_dir = Path(directory) / "target" / "surefire-reports"
            report_dir.mkdir(parents=True)
            (report_dir / "TEST-aggregate.xml").write_text(
                """
                <testsuites tests="4" failures="1" errors="0" skipped="1" time="6">
                  <testsuite tests="4" failures="1" errors="0" skipped="1" time="6"/>
                </testsuites>
                """,
                encoding="utf-8",
            )
            (report_dir / "failsafe-summary.xml").write_text(
                "<failsafe-summary result='254'/>",
                encoding="utf-8",
            )

            metrics = junit.collect_metrics(Path(directory))

            self.assertEqual(4, metrics.tests)
            self.assertEqual(1, metrics.failures)
            self.assertEqual(1, metrics.skipped)
            self.assertEqual(1, metrics.report_files)


class WorkflowContractTests(unittest.TestCase):
    def test_template_sync_uses_conventional_pull_request_titles(self):
        workflow = (
            ROOT / ".github" / "template-workflows" / "sync-template.yml"
        ).read_text(encoding="utf-8")

        self.assertIn(
            'pr-title: "chore: sync template updates ${{ env.CURRENT_DATE }}"',
            workflow,
        )
        self.assertIn(
            '--title "chore: sync template updates $(date +%Y-%m-%d)"',
            workflow,
        )
        self.assertNotIn('pr-title: "Sync template updates', workflow)
        self.assertNotIn('--title "🔄 Sync template updates', workflow)

    def test_feature_build_honors_service_maven_profile(self):
        workflow = (
            ROOT / ".github" / "template-workflows" / "build.yml"
        ).read_text(encoding="utf-8")
        dependabot_workflow = (
            ROOT / ".github" / "template-workflows" / "dependabot-validation.yml"
        ).read_text(encoding="utf-8")

        profile_expression = "${{ vars.MAVEN_PROFILE || 'core,azure' }}"
        self.assertIn(f"maven_profile: {profile_expression}", workflow)
        self.assertIn(f"MAVEN_PROFILE: {profile_expression}", workflow)
        self.assertIn(f"maven_profile: {profile_expression}", dependabot_workflow)
        self.assertIn(
            'MAVEN_CLI_OPTS="$MAVEN_CLI_OPTS -P $MAVEN_PROFILE"',
            workflow,
        )

    def test_template_ci_runs_for_any_template_repository(self):
        workflow = (ROOT / ".github" / "workflows" / "dev-ci.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("if: github.event.repository.is_template == true", workflow)
        self.assertNotIn("github.repository == 'azure/osdu-spi'", workflow)

    def test_java_build_provides_repository_local_sis_data(self):
        action = (
            ROOT / ".github" / "actions" / "java-build" / "action.yml"
        ).read_text(encoding="utf-8")
        workflow = (
            ROOT / ".github" / "template-workflows" / "build.yml"
        ).read_text(encoding="utf-8")
        sis_data = "SIS_DATA: ${{ github.workspace }}/apachesis_setup/SIS_DATA"

        self.assertIn(sis_data, action)
        self.assertIn(sis_data, workflow)


if __name__ == "__main__":
    unittest.main()
