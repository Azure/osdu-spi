"""Behaviour tests for the Python build plan resolver and report renderer.

These tests describe what the python-build action promises callers: safe input
validation, convention-based detection, fail-closed behaviour on unknown values, and
per-suite reporting. They do not assert on internal implementation details.
"""

from __future__ import annotations

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


plan_module = _load_module(
    "resolve_build_plan",
    ".github/actions/python-build/resolve_build_plan.py",
)
reports_module = _load_module(
    "render_reports_summary",
    ".github/actions/python-build/render_reports_summary.py",
)

CONVENTIONAL_PYPROJECT = """
[project]
name = "osdu-wbddms-worker"
version = "0.3.0"
requires-python = ">=3.12"

[project.optional-dependencies]
dev = ["pytest", "ruff", "mypy"]
az = ["azure-identity"]
"""


def _write_repo(
    root: Path,
    pyproject: str = CONVENTIONAL_PYPROJECT,
    lockfile: bool = True,
    package: str = "wdmsworker",
    unit_tests: bool = True,
    service_tests: bool = True,
) -> Path:
    (root / "pyproject.toml").write_text(pyproject, encoding="utf-8")
    if lockfile:
        (root / "uv.lock").write_text("version = 1\n", encoding="utf-8")
    if package:
        package_dir = root / "src" / package
        package_dir.mkdir(parents=True)
        (package_dir / "__init__.py").write_text("", encoding="utf-8")
    if unit_tests:
        (root / "tests" / "unit").mkdir(parents=True)
    if service_tests:
        (root / "tests" / "service").mkdir(parents=True)
    return root


class ConventionDetectionTests(unittest.TestCase):
    def test_conventional_service_needs_no_explicit_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))

            plan = plan_module.resolve_plan({}, root)

            self.assertEqual("3.12", plan.python_version)
            self.assertEqual("", plan.uv_version)
            self.assertEqual(("src",), plan.source_paths)
            self.assertEqual("wdmsworker", plan.package_name)
            self.assertEqual("osdu-wbddms-worker", plan.distribution_name)
            self.assertEqual(("dev",), plan.test_extras)
            self.assertEqual(("az",), plan.runtime_extras)
            self.assertEqual(("wdmsworker",), plan.runtime_import_modules)
            self.assertTrue(plan.run_unit_tests)
            self.assertTrue(plan.run_service_in_process)
            self.assertTrue(plan.run_service_subprocess)
            self.assertEqual("--no-subprocess", plan.service_in_process_flag)
            self.assertEqual("wdmsworker", plan.coverage_target)
            self.assertFalse(plan.run_lock_export_drift)

    def test_missing_optional_suites_are_skipped_not_failed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory), service_tests=False)

            plan = plan_module.resolve_plan({}, root)

            self.assertTrue(plan.run_unit_tests)
            self.assertFalse(plan.run_service_in_process)
            self.assertFalse(plan.run_service_subprocess)
            self.assertTrue(
                any("service test" in warning for warning in plan.warnings),
                plan.warnings,
            )

    def test_undeclared_default_extras_are_not_installed(self):
        pyproject = """
[project]
name = "sample-service"
version = "1.0.0"
"""
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory), pyproject=pyproject, package="sample")

            plan = plan_module.resolve_plan({}, root)

            self.assertEqual((), plan.test_extras)
            self.assertEqual((), plan.runtime_extras)

    def test_coverage_falls_back_to_source_path_when_package_is_ambiguous(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            second = root / "src" / "other"
            second.mkdir(parents=True)
            (second / "__init__.py").write_text("", encoding="utf-8")

            plan = plan_module.resolve_plan({}, root)

            self.assertEqual("", plan.package_name)
            self.assertEqual("src", plan.coverage_target)
            self.assertEqual((), plan.runtime_import_modules)

    def test_source_path_falls_back_to_repository_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory), package="")

            plan = plan_module.resolve_plan({}, root)

            self.assertEqual((".",), plan.source_paths)
            self.assertEqual(".", plan.coverage_target)

    def test_lockfile_is_mandatory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory), lockfile=False)

            with self.assertRaises(plan_module.PlanError) as error:
                plan_module.resolve_plan({}, root)

            self.assertIn("uv.lock", str(error.exception))

    def test_pyproject_is_mandatory(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(plan_module.PlanError) as error:
                plan_module.resolve_plan({}, Path(directory))

            self.assertIn("pyproject.toml", str(error.exception))


class DisabledAndExplicitInputTests(unittest.TestCase):
    def test_none_disables_suites_and_extras(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))

            plan = plan_module.resolve_plan(
                {
                    "TEST_EXTRAS": "none",
                    "RUNTIME_EXTRAS": "none",
                    "UNIT_TEST_PATH": "none",
                    "SERVICE_TEST_MODES": "none",
                },
                root,
            )

            self.assertEqual((), plan.test_extras)
            self.assertEqual((), plan.runtime_extras)
            self.assertFalse(plan.run_unit_tests)
            self.assertFalse(plan.run_service_in_process)
            self.assertFalse(plan.run_service_subprocess)

    def test_single_service_mode_can_be_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))

            plan = plan_module.resolve_plan({"SERVICE_TEST_MODES": "subprocess"}, root)

            self.assertFalse(plan.run_service_in_process)
            self.assertTrue(plan.run_service_subprocess)

    def test_explicit_missing_test_path_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))

            with self.assertRaises(plan_module.PlanError) as error:
                plan_module.resolve_plan({"UNIT_TEST_PATH": "tests/absent"}, root)

            self.assertIn("tests/absent", str(error.exception))

    def test_explicit_paths_and_modules_are_honoured(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))

            plan = plan_module.resolve_plan(
                {
                    "PACKAGE_NAME": "wdmsworker",
                    "RUNTIME_IMPORT_MODULES": "wdmsworker,wdmsworker.provider.azure",
                    "GENERATE_COVERAGE": "true",
                    "PACKAGE_BUILD": "true",
                },
                root,
            )

            self.assertTrue(plan.generate_coverage)
            self.assertTrue(plan.package_build)
            self.assertEqual(
                ("wdmsworker", "wdmsworker.provider.azure"), plan.runtime_import_modules
            )


class InputValidationTests(unittest.TestCase):
    def _expect_error(self, inputs: dict[str, str], fragment: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            with self.assertRaises(plan_module.PlanError) as error:
                plan_module.resolve_plan(inputs, root)
            self.assertIn(fragment, str(error.exception))

    def test_rejects_malformed_python_version(self):
        self._expect_error({"PYTHON_VERSION": "3.12; rm -rf /"}, "python_version")

    def test_rejects_malformed_uv_version(self):
        self._expect_error({"UV_VERSION": "$(curl evil)"}, "uv_version")

    def test_rejects_parent_directory_traversal(self):
        self._expect_error({"SOURCE_PATHS": "../etc"}, "'..'")

    def test_rejects_absolute_paths(self):
        self._expect_error({"SOURCE_PATHS": "/etc"}, "source_paths")

    def test_rejects_command_substitution_in_paths(self):
        self._expect_error({"UNIT_TEST_PATH": "tests/$(whoami)"}, "unit_test_path")

    def test_rejects_undeclared_extra_and_lists_available_extras(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            with self.assertRaises(plan_module.PlanError) as error:
                plan_module.resolve_plan({"TEST_EXTRAS": "typo"}, root)

            message = str(error.exception)
            self.assertIn("typo", message)
            self.assertIn("az, dev", message)

    def test_rejects_unknown_service_mode(self):
        self._expect_error({"SERVICE_TEST_MODES": "docker"}, "service_test_modes")

    def test_rejects_pytest_flag_with_embedded_value(self):
        self._expect_error(
            {"SERVICE_IN_PROCESS_FLAG": "--base-url=http://evil"},
            "service_in_process_flag",
        )

    def test_rejects_unknown_tool_mode(self):
        self._expect_error({"LINT_MODE": "maybe"}, "lint_mode")

    def test_rejects_non_boolean_coverage_flag(self):
        self._expect_error({"GENERATE_COVERAGE": "sometimes"}, "generate_coverage")

    def test_rejects_module_name_that_is_not_an_identifier(self):
        self._expect_error({"RUNTIME_IMPORT_MODULES": "os;import shutil"}, "runtime_import")

    def test_rejects_non_shell_lock_regeneration_script(self):
        self._expect_error(
            {"LOCK_REGENERATION_SCRIPT": "scripts/regenerate.py"}, "lock_regeneration_script"
        )

    def test_rejects_missing_lock_regeneration_script(self):
        self._expect_error(
            {"LOCK_REGENERATION_SCRIPT": "scripts/absent.sh"}, "lock_regeneration_script"
        )


class LockDriftTests(unittest.TestCase):
    def test_export_drift_runs_only_when_the_repository_supplies_a_script(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "regenerate-requirements.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (root / "requirements.txt").write_text("", encoding="utf-8")

            without_script = plan_module.resolve_plan({}, root)
            with_script = plan_module.resolve_plan(
                {"LOCK_REGENERATION_SCRIPT": "scripts/regenerate-requirements.sh"}, root
            )

            self.assertFalse(without_script.run_lock_export_drift)
            self.assertTrue(with_script.run_lock_export_drift)
            self.assertEqual(
                ("uv.lock", "requirements.txt"), with_script.lock_drift_paths
            )


class PlanOutputTests(unittest.TestCase):
    def test_outputs_expose_the_stable_caller_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            plan = plan_module.resolve_plan({"GENERATE_COVERAGE": "true"}, root)

            outputs = dict(plan_module.plan_outputs(plan))

            for key in (
                "python_version",
                "uv_version",
                "test_extras",
                "runtime_extras",
                "run_unit_tests",
                "run_service_in_process",
                "run_service_subprocess",
                "generate_coverage",
                "run_lock_export_drift",
                "reports_dir",
                "coverage_target",
            ):
                self.assertIn(key, outputs)

            self.assertEqual(".spi-build-reports", outputs["reports_dir"])
            self.assertEqual("true", outputs["generate_coverage"])
            self.assertEqual("dev", outputs["test_extras"])

    def test_output_values_never_contain_newlines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            plan = plan_module.resolve_plan({}, root)

            for key, value in plan_module.plan_outputs(plan):
                self.assertNotIn("\n", value, key)

    def test_summary_reports_the_resolved_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            plan = plan_module.resolve_plan({}, root)

            summary = plan_module.render_plan_summary(plan)

            self.assertIn("Python Build Plan", summary)
            self.assertIn("`3.12`", summary)
            self.assertIn("wdmsworker", summary)
            self.assertIn("tests/unit", summary)


class DescriptorToActionContractTests(unittest.TestCase):
    """The generated descriptor must be directly usable as python-build inputs.

    This is the seam the workflows rely on: `read-service-config` outputs become
    action inputs verbatim. A pattern that the schema accepts but the plan resolver
    rejects (or vice versa) would only surface in a fork's first Python build.
    """

    def _generate_and_resolve(self, root: Path):
        descriptor_module = _load_module(
            "descriptor_for_plan", ".github/scripts/service-config/descriptor.py"
        )
        generator = _load_module(
            "generate_descriptor_for_plan",
            ".github/scripts/service-config/generate_descriptor.py",
        )
        archetype, _ = generator.detect_archetype(root)
        app_module, _ = generator.detect_app_module(root)
        target = root / ".spi"
        target.mkdir(parents=True, exist_ok=True)
        (target / "service.yaml").write_text(
            generator.render_descriptor(archetype, "wellbore-worker", root, app_module),
            encoding="utf-8",
        )
        return descriptor_module.resolve(root)

    def test_generated_descriptor_outputs_resolve_into_a_valid_build_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            (root / "src" / "wdmsworker" / "app.py").write_text(
                "from fastapi import FastAPI\n\napp = FastAPI()\n", encoding="utf-8"
            )

            config = self._generate_and_resolve(root)
            self.assertTrue(config.valid, [error.render() for error in config.errors])

            outputs = config.outputs()
            # Exactly what build.yml / validate.yml pass to the action.
            plan = plan_module.resolve_plan(
                {
                    "PYTHON_VERSION": outputs["python_runtime_version"] or "3.12",
                    "PACKAGE_NAME": outputs["python_import_package"],
                    "DISTRIBUTION_NAME": outputs["python_distribution"],
                    "TEST_EXTRAS": outputs["python_test_extras"],
                    "RUNTIME_EXTRAS": outputs["python_runtime_extras"],
                    "GENERATE_COVERAGE": outputs["has_coverage"],
                },
                root,
            )

            self.assertEqual("3.12", plan.python_version)
            self.assertEqual("wdmsworker", plan.package_name)
            self.assertEqual("osdu-wbddms-worker", plan.distribution_name)
            self.assertEqual(("dev",), plan.test_extras)
            self.assertEqual(("az",), plan.runtime_extras)
            self.assertTrue(plan.generate_coverage)
            self.assertEqual("wdmsworker.app:app", outputs["app_module"])

    def test_descriptor_app_module_matches_the_container_build_argument_pattern(self):
        with tempfile.TemporaryDirectory() as directory:
            root = _write_repo(Path(directory))
            (root / "src" / "wdmsworker" / "app.py").write_text("app = object()\n", encoding="utf-8")

            app_module = self._generate_and_resolve(root).outputs()["app_module"]

            # Same expression prepare-build-args.sh enforces before the --build-arg.
            self.assertRegex(
                app_module, r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*:[A-Za-z_][A-Za-z0-9_]*$"
            )


class ReportSummaryTests(unittest.TestCase):
    def _reports(self, root: Path) -> Path:
        (root / "junit").mkdir(parents=True)
        (root / "coverage").mkdir(parents=True)
        return root

    def test_each_suite_is_reported_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            reports = self._reports(Path(directory))
            (reports / "junit" / "unit-junit.xml").write_text(
                '<testsuites tests="10" failures="0" errors="0" skipped="1" time="4.5"/>',
                encoding="utf-8",
            )
            (reports / "junit" / "service-subprocess-junit.xml").write_text(
                '<testsuite tests="3" failures="1" errors="0" skipped="0" time="61"/>',
                encoding="utf-8",
            )

            suites, parse_errors = reports_module.collect_junit_results(reports)

            self.assertEqual(0, parse_errors)
            self.assertEqual(["service subprocess", "unit"], sorted(s.name for s in suites))
            summary = reports_module.render_summary(reports)
            self.assertIn("`unit`", summary)
            self.assertIn("`service subprocess` ❌", summary)
            self.assertIn("**13**", summary)
            self.assertIn("1m 6s", summary)

    def test_child_testsuites_are_not_double_counted(self):
        with tempfile.TemporaryDirectory() as directory:
            reports = self._reports(Path(directory))
            (reports / "junit" / "unit-junit.xml").write_text(
                """
                <testsuites tests="4" failures="0" errors="0" skipped="0" time="2">
                  <testsuite tests="4" failures="0" errors="0" skipped="0" time="2"/>
                </testsuites>
                """,
                encoding="utf-8",
            )

            suites, _ = reports_module.collect_junit_results(reports)

            self.assertEqual(1, len(suites))
            self.assertEqual(4, suites[0].tests)

    def test_coverage_percentages_are_rendered_per_suite(self):
        with tempfile.TemporaryDirectory() as directory:
            reports = self._reports(Path(directory))
            (reports / "coverage" / "unit-coverage.xml").write_text(
                '<coverage lines-valid="20" lines-covered="15" branches-valid="10" '
                'branches-covered="8"/>',
                encoding="utf-8",
            )
            (reports / "coverage" / "service-inprocess-coverage.xml").write_text(
                '<coverage lines-valid="0" lines-covered="0" branches-valid="0" '
                'branches-covered="0"/>',
                encoding="utf-8",
            )

            summary = reports_module.render_summary(reports)

            self.assertIn("75.0% (15/20)", summary)
            self.assertIn("80.0% (8/10)", summary)
            self.assertIn("n/a", summary)

    def test_unreadable_reports_are_counted_not_fatal(self):
        with tempfile.TemporaryDirectory() as directory:
            reports = self._reports(Path(directory))
            (reports / "junit" / "unit-junit.xml").write_text("<testsuite", encoding="utf-8")

            summary = reports_module.render_summary(reports)

            self.assertIn("Unreadable reports skipped: 1 JUnit", summary)

    def test_missing_reports_are_reported_clearly(self):
        with tempfile.TemporaryDirectory() as directory:
            summary = reports_module.render_summary(Path(directory))

            self.assertIn("No pytest JUnit reports were generated", summary)
            self.assertIn("No Cobertura coverage reports were generated", summary)


if __name__ == "__main__":
    unittest.main()
