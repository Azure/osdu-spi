"""Behaviour tests for the two docker-build modes (ADR-037 amendment, issue #42).

The Java lane must keep working exactly as before source mode existed, and the Python
lane must never download a build artifact, resolve a JAR, or hand a credential to a
build argument. The `prepare-build-args.sh` contract is exercised for real, so a change
that silently drops `JAR_FILE` or stops validating the application module fails here.
"""

from __future__ import annotations

import importlib.util
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
ACTION_DIR = ROOT / ".github" / "actions" / "docker-build"
ACTION_YML = ACTION_DIR / "action.yml"
PREPARE = ACTION_DIR / "prepare-build-args.sh"
PYTHON_DOCKERFILE = ROOT / "build" / "python" / "Dockerfile"
PYTHON_DOCKERIGNORE = ROOT / "build" / "python" / "Dockerfile.dockerignore"

HAS_YAML = importlib.util.find_spec("yaml") is not None


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


def _run_script(path: Path, env: dict, args: tuple = ()) -> subprocess.CompletedProcess:
    """Run a repository script through bash, tolerating a CRLF checkout.

    Values are exported inside the script rather than through the process
    environment: on Windows hosts the interop bash does not inherit the Windows
    environment, and this keeps the same test meaningful on every platform.
    """

    prelude = "".join(
        f"export {key}={shlex.quote(str(value))}\n" for key, value in sorted(env.items())
    )
    body = prelude.encode("utf-8") + path.read_bytes().replace(b"\r\n", b"\n")
    return subprocess.run(
        ["bash", "-s", *args],
        input=body,
        capture_output=True,
        # Source mode resolves the canonical Dockerfile relative to the build context.
        cwd=str(ROOT),
        timeout=120,
    )


class PrepareBuildArgsTests(unittest.TestCase):
    """The single place where mode-specific build arguments are decided."""

    def setUp(self):
        if not BASH_READY:
            self.skipTest("bash is not available on this host")
        self._directory = tempfile.TemporaryDirectory()
        self.workspace = Path(self._directory.name)
        self.output = self.workspace / "outputs.txt"
        self.output.write_text("", encoding="utf-8")
        self.addCleanup(self._directory.cleanup)

    def _prepare(self, **env) -> dict:
        environment = {"GITHUB_OUTPUT": _posix_path(self.output)}
        environment.update({key: str(value) for key, value in env.items()})
        result = _run_script(PREPARE, environment)
        self.assertEqual(
            0, result.returncode, result.stdout.decode() + result.stderr.decode()
        )
        return self._parse_outputs()

    def _expect_failure(self, **env) -> str:
        environment = {"GITHUB_OUTPUT": _posix_path(self.output)}
        environment.update({key: str(value) for key, value in env.items()})
        result = _run_script(PREPARE, environment)
        self.assertNotEqual(0, result.returncode, "expected the script to fail closed")
        return (result.stdout + result.stderr).decode()

    def _parse_outputs(self) -> dict:
        """Parse a $GITHUB_OUTPUT file, including heredoc (multiline) values."""

        outputs: dict = {}
        lines = self.output.read_text(encoding="utf-8").splitlines()
        index = 0
        while index < len(lines):
            line = lines[index]
            heredoc = re.match(r"^([A-Za-z0-9_]+)<<(\S+)$", line)
            if heredoc:
                key, delimiter = heredoc.groups()
                index += 1
                collected = []
                while index < len(lines) and lines[index] != delimiter:
                    collected.append(lines[index])
                    index += 1
                outputs[key] = collected
            else:
                key, _, value = line.partition("=")
                outputs[key] = value
            index += 1
        return outputs

    # -- Java backward compatibility ---------------------------------------------------

    def test_java_push_keeps_jar_file_and_multiarch_platforms(self):
        outputs = self._prepare(
            BUILD_MODE="java-artifact",
            JAR_FILE="provider/partition-azure/target/partition-azure-1.0-spring-boot.jar",
            PUSH="true",
        )

        self.assertEqual(
            ["JAR_FILE=provider/partition-azure/target/partition-azure-1.0-spring-boot.jar"],
            outputs["build_args"],
        )
        self.assertEqual("linux/amd64,linux/arm64", outputs["platforms"])
        self.assertEqual("true", outputs["needs_qemu"])
        self.assertEqual("build/Dockerfile", outputs["dockerfile"])

    def test_java_validate_only_stays_amd64_without_qemu(self):
        outputs = self._prepare(
            BUILD_MODE="java-artifact", JAR_FILE="target/app.jar", PUSH="false"
        )

        self.assertEqual("linux/amd64", outputs["platforms"])
        self.assertEqual("false", outputs["needs_qemu"])

    def test_default_mode_is_the_java_lane(self):
        outputs = self._prepare(JAR_FILE="target/app.jar", PUSH="false")

        self.assertEqual(["JAR_FILE=target/app.jar"], outputs["build_args"])

    def test_java_mode_without_a_resolved_jar_fails_closed(self):
        message = self._expect_failure(BUILD_MODE="java-artifact", PUSH="false")

        self.assertIn("requires a resolved JAR", message)

    # -- Python source mode ------------------------------------------------------------

    def test_source_mode_passes_no_jar_and_uses_the_python_dockerfile(self):
        outputs = self._prepare(
            BUILD_MODE="source",
            APP_MODULE="wdmsworker.app:app",
            RUNTIME_EXTRAS="az",
            PLATFORMS="linux/amd64",
            PUSH="true",
            IMAGE_SOURCE="https://github.com/org/service",
            IMAGE_REVISION="0123456789abcdef0123456789abcdef01234567",
            IMAGE_VERSION="0123456789ab",
        )

        self.assertEqual("build/python/Dockerfile", outputs["dockerfile"])
        self.assertEqual("linux/amd64", outputs["platforms"])
        self.assertEqual("false", outputs["needs_qemu"])
        self.assertIn("APP_MODULE=wdmsworker.app:app", outputs["build_args"])
        self.assertIn("RUNTIME_EXTRAS=az", outputs["build_args"])
        self.assertIn(
            "IMAGE_REVISION=0123456789abcdef0123456789abcdef01234567", outputs["build_args"]
        )
        self.assertIn("IMAGE_VERSION=0123456789ab", outputs["build_args"])
        for argument in outputs["build_args"]:
            self.assertFalse(argument.startswith("JAR_FILE="), argument)

    def test_source_mode_requires_an_application_module(self):
        message = self._expect_failure(BUILD_MODE="source", PUSH="false")

        self.assertIn("requires app_module", message)

    def test_source_mode_rejects_unsafe_values(self):
        cases = {
            "shell metacharacters": {"APP_MODULE": "app.main:app; rm -rf /"},
            "argument injection": {"APP_MODULE": "app.main:app --reload"},
            "missing attribute": {"APP_MODULE": "app.main"},
            "command substitution in extras": {
                "APP_MODULE": "app.main:app",
                "RUNTIME_EXTRAS": "az$(id)",
            },
            "newline smuggling": {"APP_MODULE": "app.main:app\nJAR_FILE=/etc/passwd"},
        }

        for label, environment in cases.items():
            with self.subTest(label=label):
                message = self._expect_failure(BUILD_MODE="source", PUSH="false", **environment)
                self.assertIn("::error::", message)

    def test_unknown_build_mode_and_platforms_fail_closed(self):
        self.assertIn("Invalid build_mode", self._expect_failure(BUILD_MODE="wasm", PUSH="false"))
        self.assertIn(
            "Invalid platforms",
            self._expect_failure(
                BUILD_MODE="source",
                APP_MODULE="app.main:app",
                PLATFORMS="linux/amd64; curl evil",
                PUSH="false",
            ),
        )

    def test_no_credential_is_ever_emitted_as_a_build_argument(self):
        outputs = self._prepare(
            BUILD_MODE="source",
            APP_MODULE="app.main:app",
            PUSH="false",
            GITHUB_TOKEN="ghp_should_never_appear",
            INDEX_TOKEN="secret-token",
        )

        rendered = "\n".join(outputs["build_args"])
        self.assertNotIn("ghp_should_never_appear", rendered)
        self.assertNotIn("secret-token", rendered)
        for forbidden in ("TOKEN", "PASSWORD", "SECRET", "NETRC"):
            self.assertNotIn(forbidden, rendered.upper())


class ActionContractTests(unittest.TestCase):
    def setUp(self):
        self.action = _read(ACTION_YML)

    def test_directly_invoked_scripts_are_executable(self):
        """The action runs these scripts directly, so the tracked mode must be 0755."""

        if shutil.which("git") is None:
            self.skipTest("git is not available")

        scripts = [
            ".github/actions/docker-build/compute-metadata.sh",
            ".github/actions/docker-build/compute-tags.sh",
            ".github/actions/docker-build/resolve-jar.sh",
            ".github/actions/docker-build/prepare-build-args.sh",
            ".github/actions/docker-build/set-package-visibility.sh",
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
        listed = {line.split("\t", 1)[1].strip(): line.split(" ", 1)[0] for line in result.stdout.strip().splitlines()}
        for script in scripts:
            self.assertEqual("100755", listed.get(script), f"{script} must be tracked as executable")

    def test_artifact_and_jar_steps_are_java_mode_only(self):
        download = self.action.split('- name: "Download build artifacts"', 1)[1]
        jar = self.action.split('- name: "Resolve service JAR path"', 1)[1]

        self.assertIn("if: ${{ inputs.build_mode != 'source' }}", download.split("- name:", 1)[0])
        self.assertIn("if: ${{ inputs.build_mode != 'source' }}", jar.split("- name:", 1)[0])

    def test_build_step_consumes_the_prepared_mode_specific_values(self):
        build = self.action.split('- name: "Build container image"', 1)[1]

        self.assertIn("file: ${{ steps.args.outputs.dockerfile }}", build)
        self.assertIn("platforms: ${{ steps.args.outputs.platforms }}", build)
        self.assertIn("${{ steps.args.outputs.build_args }}", build)
        self.assertIn("${{ inputs.build_args }}", build)
        self.assertIn("provenance: false", build)

    def test_qemu_is_only_set_up_for_an_emulated_leg(self):
        qemu = self.action.split('- name: "Set up QEMU"', 1)[1].split("- name:", 1)[0]

        self.assertIn("if: ${{ steps.args.outputs.needs_qemu == 'true' }}", qemu)

    def test_outputs_tags_and_visibility_behaviour_are_unchanged(self):
        self.assertIn("value: ${{ steps.meta.outputs.image_repository }}", self.action)
        self.assertIn(
            "value: ${{ inputs.push == 'true' && steps.build.outputs.digest || '' }}", self.action
        )
        self.assertIn("value: ${{ steps.tags.outputs.image_tags }}", self.action)
        self.assertIn('"$GITHUB_ACTION_PATH/set-package-visibility.sh" "$ORG" "$IMAGE_NAME"', self.action)
        self.assertIn("if: ${{ inputs.push == 'true' && steps.build.outcome == 'success' }}", self.action)

    def test_registry_login_still_only_happens_on_the_push_path(self):
        login = self.action.split('- name: "Log in to GHCR"', 1)[1].split("- name:", 1)[0]

        self.assertIn("if: ${{ inputs.push == 'true' }}", login)

    def test_no_secret_is_mounted_or_passed_by_the_action(self):
        # The pilot registry is public: the action passes no BuildKit secret. The
        # Dockerfile keeps its optional netrc mount for services that need one.
        self.assertNotIn("secrets: |", self.action)
        self.assertNotIn("secret-files:", self.action)
        self.assertNotIn("id=netrc", self.action)

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_new_inputs_are_declared_with_backward_compatible_defaults(self):
        import yaml

        inputs = yaml.safe_load(self.action)["inputs"]

        self.assertEqual("java-artifact", inputs["build_mode"]["default"])
        self.assertEqual("build/Dockerfile", inputs["dockerfile_path"]["default"])
        self.assertEqual("", inputs["platforms"]["default"])
        self.assertEqual("", inputs["app_module"]["default"])
        self.assertEqual("", inputs["runtime_extras"]["default"])
        self.assertEqual("true", str(inputs["push"]["default"]))

    @unittest.skipUnless(HAS_YAML, "PyYAML is not available")
    def test_no_workflow_expression_reaches_a_run_body(self):
        import yaml

        for step in yaml.safe_load(self.action)["runs"]["steps"]:
            body = step.get("run")
            if body is None:
                continue
            self.assertNotIn("${{", body, f"step '{step.get('name')}' interpolates an expression")


class PythonImageSecretTests(unittest.TestCase):
    def test_python_build_context_excludes_local_environments_and_caches(self):
        patterns = {
            line.strip()
            for line in _read(PYTHON_DOCKERIGNORE).splitlines()
            if line.strip() and not line.startswith("#")
        }

        for required in (
            ".git",
            ".venv",
            "venv",
            "__pycache__",
            ".pytest_cache",
            ".mypy_cache",
            ".ruff_cache",
            ".spi-build-reports",
            "dist",
        ):
            self.assertIn(required, patterns)

        # The canonical entrypoint is copied from this tree, so build/ itself
        # must remain in the context.
        self.assertNotIn("build", patterns)
        self.assertNotIn("build/", patterns)

    def test_netrc_secret_mount_stays_optional(self):
        dockerfile = _read(PYTHON_DOCKERFILE)

        self.assertIn("--mount=type=secret,id=netrc", dockerfile)
        for mount in re.findall(r"--mount=type=secret[^ \\\n]*", dockerfile):
            self.assertNotIn("required=true", mount)

    def test_documented_build_arguments_exist_in_the_image(self):
        dockerfile = _read(PYTHON_DOCKERFILE)

        for argument in ("APP_MODULE", "RUNTIME_EXTRAS", "IMAGE_SOURCE", "IMAGE_REVISION", "IMAGE_VERSION"):
            self.assertIn(f"ARG {argument}", dockerfile)


if __name__ == "__main__":
    unittest.main()
