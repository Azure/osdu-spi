"""Contract tests for the template-owned Python build assets.

They cover what a fork depends on and what a reviewer cannot easily see by reading a
diff: pinned action/base-image references, the credential handling rules, the stable
output/artifact contract, entrypoint validation behaviour, and the language-aware fork
resources that must keep working for existing Java forks.
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
ACTION_DIR = ROOT / ".github" / "actions" / "python-build"
ACTION_YML = ACTION_DIR / "action.yml"
DOCKERFILE = ROOT / "build" / "python" / "Dockerfile"
ENTRYPOINT = ROOT / "build" / "python" / "docker-entrypoint.sh"
FORK_RESOURCES = ROOT / ".github" / "fork-resources"
SELECTOR = FORK_RESOURCES / "select-dependabot-config.sh"

SHA_PIN = re.compile(r"uses:\s*\S+@[0-9a-f]{40}\b")
USES_LINE = re.compile(r"^\s*(-\s*)?uses:\s*(\S+)\s*(#.*)?$")

HAS_YAML = importlib.util.find_spec("yaml") is not None


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _posix_path(path: Path) -> str:
    """Return a path the local bash can open (handles WSL bash on Windows)."""

    text = str(path)
    if os.name == "nt" and len(text) > 2 and text[1] == ":":
        drive = text[0].lower()
        return "/mnt/" + drive + text[2:].replace("\\", "/")
    return text


def _bash_can_run(path: Path) -> bool:
    if os.name == "nt":
        # Windows hosts run bash through an interop layer with a different filesystem
        # view; these scripts are exercised on the Linux runner instead.
        return False
    if shutil.which("bash") is None:
        return False
    if b"\r\n" in path.read_bytes():
        # A CRLF checkout cannot be executed by a POSIX shell.
        return False
    try:
        probe = subprocess.run(
            ["bash", "-c", f"test -f '{_posix_path(path)}'"],
            capture_output=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return probe.returncode == 0


BASH_READY = _bash_can_run(ENTRYPOINT)


def _run_bash(args: list[str], env: dict[str, str] | None = None, cwd: Path | None = None):
    environment = dict(os.environ)
    if env:
        environment.update(env)
    return subprocess.run(
        ["bash", *args],
        capture_output=True,
        text=True,
        env=environment,
        cwd=str(cwd) if cwd else None,
        timeout=120,
    )


class ActionContractTests(unittest.TestCase):
    def setUp(self):
        self.action = _read(ACTION_YML)

    def test_every_referenced_action_is_pinned_to_a_commit_sha(self):
        for line in self.action.splitlines():
            match = USES_LINE.match(line)
            if not match:
                continue
            self.assertRegex(line.strip(), SHA_PIN, f"unpinned action reference: {line.strip()}")

    def test_directly_invoked_scripts_are_executable(self):
        """The action runs these scripts directly, so the tracked mode must be 0755."""

        if shutil.which("git") is None:
            self.skipTest("git is not available")

        scripts = [
            ".github/actions/python-build/detect-project.sh",
            ".github/actions/python-build/validate-runtime-inputs.sh",
            ".github/actions/python-build/run-build.sh",
        ]
        result = subprocess.run(
            ["git", "ls-files", "--stage", *scripts],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=120,
        )
        if result.returncode != 0 or not result.stdout.strip():
            self.skipTest(f"git index is unavailable here: {result.stderr.strip()}")
        for line in result.stdout.strip().splitlines():
            mode, _, rest = line.partition(" ")
            self.assertEqual("100755", mode, f"{rest.strip()} must be executable")

    def test_official_python_and_uv_setup_actions_are_used(self):
        self.assertIn("actions/setup-python@", self.action)
        self.assertIn("astral-sh/setup-uv@", self.action)

    def test_build_result_output_is_stable_for_callers(self):
        self.assertIn("value: ${{ steps.build.outcome }}", self.action)
        self.assertIn("value: ${{ steps.detect.outputs.has_python_project }}", self.action)
        self.assertIn("value: build-artifacts", self.action)

    def test_reports_are_uploaded_as_distinct_artifacts(self):
        self.assertIn("name: build-artifacts", self.action)
        self.assertIn("name: python-junit-reports", self.action)
        self.assertIn("name: python-coverage-reports", self.action)

    def test_locked_dependency_installs_are_used(self):
        phases = _read(ACTION_DIR / "phases" / "sync-test-env.sh")
        runtime = _read(ACTION_DIR / "phases" / "runtime-extras.sh")
        drift = _read(ACTION_DIR / "phases" / "lock-drift.sh")

        self.assertIn("uv sync --locked", phases)
        self.assertIn("uv sync --locked --no-dev", runtime)
        self.assertIn("uv lock --locked", drift)

    def test_export_drift_requires_a_repository_supplied_script(self):
        drift = _read(ACTION_DIR / "phases" / "lock-drift.sh")

        self.assertIn('spi_enabled "${RUN_LOCK_EXPORT_DRIFT:-false}"', drift)
        self.assertIn("git diff --exit-code", drift)

    def test_suites_write_distinct_report_files(self):
        tests_phase = _read(ACTION_DIR / "phases" / "tests.sh")

        for report in (
            "unit-junit.xml",
            "unit-coverage.xml",
            "service-inprocess-junit.xml",
            "service-inprocess-coverage.xml",
            "service-subprocess-junit.xml",
        ):
            self.assertIn(report, tests_phase)

    def test_action_scripts_never_evaluate_caller_input(self):
        for script in sorted(ACTION_DIR.rglob("*.sh")):
            code = [
                line
                for line in _read(script).splitlines()
                if not line.lstrip().startswith("#")
            ]
            content = "\n".join(code)
            self.assertNotIn("eval ", content, f"{script.name} uses eval")
            self.assertNotIn("${{", content, f"{script.name} interpolates a workflow expression")

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_no_workflow_expression_reaches_a_run_body(self):
        import yaml

        action = yaml.safe_load(self.action)
        for step in action["runs"]["steps"]:
            body = step.get("run")
            if body is None:
                continue
            self.assertNotIn(
                "${{",
                body,
                f"step '{step.get('name')}' interpolates an expression into its script",
            )

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_inputs_are_documented_with_safe_defaults(self):
        import yaml

        action = yaml.safe_load(self.action)
        inputs = action["inputs"]

        for name in (
            "python_version",
            "uv_version",
            "package_name",
            "distribution_name",
            "test_extras",
            "runtime_extras",
            "unit_test_path",
            "service_test_path",
            "service_test_modes",
            "generate_coverage",
            "lock_regeneration_script",
            "index_token",
        ):
            self.assertIn(name, inputs)
            self.assertIn("description", inputs[name])

        self.assertEqual("3.12", inputs["python_version"]["default"])
        self.assertEqual("false", inputs["generate_coverage"]["default"])
        self.assertEqual("in-process,subprocess", inputs["service_test_modes"]["default"])
        self.assertEqual("", inputs["lock_regeneration_script"]["default"])

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_the_caller_owns_the_checkout(self):
        """java-build has no internal checkout; the Python lane must match it.

        A composite action that checks out itself would silently re-fetch the default
        ref and undo a caller's trusted `pull_request_target` restore.
        """

        import yaml

        for step in yaml.safe_load(self.action)["runs"]["steps"]:
            self.assertNotIn("actions/checkout", str(step.get("uses", "")))
        self.assertIn("The caller owns the checkout", self.action)

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_uv_version_default_is_pinned_to_the_canonical_image(self):
        """CI must resolve the lockfile with the uv the image installs it with."""

        import yaml

        default = yaml.safe_load(self.action)["inputs"]["uv_version"]["default"]
        image = re.search(
            r"ghcr\.io/astral-sh/uv:(\d+\.\d+\.\d+)@sha256:[0-9a-f]{64}", _read(DOCKERFILE)
        )

        self.assertIsNotNone(image, "the canonical image must pin uv by version and digest")
        self.assertEqual(image.group(1), str(default))
        self.assertNotIn(default, ("", "latest", "latest-known"))


class DockerfileContractTests(unittest.TestCase):
    def setUp(self):
        self.dockerfile = _read(DOCKERFILE)

    def test_all_images_are_digest_pinned(self):
        from_lines = [
            line for line in self.dockerfile.splitlines() if line.strip().startswith("FROM ")
        ]
        self.assertGreaterEqual(len(from_lines), 3)
        for line in from_lines:
            self.assertRegex(line, r"@sha256:[0-9a-f]{64}", f"unpinned base image: {line}")

        self.assertRegex(
            self.dockerfile.splitlines()[0], r"^# syntax=docker/dockerfile:\S+@sha256:[0-9a-f]{64}$"
        )

    def test_uses_the_multiarch_azure_linux_python_312_base(self):
        base = (
            "mcr.microsoft.com/azurelinux/base/python:3.12@sha256:"
            "722b6224c23b3f21f5268e2073f80c0f396bc626e3193b6dbf66e40d89478f03"
        )
        self.assertEqual(2, self.dockerfile.count(base), "builder and runtime must share the base")

        from_lines = [
            line for line in self.dockerfile.splitlines() if line.strip().startswith("FROM ")
        ]
        for line in from_lines:
            self.assertNotIn("python:3.13", line, "MCR publishes no Azure Linux 3.13 base image")

    def test_installs_from_the_lockfile_without_editable_mode(self):
        self.assertIn("uv sync --frozen --no-dev --no-install-project", self.dockerfile)
        self.assertIn("uv sync --frozen --no-dev --no-editable", self.dockerfile)
        self.assertNotIn("pip install", self.dockerfile)

    def test_index_credentials_use_a_buildkit_secret_only(self):
        self.assertIn("--mount=type=secret,id=netrc", self.dockerfile)
        self.assertNotIn("ARG PIP_INDEX_URL", self.dockerfile)
        self.assertNotIn("ARG PIP_EXTRA_INDEX_URL", self.dockerfile)
        self.assertNotIn("ENV PIP_INDEX_URL", self.dockerfile)
        self.assertNotIn("ENV UV_INDEX_URL", self.dockerfile)

    def test_runtime_extras_build_arg_is_validated_in_the_build(self):
        self.assertIn('ARG RUNTIME_EXTRAS=""', self.dockerfile)
        self.assertIn("*[!A-Za-z0-9._-]*", self.dockerfile)

    def test_image_runs_as_uid_1000(self):
        self.assertIn("COPY --from=builder --chown=1000:1000 /app/.venv /app/.venv", self.dockerfile)
        self.assertIn("USER 1000:1000", self.dockerfile)

    def test_entrypoint_is_baked_into_the_image(self):
        self.assertIn("COPY --chmod=0755 build/python/docker-entrypoint.sh", self.dockerfile)
        self.assertIn('ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]', self.dockerfile)
        self.assertIn('ARG APP_MODULE=""', self.dockerfile)
        self.assertIn('SPI_APP_MODULE="${APP_MODULE}"', self.dockerfile)

    def test_oci_labels_are_declared(self):
        for label in (
            "org.opencontainers.image.source",
            "org.opencontainers.image.revision",
            "org.opencontainers.image.version",
            "org.opencontainers.image.base.digest",
        ):
            self.assertIn(label, self.dockerfile)

    def test_stage_structure_is_explicit(self):
        self.assertIn("AS uv", self.dockerfile)
        self.assertIn("AS builder", self.dockerfile)
        self.assertIn("AS runtime", self.dockerfile)

    def test_instructions_and_stage_references_are_structurally_valid(self):
        """Structural parse stands in for a daemon-backed build smoke test."""

        known = {
            "FROM",
            "ARG",
            "ENV",
            "RUN",
            "COPY",
            "ADD",
            "WORKDIR",
            "USER",
            "EXPOSE",
            "LABEL",
            "ENTRYPOINT",
            "CMD",
            "HEALTHCHECK",
            "VOLUME",
            "SHELL",
            "STOPSIGNAL",
            "ONBUILD",
        }

        instructions: list[str] = []
        continuation = False
        for raw in self.dockerfile.splitlines():
            line = raw.rstrip()
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not continuation:
                instructions.append(line.strip())
            continuation = line.endswith("\\")

        stages = {"scratch"}
        for instruction in instructions:
            keyword = instruction.split(maxsplit=1)[0].upper()
            self.assertIn(keyword, known, f"unknown Dockerfile instruction: {instruction}")
            if keyword == "FROM":
                parts = instruction.split()
                if len(parts) >= 4 and parts[2].upper() == "AS":
                    stages.add(parts[3])

        for reference in re.findall(r"--from=([A-Za-z0-9_.-]+)", self.dockerfile):
            self.assertIn(reference, stages, f"COPY --from references unknown stage: {reference}")


@unittest.skipUnless(BASH_READY, "bash cannot execute repository scripts on this host")
class ShellSyntaxTests(unittest.TestCase):
    def test_all_python_build_scripts_parse(self):
        scripts = sorted(ACTION_DIR.rglob("*.sh")) + [SELECTOR]
        self.assertTrue(scripts)
        for script in scripts:
            result = _run_bash(["-n", _posix_path(script)])
            self.assertEqual(0, result.returncode, f"{script.name}: {result.stderr}")

    def test_container_entrypoint_is_posix_compatible(self):
        result = subprocess.run(
            ["bash", "--posix", "-n", _posix_path(ENTRYPOINT)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(0, result.returncode, result.stderr)


@unittest.skipUnless(BASH_READY, "bash cannot execute repository scripts on this host")
class EntrypointBehaviourTests(unittest.TestCase):
    def _run(self, args: list[str], env: dict[str, str] | None = None):
        return _run_bash([_posix_path(ENTRYPOINT), *args], env=env)

    def test_missing_application_module_fails_with_actionable_message(self):
        result = self._run([])

        self.assertNotEqual(0, result.returncode)
        self.assertIn("SPI_APP_MODULE", result.stderr)

    def test_invalid_application_module_is_rejected(self):
        result = self._run([], env={"SPI_APP_MODULE": "app.main:app; rm -rf /"})

        self.assertNotEqual(0, result.returncode)
        self.assertIn("invalid SPI_APP_MODULE", result.stderr)

    def test_invalid_port_and_log_level_are_rejected(self):
        port = self._run([], env={"SPI_APP_MODULE": "app.main:app", "SPI_APP_PORT": "80a"})
        level = self._run(
            [], env={"SPI_APP_MODULE": "app.main:app", "SPI_UVICORN_LOG_LEVEL": "verbose"}
        )

        self.assertIn("invalid SPI_APP_PORT", port.stderr)
        self.assertIn("invalid SPI_UVICORN_LOG_LEVEL", level.stderr)

    def test_valid_configuration_passes_validation_and_execs_uvicorn(self):
        result = self._run(
            [],
            env={
                "SPI_APP_MODULE": "wdmsworker.app:app",
                "SPI_APP_PORT": "8080",
                "SPI_UVICORN_ROOT_PATH": "/api/wdms-worker",
            },
        )

        # uvicorn is absent on the test host, so the exec fails - but validation passed.
        self.assertNotIn("spi-entrypoint:", result.stderr)

    def test_healthcheck_is_a_no_op_without_a_configured_path(self):
        result = self._run(["healthcheck"])

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("no SPI_HEALTH_PATH", result.stdout)

    def test_explicit_container_arguments_are_executed(self):
        result = self._run(["echo", "override"])

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("override", result.stdout.strip())


@unittest.skipUnless(BASH_READY, "bash cannot execute repository scripts on this host")
class DependabotSelectorTests(unittest.TestCase):
    JAVA = ".github/fork-resources/dependabot.yml"
    PYTHON = ".github/fork-resources/dependabot-python.yml"

    def _select(self, markers: dict[str, str], mode: str = "--print-source") -> str:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, content in markers.items():
                (root / name).write_text(content, encoding="utf-8")
            result = _run_bash([_posix_path(SELECTOR), mode, _posix_path(root)])
            self.assertEqual(0, result.returncode, result.stderr)
            return result.stdout.strip()

    def test_java_fork_keeps_the_maven_configuration(self):
        self.assertEqual(self.JAVA, self._select({"pom.xml": "<project/>"}))

    def test_python_fork_selects_the_uv_configuration(self):
        selected = self._select({"pyproject.toml": "[project]\n", "uv.lock": "version = 1\n"})
        self.assertEqual(self.PYTHON, selected)
        self.assertEqual(
            "python",
            self._select(
                {"pyproject.toml": "[project]\n", "uv.lock": "version = 1\n"},
                mode="--print-language",
            ),
        )

    def test_python_project_without_a_lockfile_keeps_the_default(self):
        self.assertEqual(self.JAVA, self._select({"pyproject.toml": "[project]\n"}))

    def test_mixed_repository_keeps_the_java_configuration(self):
        selected = self._select(
            {"pom.xml": "<project/>", "pyproject.toml": "[project]\n", "uv.lock": "version = 1\n"}
        )
        self.assertEqual(self.JAVA, selected)

    def test_unknown_repository_keeps_the_java_configuration(self):
        self.assertEqual(self.JAVA, self._select({"README.md": "#\n"}))


class ForkResourceTests(unittest.TestCase):
    def test_python_fork_dependabot_config_uses_the_uv_ecosystem(self):
        config = _read(FORK_RESOURCES / "dependabot-python.yml")

        self.assertIn('package-ecosystem: "uv"', config)
        self.assertIn('directory: "/"', config)
        self.assertIn("version-update:semver-major", config)

    def test_java_fork_dependabot_config_is_unchanged_in_intent(self):
        config = _read(FORK_RESOURCES / "dependabot.yml")

        self.assertIn('package-ecosystem: "maven"', config)
        self.assertNotIn('package-ecosystem: "uv"', config)

    def test_copilot_setup_steps_support_both_languages(self):
        workflow = _read(FORK_RESOURCES / "copilot-setup-steps.yml")

        self.assertIn("has_maven", workflow)
        self.assertIn("has_python", workflow)
        self.assertIn("if: steps.detect.outputs.has_maven == 'true'", workflow)
        self.assertIn("if: steps.detect.outputs.has_python == 'true'", workflow)
        self.assertIn("actions/setup-java@", workflow)
        self.assertIn("actions/setup-python@", workflow)
        self.assertIn("astral-sh/setup-uv@", workflow)
        self.assertIn("uv sync --locked", workflow)
        for line in workflow.splitlines():
            if USES_LINE.match(line):
                self.assertRegex(line.strip(), SHA_PIN, f"unpinned action reference: {line}")

    def test_copilot_firewall_allows_python_and_maven_hosts(self):
        config = json.loads(_read(FORK_RESOURCES / "copilot-firewall-config.json"))
        additions = config["firewall_additions"]

        for host in ("repo1.maven.org", "community.opengroup.org"):
            self.assertIn(host, additions)
        for host in ("pypi.org", "files.pythonhosted.org", "astral.sh"):
            self.assertIn(host, additions)
        self.assertEqual(sorted(additions), sorted(config["reasoning"]))

    def test_fork_copilot_instructions_cover_both_toolchains(self):
        instructions = _read(FORK_RESOURCES / "copilot-instructions.md")

        self.assertIn("mvn clean install", instructions)
        self.assertIn("uv sync --locked", instructions)
        self.assertIn("uv lock --locked", instructions)
        self.assertNotIn("Build/test Java Maven projects", instructions)

    def test_fork_resource_deployment_selects_the_language_configuration(self):
        deploy = _read(
            ROOT / ".github" / "local-actions" / "init-helpers" / "deploy-fork-resources.sh"
        )
        sync = _read(ROOT / ".github" / "template-workflows" / "sync-template.yml")

        self.assertIn("select-dependabot-config.sh", deploy)
        self.assertIn("select-dependabot-config.sh", sync)
        # Template sync must still fall back to the Java configuration.
        self.assertIn('.github/fork-resources/dependabot.yml"', sync)

    def test_template_dependabot_covers_both_canonical_dockerfiles(self):
        config = _read(ROOT / ".github" / "dependabot.yml")

        self.assertIn('- "/build"', config)
        self.assertIn('- "/build/python"', config)
        self.assertIn('package-ecosystem: "github-actions"', config)

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_changed_yaml_documents_parse(self):
        import yaml

        for path in (
            ACTION_YML,
            FORK_RESOURCES / "dependabot-python.yml",
            FORK_RESOURCES / "copilot-setup-steps.yml",
            ROOT / ".github" / "dependabot.yml",
            ROOT / ".github" / "template-workflows" / "sync-template.yml",
            ROOT / "doc" / "mkdocs.yml",
        ):
            with self.subTest(path=path.name):
                if path.name == "mkdocs.yml":
                    # mkdocs uses python-specific tags; only the nav contract is asserted.
                    self.assertIn("workflows/python-build.md", _read(path))
                    continue
                self.assertIsInstance(yaml.safe_load(_read(path)), dict)


class DocumentationTests(unittest.TestCase):
    def test_python_build_profile_is_documented(self):
        doc = _read(ROOT / "doc" / "src" / "workflows" / "python-build.md")

        self.assertIn("build/python/Dockerfile", doc)
        self.assertIn(".github/actions/python-build", doc)
        self.assertIn("uv sync --locked", doc)
        self.assertIn("--secret id=netrc", doc)
        self.assertIn("PIP_INDEX_URL", doc)
        self.assertIn("3.13", doc)

    def test_caller_contract_and_workflow_wiring_are_documented(self):
        doc = _read(ROOT / "doc" / "src" / "workflows" / "python-build.md")

        self.assertIn("caller owns the checkout", doc)
        self.assertIn("fetch-depth: 0", doc)
        self.assertIn("build_lane == 'python'", doc)
        self.assertIn("container.appModule", doc)
        self.assertIn("source", doc)

    def test_build_documentation_links_the_python_profile(self):
        build_doc = _read(ROOT / "doc" / "src" / "workflows" / "build.md")

        self.assertIn("python-build.md", build_doc)
        self.assertNotIn("Java/Maven only", build_doc)


if __name__ == "__main__":
    unittest.main()
