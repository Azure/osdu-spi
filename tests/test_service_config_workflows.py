"""Regression tests for the descriptor-aware workflow contract (ADR-039).

These exercise the copied workflows' own logic: the changed-path filters are
extracted from the workflow YAML and evaluated, so a filter that stops treating
`.spi/**` as build-relevant fails here rather than silently green-lighting a
descriptor-only pull request.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
VALIDATE = ROOT / ".github" / "template-workflows" / "validate.yml"
BUILD = ROOT / ".github" / "template-workflows" / "build.yml"
CODEQL = ROOT / ".github" / "template-workflows" / "codeql.yml"
SETTINGS_APPLY = ROOT / ".github" / "template-workflows" / "settings-apply.yml"
INIT_COMPLETE = ROOT / ".github" / "workflows" / "init-complete.yml"
DEV_CI = ROOT / ".github" / "workflows" / "dev-ci.yml"
SYNC_CONFIG = ROOT / ".github" / "sync-config.json"
SCHEMA = ROOT / ".github" / "scripts" / "service-config" / "schema.json"
CHECK_VARIABLES = ROOT / ".github" / "scripts" / "settings-apply" / "check-required-variables.sh"
DEPLOY_FORK_RESOURCES = (
    ROOT / ".github" / "local-actions" / "init-helpers" / "deploy-fork-resources.sh"
)

REQUIRED_CHECK_CONTEXT = 'name: "🐳 Docker Build"'


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _posix_path(path: Path) -> str:
    """Return a path the local bash can open (handles WSL bash on Windows)."""

    text = str(path)
    if os.name == "nt" and len(text) > 2 and text[1] == ":":
        return "/mnt/" + text[0].lower() + text[2:].replace("\\", "/")
    return text


def _bash_available() -> bool:
    if shutil.which("bash") is None:
        return False
    try:
        probe = subprocess.run(["bash", "-c", "exit 0"], capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return False
    return probe.returncode == 0


BASH_READY = _bash_available()


def _job_block(workflow_text: str, job_id: str) -> str:
    """Return the YAML block of one job, so assertions cannot leak across jobs."""

    lines = workflow_text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.startswith(f"  {job_id}:"):
            start = index
            break
    if start is None:
        raise AssertionError(f"job '{job_id}' not found")
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.startswith("  ") and not line.startswith("   ") and line.strip().endswith(":"):
            return "\n".join(lines[start:index])
    return "\n".join(lines[start:])


def _step_script(workflow: Path, job_id: str, step_name: str) -> str:
    """Extract a step's `run:` body verbatim so it can be executed for real."""

    block = _job_block(_read(workflow), job_id)
    marker = f'- name: "{step_name}"'
    if marker not in block:
        raise AssertionError(f"step '{step_name}' not found in job '{job_id}'")
    after = block.split(marker, 1)[1]
    body = after.split("run: |", 1)[1]
    collected: list[str] = []
    for line in body.splitlines()[1:]:
        if line.strip() and not line.startswith(" " * 10):
            break
        collected.append(line[10:] if len(line) > 10 else "")
    script = "\n".join(collected)
    if "${{" in script:
        raise AssertionError(f"step '{step_name}' interpolates an expression; cannot execute it")
    return script + "\n"


def _build_relevant(workflow_text: str, changed_file: str) -> bool:
    """Replay the workflow's own changed-path filter for a single file."""

    always_relevant = re.search(r'case "\$file" in ([^)]+)\)', workflow_text)
    ignore_pattern = re.search(r"grep -qE '([^']+)'", workflow_text)
    if not always_relevant or not ignore_pattern:
        raise AssertionError("changed-path filter not found in workflow")

    for glob in always_relevant.group(1).split("|"):
        if fnmatch.fnmatchcase(changed_file, glob.strip()):
            return True
    return not re.search(ignore_pattern.group(1), changed_file)


class ChangedPathFilterTests(unittest.TestCase):
    def test_descriptor_only_changes_run_the_required_validation(self):
        for workflow in (VALIDATE, CODEQL):
            with self.subTest(workflow=workflow.name):
                text = _read(workflow)
                self.assertTrue(_build_relevant(text, ".spi/service.yaml"))
                self.assertTrue(_build_relevant(text, ".spi/nested/extra.yaml"))

    def test_configuration_and_documentation_changes_still_skip(self):
        for workflow in (VALIDATE, CODEQL):
            with self.subTest(workflow=workflow.name):
                text = _read(workflow)
                self.assertFalse(_build_relevant(text, ".github/workflows/validate.yml"))
                self.assertFalse(_build_relevant(text, "README.md"))
                self.assertFalse(_build_relevant(text, ".gitignore"))

    def test_source_and_maven_settings_changes_remain_build_relevant(self):
        text = _read(VALIDATE)

        self.assertTrue(_build_relevant(text, "provider/partition-azure/src/main/java/App.java"))
        self.assertTrue(_build_relevant(text, ".mvn/community-maven.settings.xml"))

    def test_build_workflow_does_not_ignore_the_descriptor_path(self):
        paths_ignore = re.findall(r"paths-ignore:(.*?)(?=\n  [a-z]|\njobs:)", _read(BUILD), re.DOTALL)

        self.assertTrue(paths_ignore)
        for block in paths_ignore:
            self.assertNotIn(".spi", block)


class ServiceConfigPreludeTests(unittest.TestCase):
    def test_validate_publishes_the_fixed_output_contract(self):
        text = _read(VALIDATE)

        self.assertIn("read-service-config:", text)
        for output in (
            "descriptor_present:",
            "schema_version:",
            "archetype:",
            "service_name:",
            "dockerfile_profile:",
            "unit_test_type:",
            "has_coverage:",
            "build_lane:",
            "lane_implemented:",
            "fallback:",
        ):
            self.assertIn(output, text)
        self.assertIn("read_service_config.py", text)

    def test_language_neutral_selection_drives_the_java_lane(self):
        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                text = _read(workflow)
                self.assertIn("needs.read-service-config.outputs.build_lane == 'java'", text)
                self.assertNotIn("needs.check-repo-state.outputs.is_java_repo == 'true' &&", text)

    def test_existing_java_behaviour_is_preserved(self):
        text = _read(VALIDATE)
        build_text = _read(BUILD)
        profile_expression = "${{ vars.MAVEN_PROFILE || 'core,azure' }}"

        self.assertIn('name: "🔨 Java Build"', text)
        self.assertIn("uses: ./.github/actions/java-build", text)
        self.assertIn(f"maven_profile: {profile_expression}", text)
        self.assertIn(f"maven_profile: {profile_expression}", build_text)

    def test_required_docker_build_context_is_unchanged(self):
        text = _read(VALIDATE)

        self.assertIn(REQUIRED_CHECK_CONTEXT, text)
        self.assertIn('name: "🐳 Docker Build (validate)"', text)

    def test_required_check_fails_closed_for_a_present_but_unsupported_archetype(self):
        text = _read(VALIDATE)
        summary = text.split("docker-build-required:", 1)[1]

        self.assertIn("needs.read-service-config.outputs.descriptor_present }}\" = \"true\"", summary)
        self.assertIn("needs.read-service-config.outputs.lane_implemented }}\" != \"true\"", summary)
        self.assertIn("has no build lane in this template version", summary)
        self.assertIn('needs.read-service-config.result }}" = "failure"', summary)

    def test_absent_descriptor_still_passes_the_required_check_for_non_java_repositories(self):
        summary = _read(VALIDATE).split("docker-build-required:", 1)[1]

        self.assertIn('needs.read-service-config.outputs.build_lane }}" = "none"', summary)
        self.assertIn("no build lane selected", summary)

    def test_pull_request_target_uses_the_trusted_main_descriptor(self):
        text = _read(VALIDATE)
        restore = text.split("Restore trusted service config", 1)[1].split("- name:", 1)[0]

        self.assertIn("github.event_name == 'pull_request_target'", restore)
        self.assertIn("git fetch origin main --depth=1", restore)
        self.assertIn("git checkout origin/main -- .spi/", restore)
        self.assertIn("git checkout origin/main -- .github/scripts/service-config/", restore)

    def test_python_build_action_is_wired_into_both_workflows(self):
        self.assertTrue((ROOT / ".github" / "actions" / "python-build").exists())

        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                text = _read(workflow)
                self.assertIn("  python-build:", text)
                self.assertIn('name: "🐍 Python Build"', text)
                self.assertIn("uses: ./.github/actions/python-build", text)
                self.assertIn("needs.read-service-config.outputs.build_lane == 'python'", text)

    def test_python_lane_is_parameterised_by_descriptor_outputs(self):
        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                job = _job_block(_read(workflow), "python-build")
                # Safe default keeps a minimal descriptor (no runtimeVersion) working.
                self.assertIn(
                    "python_version: ${{ needs.read-service-config.outputs.python_runtime_version || '3.12' }}",
                    job,
                )
                self.assertIn(
                    "package_name: ${{ needs.read-service-config.outputs.python_import_package }}", job
                )
                self.assertIn(
                    "test_extras: ${{ needs.read-service-config.outputs.python_test_extras }}", job
                )
                self.assertIn(
                    "runtime_extras: ${{ needs.read-service-config.outputs.python_runtime_extras }}", job
                )
                # The action no longer checks out; the caller must, with full history.
                self.assertIn("fetch-depth: 0", job)
                self.assertIn("uses: actions/checkout@", job)

    def test_every_consumed_service_config_output_is_declared_by_the_prelude_job(self):
        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                text = _read(workflow)
                prelude = _job_block(text, "read-service-config")
                consumed = set(re.findall(r"needs\.read-service-config\.outputs\.([a-z_]+)", text))
                declared = set(
                    re.findall(
                        r"^\s{6}([a-z_]+):\s+\$\{\{\s+steps\.config\.outputs\.\1\s+\}\}$",
                        prelude,
                        re.MULTILINE,
                    )
                )
                self.assertEqual(set(), consumed - declared)

    def test_initialization_never_executes_the_pr_head_descriptor_parser(self):
        initialization = _job_block(_read(VALIDATE), "check-initialization")

        self.assertNotIn("read_service_config.py", initialization)

    def test_python_lane_restores_trusted_actions_for_sync_pull_requests(self):
        job = _job_block(_read(VALIDATE), "python-build")

        self.assertIn("Restore local actions for sync PRs", job)
        self.assertIn("git checkout origin/main -- .github/actions/", job)
        self.assertIn(
            "ref: ${{ github.event_name == 'pull_request_target' && github.event.pull_request.head.sha || github.sha }}",
            job,
        )

    def test_python_reports_are_published_by_the_action_not_the_workflow(self):
        action = _read(ROOT / ".github" / "actions" / "python-build" / "action.yml")

        for artifact in ("python-junit-reports", "python-coverage-reports", "build-artifacts"):
            self.assertIn(f"name: {artifact}", action)
        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                job = _job_block(_read(workflow), "python-build")
                self.assertNotIn("upload-artifact", job)

    def test_no_obsolete_python_integration_point_remains(self):
        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                self.assertNotIn("INTEGRATION POINT", _read(workflow))

    def test_python_archetype_lane_is_marked_implemented(self):
        schema = json.loads(_read(SCHEMA))

        self.assertTrue(schema["archetypes"]["python-uv-fastapi"]["laneImplemented"])
        self.assertTrue(schema["archetypes"]["java-maven-azure"]["laneImplemented"])


class DockerLaneSelectionTests(unittest.TestCase):
    def test_docker_jobs_select_the_image_profile_from_the_descriptor(self):
        text = _read(VALIDATE)

        for job in ("docker-build", "docker-push"):
            with self.subTest(job=job):
                block = _job_block(text, job)
                self.assertIn(
                    "build_mode: ${{ needs.read-service-config.outputs.build_lane == 'python' && 'source' || 'java-artifact' }}",
                    block,
                )
                self.assertIn(
                    "dockerfile_path: ${{ needs.read-service-config.outputs.build_lane == 'python' && 'build/python/Dockerfile' || 'build/Dockerfile' }}",
                    block,
                )
                self.assertIn(
                    "platforms: ${{ needs.read-service-config.outputs.build_lane == 'python' && 'linux/amd64' || '' }}",
                    block,
                )
                self.assertIn("app_module: ${{ needs.read-service-config.outputs.app_module }}", block)
                # Java behaviour is preserved: the conventional JAR path is still passed.
                self.assertIn("jar_file: ${{ vars.SERVICE_TARGET_JAR ||", block)

    def test_docker_jobs_run_for_either_lane_without_breaking_the_java_gate(self):
        text = _read(VALIDATE)

        for job in ("docker-build", "docker-push"):
            with self.subTest(job=job):
                block = _job_block(text, job)
                # A skipped sibling lane must not skip the image job, but a failed or
                # skipped selected lane still must.
                self.assertIn("!cancelled()", block)
                self.assertIn(
                    "needs.java-build.result == 'success' && needs.java-build.outputs.build_result == 'success'",
                    block,
                )
                self.assertIn(
                    "needs.python-build.result == 'success' && needs.python-build.outputs.build_result == 'success'",
                    block,
                )

    def test_docker_push_keeps_the_adr_036_trust_clause(self):
        block = _job_block(_read(VALIDATE), "docker-push")
        condition = block.split("if: |", 1)[1].split("runs-on:", 1)[0]

        self.assertIn("github.actor != 'dependabot[bot]'", condition)
        self.assertIn("github.event_name != 'pull_request_target'", condition)
        self.assertIn("github.event_name != 'workflow_dispatch'", condition)
        self.assertIn(
            "(github.event_name != 'pull_request' ||\n           github.event.pull_request.head.repo.full_name == github.repository)",
            condition,
        )
        self.assertIn("inputs.force_full_pipeline == true", condition)
        # Losing the docker-build gate would push an image the validate job rejected.
        # It must sit outside the trust disjunction so the force_full_pipeline arm — which
        # previously inherited GitHub's implicit success() — cannot push a failed build.
        self.assertIn("needs.docker-build.result == 'success'", condition)
        self.assertLess(
            condition.index("needs.docker-build.result == 'success'"),
            condition.index("inputs.force_full_pipeline == true"),
        )
        self.assertLess(
            condition.index("needs.java-build.outputs.build_result == 'success'"),
            condition.index("github.actor != 'dependabot[bot]'"),
        )

    def test_deploy_and_integration_tests_remain_java_only(self):
        text = _read(VALIDATE)

        for job in ("deploy", "integration-test"):
            with self.subTest(job=job):
                block = _job_block(text, job)
                self.assertIn("needs.read-service-config.outputs.build_lane == 'java'", block)
                self.assertIn("needs.java-build.outputs.build_result == 'success'", block)
                self.assertNotIn("python-build", block)
                # No status function: a skipped java-build keeps the deploy lane skipped.
                self.assertNotIn("!cancelled()", block)
                self.assertNotIn("always()", block)

    def test_required_summary_aggregates_the_python_lane(self):
        summary = _read(VALIDATE).split("docker-build-required:", 1)[1]

        self.assertIn("python-build", summary.split("steps:", 1)[0])
        self.assertIn('needs.python-build.result }}" = "failure"', summary)
        self.assertIn('needs.read-service-config.outputs.build_lane }}" = "python"', summary)
        self.assertIn('needs.python-build.result }}" != "success"', summary)
        self.assertIn('needs.docker-build.result }}" != "success"', summary)
        # The required context name may never change (ADR-030).
        self.assertIn(REQUIRED_CHECK_CONTEXT, _read(VALIDATE))

    def test_validation_report_covers_the_python_lane(self):
        block = _job_block(_read(VALIDATE), "code-validation")

        self.assertIn('needs.read-service-config.outputs.build_lane }}" == "python"', block)
        self.assertIn("Python Build Successful", block)
        self.assertIn("Python Build Failed", block)
        self.assertIn("Java Build Successful", block)


@unittest.skipUnless(BASH_READY, "bash is not available on this host")
class InitializationDetectionTests(unittest.TestCase):
    """A Python repository must never look uninitialized (and pass vacuously)."""

    REPOSITORIES = {
        "maven service": {"pom.xml": "<project/>"},
        "uv python service": {"pyproject.toml": "[project]\n", "uv.lock": "version = 1\n"},
        "descriptor only": {".spi/service.yaml": "schemaVersion: 1\n"},
        "java source tree": {"src/main/java/App.java": "class App {}\n"},
    }

    def _initialized(self, workflow: Path, files: dict) -> str:
        step = _step_script(workflow, "check-repo-state", "Check Repository Initialization")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, content in files.items():
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding="utf-8")
            output = root / "outputs.txt"
            output.write_text("", encoding="utf-8")
            script = (
                'cd "$1" || exit 3\n'
                'export GITHUB_OUTPUT="$2"\n'
                + step
            )
            result = subprocess.run(
                ["bash", "-s", _posix_path(root), _posix_path(output)],
                input=script.encode("utf-8"),
                capture_output=True,
                timeout=120,
            )
            self.assertEqual(0, result.returncode, result.stderr.decode())
            return output.read_text(encoding="utf-8").strip()

    def test_supported_service_shapes_are_recognised(self):
        for workflow in (VALIDATE, BUILD):
            for label, files in self.REPOSITORIES.items():
                with self.subTest(workflow=workflow.name, repository=label):
                    self.assertEqual("initialized=true", self._initialized(workflow, files))

    def test_an_empty_repository_is_still_uninitialized(self):
        for workflow in (VALIDATE, BUILD):
            with self.subTest(workflow=workflow.name):
                self.assertEqual(
                    "initialized=false", self._initialized(workflow, {"README.md": "#\n"})
                )

    def test_python_repository_reports_the_python_marker(self):
        step = _step_script(VALIDATE, "check-repo-state", "Check if Python Repository")

        self.assertIn("pyproject.toml", step)
        self.assertIn("uv.lock", step)

    def test_structural_initialization_check_accepts_python_and_the_descriptor(self):
        block = _job_block(_read(VALIDATE), "check-initialization")

        self.assertIn('[ -f ".spi/service.yaml" ]', block)
        self.assertIn('[ -f "pyproject.toml" ] && [ -f "uv.lock" ]', block)
        self.assertIn("SERVICE_SHAPE", block)
        # A present-but-invalid descriptor must still reach read-service-config.
        self.assertIn("invalid descriptor must reach read-service-config", block)


class SettingsAndOwnershipTests(unittest.TestCase):
    def test_settings_apply_validates_the_descriptor_through_the_existing_issue(self):
        script = _read(CHECK_VARIABLES)

        self.assertEqual(1, script.count("ISSUE_TITLE="))
        self.assertIn("service-config/read_service_config.py", script)
        self.assertIn('--root . --format json --redact', script)
        self.assertIn("generate_codeowners.py", script)
        self.assertIn("missing+=(\"service descriptor", script)
        self.assertIn("CODEOWNERS rule for", script)

    def test_settings_apply_never_echoes_descriptor_or_secret_values(self):
        script = _read(CHECK_VARIABLES)

        self.assertIn("--redact", script)
        self.assertIn("no descriptor, secret or variable value is reproduced here", script)

    def test_settings_apply_runs_when_the_descriptor_changes(self):
        text = _read(SETTINGS_APPLY)

        self.assertIn("'.spi/**'", text)
        self.assertIn("'.github/scripts/service-config/**'", text)

    def test_initialization_generates_the_descriptor_and_seeds_ownership(self):
        init_text = _read(INIT_COMPLETE)
        deploy_text = _read(DEPLOY_FORK_RESOURCES)

        self.assertIn("generate_descriptor.py", init_text)
        self.assertIn("SPI_ENGINEERING_OWNERS", init_text)
        self.assertIn("generate_codeowners.py", deploy_text)
        self.assertIn("SPI_ENGINEERING_OWNERS", deploy_text)

    def test_sync_configuration_keeps_the_descriptor_service_owned(self):
        config = json.loads(_read(SYNC_CONFIG))
        directories = [entry["path"] for entry in config["sync_rules"]["directories"]]
        files = [entry["path"] for entry in config["sync_rules"]["files"]]
        service_owned = [entry["path"] for entry in config["service_owned"]["paths"]]

        self.assertIn(".github/scripts/service-config", directories)
        self.assertIn(".spi", config["exclusions"])
        self.assertIn(".spi/service.yaml", service_owned)
        self.assertIn("CODEOWNERS", service_owned)
        for path in directories + files:
            self.assertFalse(path.startswith(".spi"), path)

    def test_codeowners_cleanup_rule_documents_the_reseeding(self):
        config = json.loads(_read(SYNC_CONFIG))
        reasons = {
            entry["path"]: entry["reason"] for entry in config["cleanup_rules"]["files"]
        }

        self.assertIn("CODEOWNERS", reasons)
        self.assertIn("re-seeded", reasons["CODEOWNERS"])

    def test_dev_ci_validates_the_service_config_assets(self):
        text = _read(DEV_CI)

        self.assertIn("python -m unittest discover -s tests -p 'test_*.py' -v", text)
        self.assertIn(".github/scripts/service-config/schema.json", text)


if __name__ == "__main__":
    unittest.main()
