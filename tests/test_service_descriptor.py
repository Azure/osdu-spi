"""Behaviour tests for the fork-owned service descriptor parser and validator (ADR-039)."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SERVICE_CONFIG_DIR = ROOT / ".github" / "scripts" / "service-config"


def _load_module(name: str, relative_path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {relative_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


descriptor = _load_module("descriptor", ".github/scripts/service-config/descriptor.py")


JAVA_DESCRIPTOR = """\
schemaVersion: 1

service:
  name: partition
  archetype: java-maven-azure

build:
  mavenProfiles:
    - core
    - azure
  artifact:
    discovery: spring-boot-azure

tests:
  unit:
    type: maven
    coverage: jacoco

container:
  dockerfileProfile: java
"""

PYTHON_DESCRIPTOR = """\
schemaVersion: 1

service:
  name: wellbore-ddms-worker
  archetype: python-uv-fastapi

build:
  python:
    runtimeVersion: "3.12"
    compatibilityVersions: ["3.13"]
    packageManager: uv
    lockfile: uv.lock
    distribution: osdu-wbddms-worker
    importPackage: wdmsworker
    testExtras: [dev]
    runtimeExtras: [az]

tests:
  unit:
    type: pytest
    path: tests/unit
    coverage: true

container:
  appModule: wdmsworker.app:app
"""


def _repository(descriptor_text: str = "", markers=()):
    directory = tempfile.TemporaryDirectory()
    root = Path(directory.name)
    for marker in markers:
        target = root / marker
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("marker", encoding="utf-8")
    if descriptor_text:
        (root / ".spi").mkdir(parents=True, exist_ok=True)
        (root / ".spi" / "service.yaml").write_text(descriptor_text, encoding="utf-8")
    return directory, root


def _codes(errors):
    return sorted({error.code for error in errors})


class DescriptorParsingTests(unittest.TestCase):
    def test_reads_a_conventional_java_descriptor(self):
        document = descriptor.parse(JAVA_DESCRIPTOR)

        self.assertEqual("partition", document["service"]["name"])
        self.assertEqual(["core", "azure"], document["build"]["mavenProfiles"])
        self.assertEqual([], descriptor.validate(document))

    def test_reads_a_python_descriptor_with_flow_sequences(self):
        document = descriptor.parse(PYTHON_DESCRIPTOR)

        self.assertEqual(["3.13"], document["build"]["python"]["compatibilityVersions"])
        self.assertEqual(["dev"], document["build"]["python"]["testExtras"])
        self.assertTrue(document["tests"]["unit"]["coverage"])
        self.assertEqual([], descriptor.validate(document))

    def test_rejects_yaml_features_outside_the_supported_subset(self):
        unsupported = {
            "tabs": "schemaVersion: 1\n\tservice: partition\n",
            "anchors": "schemaVersion: 1\nservice: &anchor\n",
            "block scalar": "schemaVersion: 1\nservice: |\n  text\n",
            "multiple documents": "---\nschemaVersion: 1\n---\nschemaVersion: 1\n",
            "duplicate keys": "schemaVersion: 1\nschemaVersion: 1\n",
            "nulls": "schemaVersion: 1\nservice: null\n",
            "unquoted version numbers": "schemaVersion: 1\nservice:\n  name: 3.12\n",
            "unterminated quotes": 'schemaVersion: 1\nservice:\n  name: "partition\n',
            "odd indentation": "schemaVersion: 1\nservice:\n   name: partition\n",
        }

        for label, text in unsupported.items():
            with self.subTest(label=label):
                with self.assertRaises(descriptor.DescriptorError):
                    descriptor.parse(text)

    def test_rejects_an_empty_or_non_mapping_document(self):
        for text in ("", "# only a comment\n", "- item\n"):
            with self.subTest(text=text):
                with self.assertRaises(descriptor.DescriptorError):
                    descriptor.parse(text)


class DescriptorValidationTests(unittest.TestCase):
    def test_rejects_an_unknown_archetype(self):
        document = descriptor.parse(
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: go-modules\n"
        )

        self.assertIn("invalid-value", _codes(descriptor.validate(document)))

    def test_rejects_a_future_schema_version(self):
        document = descriptor.parse(
            "schemaVersion: 99\nservice:\n  name: demo\n  archetype: java-maven-azure\n"
        )

        self.assertIn("unsupported-schema-version", _codes(descriptor.validate(document)))

    def test_rejects_unknown_keys(self):
        document = descriptor.parse(
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: java-maven-azure\ndeploy: fast\n"
        )

        self.assertIn("unknown-key", _codes(descriptor.validate(document)))

    def test_rejects_privileged_configuration(self):
        privileged = {
            "command": "build:\n  command: rm -rf /\n",
            "secrets": "build:\n  secrets: ALL\n",
            "environment": "container:\n  environment: production\n",
            "namespace": "container:\n  namespace: osdu\n",
            "identity": "container:\n  identity: managed\n",
            "action reference": "build:\n  uses: evil/action@main\n",
            "permissions": "build:\n  permissions: write-all\n",
        }
        head = "schemaVersion: 1\nservice:\n  name: demo\n  archetype: java-maven-azure\n"

        for label, extra in privileged.items():
            with self.subTest(label=label):
                document = descriptor.parse(head + extra)
                self.assertIn("forbidden-key", _codes(descriptor.validate(document)))

    def test_rejects_paths_that_escape_the_repository(self):
        head = "schemaVersion: 1\nservice:\n  name: demo\n  archetype: java-maven-azure\n"

        for value in ("../../etc/passwd", "/etc/passwd", "tests/$(whoami)"):
            with self.subTest(value=value):
                document = descriptor.parse(head + f"tests:\n  unit:\n    path: {value}\n")
                self.assertIn("invalid-path", _codes(descriptor.validate(document)))

    def test_rejects_cross_archetype_and_mismatched_settings(self):
        cases = {
            "python block on java service": (
                "java-maven-azure",
                "build:\n  python:\n    packageManager: uv\n",
                "archetype-mismatch",
            ),
            "maven profiles on python service": (
                "python-uv-fastapi",
                "build:\n  mavenProfiles: [core]\n",
                "archetype-mismatch",
            ),
            "python image for a java service": (
                "java-maven-azure",
                "container:\n  dockerfileProfile: python\n",
                "profile-mismatch",
            ),
            "pytest suite for a java service": (
                "java-maven-azure",
                "tests:\n  unit:\n    type: pytest\n",
                "test-type-mismatch",
            ),
        }

        for label, (archetype, extra, expected) in cases.items():
            with self.subTest(label=label):
                document = descriptor.parse(
                    f"schemaVersion: 1\nservice:\n  name: demo\n  archetype: {archetype}\n" + extra
                )
                self.assertIn(expected, _codes(descriptor.validate(document)))

    def test_python_runtime_must_match_the_canonical_image(self):
        document = descriptor.parse(
            PYTHON_DESCRIPTOR.replace('runtimeVersion: "3.12"', 'runtimeVersion: "3.13"')
        )

        self.assertIn("invalid-value", _codes(descriptor.validate(document)))

    def test_rejects_an_invalid_service_name(self):
        document = descriptor.parse(
            "schemaVersion: 1\nservice:\n  name: Partition Service\n  archetype: java-maven-azure\n"
        )

        self.assertIn("invalid-value", _codes(descriptor.validate(document)))

    def test_requires_service_identity(self):
        document = descriptor.parse("schemaVersion: 1\nservice:\n  name: demo\n")

        self.assertIn("missing-key", _codes(descriptor.validate(document)))

    def test_python_service_must_declare_a_container_application_module(self):
        document = descriptor.parse(
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: python-uv-fastapi\n"
        )

        errors = descriptor.validate(document)
        self.assertIn("missing-key", _codes(errors))
        self.assertTrue(any(error.path == "container.appModule" for error in errors))

    def test_application_module_pattern_rejects_anything_but_module_colon_attribute(self):
        head = (
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: python-uv-fastapi\n"
            "container:\n  appModule: "
        )
        unsafe = [
            '"app.main:app; rm -rf /"',
            '"app.main:app --reload"',
            '"app.main"',
            '"$(id)"',
            '"app.main:app app.other:app"',
            '"/etc/passwd:app"',
        ]

        for value in unsafe:
            with self.subTest(value=value):
                document = descriptor.parse(head + value + "\n")
                self.assertIn("invalid-value", _codes(descriptor.validate(document)))

        valid = descriptor.parse(head + "wdmsworker.app:app\n")
        self.assertEqual([], descriptor.validate(valid))

    def test_application_module_is_rejected_for_a_java_service(self):
        document = descriptor.parse(
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: java-maven-azure\n"
            "container:\n  appModule: demo.app:app\n"
        )

        self.assertIn("archetype-mismatch", _codes(descriptor.validate(document)))

    def test_pattern_validation_anchors_on_the_whole_value(self):
        """A trailing newline must not satisfy a '$'-anchored pattern."""

        document = {
            "schemaVersion": 1,
            "service": {"name": "demo", "archetype": "python-uv-fastapi"},
            "container": {"appModule": "demo.app:app\nJAR_FILE=/etc/passwd"},
        }
        trailing = {
            "schemaVersion": 1,
            "service": {"name": "demo\n", "archetype": "python-uv-fastapi"},
            "container": {"appModule": "demo.app:app"},
        }

        self.assertIn("invalid-value", _codes(descriptor.validate(document)))
        self.assertIn("invalid-value", _codes(descriptor.validate(trailing)))


class DescriptorResolutionTests(unittest.TestCase):
    def test_java_descriptor_selects_the_java_lane(self):
        directory, root = _repository(JAVA_DESCRIPTOR, markers=["pom.xml"])
        with directory:
            config = descriptor.resolve(root, service_name="repository-name")

            self.assertTrue(config.valid)
            self.assertEqual(
                {
                    "descriptor_present": "true",
                    "schema_version": "1",
                    "archetype": "java-maven-azure",
                    "service_name": "partition",
                    "dockerfile_profile": "java",
                    "unit_test_type": "maven",
                    "has_coverage": "true",
                    "build_lane": "java",
                    "lane_implemented": "true",
                    "fallback": "none",
                    "python_runtime_version": "",
                    "python_distribution": "",
                    "python_import_package": "",
                    "python_test_extras": "",
                    "python_runtime_extras": "",
                    "app_module": "",
                },
                config.outputs(),
            )

    def test_python_descriptor_publishes_the_python_lane_inputs(self):
        directory, root = _repository(PYTHON_DESCRIPTOR, markers=["pyproject.toml", "uv.lock"])
        with directory:
            config = descriptor.resolve(root)

            self.assertTrue(config.valid)
            outputs = config.outputs()
            self.assertEqual("python", outputs["build_lane"])
            self.assertEqual("true", outputs["lane_implemented"])
            self.assertEqual("python", outputs["dockerfile_profile"])
            self.assertEqual("3.12", outputs["python_runtime_version"])
            self.assertEqual("osdu-wbddms-worker", outputs["python_distribution"])
            self.assertEqual("wdmsworker", outputs["python_import_package"])
            self.assertEqual("dev", outputs["python_test_extras"])
            self.assertEqual("az", outputs["python_runtime_extras"])
            self.assertEqual("wdmsworker.app:app", outputs["app_module"])
            self.assertEqual([], config.warnings)

    def test_minimal_python_descriptor_falls_back_to_the_runtime_default(self):
        minimal = (
            "schemaVersion: 1\n"
            "service:\n  name: demo\n  archetype: python-uv-fastapi\n"
            "container:\n  appModule: demo.app:app\n"
        )
        directory, root = _repository(minimal, markers=["pyproject.toml", "uv.lock"])
        with directory:
            outputs = descriptor.resolve(root).outputs()

            self.assertEqual("3.12", outputs["python_runtime_version"])
            self.assertEqual("", outputs["python_test_extras"])
            self.assertEqual("demo.app:app", outputs["app_module"])

    def test_missing_descriptor_keeps_java_inference_with_a_warning(self):
        directory, root = _repository(markers=["pom.xml"])
        with directory:
            config = descriptor.resolve(root, service_name="partition")

            self.assertTrue(config.valid)
            self.assertEqual("java", config.outputs()["build_lane"])
            self.assertEqual("java-inference", config.outputs()["fallback"])
            self.assertEqual("partition", config.outputs()["service_name"])
            self.assertTrue(any("legacy Java inference" in warning for warning in config.warnings))

    def test_legacy_java_inference_remains_recursive(self):
        directory, root = _repository(markers=["modules/provider/azure/pom.xml"])
        with directory:
            outputs = descriptor.resolve(root, service_name="deep-java-service").outputs()

            self.assertEqual("java", outputs["build_lane"])
            self.assertEqual("java-inference", outputs["fallback"])

    def test_missing_descriptor_and_no_markers_selects_no_lane(self):
        directory, root = _repository()
        with directory:
            config = descriptor.resolve(root, service_name="docs-only")

            self.assertTrue(config.valid)
            self.assertEqual("none", config.outputs()["build_lane"])
            self.assertEqual("false", config.outputs()["lane_implemented"])

    def test_invalid_descriptor_fails_closed_instead_of_falling_back(self):
        directory, root = _repository(
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: go-modules\n",
            markers=["pom.xml"],
        )
        with directory:
            config = descriptor.resolve(root)

            self.assertFalse(config.valid)
            self.assertEqual("none", config.outputs()["build_lane"])
            self.assertEqual("false", config.outputs()["lane_implemented"])

    def test_unparsable_descriptor_fails_closed(self):
        directory, root = _repository("schemaVersion: 1\n\tservice: broken\n", markers=["pom.xml"])
        with directory:
            config = descriptor.resolve(root)

            self.assertFalse(config.valid)
            self.assertEqual(["parse-error"], _codes(config.errors))


class ReadServiceConfigCommandTests(unittest.TestCase):
    def _run(self, root: Path, *args):
        return subprocess.run(
            [sys.executable, str(SERVICE_CONFIG_DIR / "read_service_config.py"), "--root", str(root), *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    def test_writes_the_workflow_output_contract(self):
        directory, root = _repository(JAVA_DESCRIPTOR, markers=["pom.xml"])
        with directory:
            output = root / "outputs.txt"
            result = self._run(root, "--format", "github", "--output", str(output))

            self.assertEqual(0, result.returncode, result.stderr)
            written = output.read_text(encoding="utf-8")
            self.assertIn("build_lane=java\n", written)
            self.assertIn("archetype=java-maven-azure\n", written)
            self.assertIn("lane_implemented=true\n", written)
            self.assertNotIn("run=", written)

    def test_exits_non_zero_for_an_invalid_descriptor(self):
        directory, root = _repository(
            "schemaVersion: 4\nservice:\n  name: demo\n  archetype: java-maven-azure\n"
        )
        with directory:
            output = root / "outputs.txt"
            result = self._run(root, "--format", "github", "--output", str(output))

            self.assertEqual(1, result.returncode)
            self.assertIn("::error::", result.stdout)

    def test_json_output_is_machine_readable_and_redactable(self):
        directory, root = _repository(
            "schemaVersion: 1\nservice:\n  name: demo\n  archetype: java-maven-azure\nsecrets: all\n"
        )
        with directory:
            result = self._run(root, "--format", "json", "--redact")

            self.assertEqual(1, result.returncode)
            payload = json.loads(result.stdout)
            self.assertFalse(payload["valid"])
            self.assertIn("secrets: forbidden-key", payload["errors"])
            self.assertNotIn("all", " ".join(payload["errors"]))

    def test_a_multi_line_service_name_cannot_inject_extra_outputs(self):
        """$GITHUB_OUTPUT is line-based; the fallback name comes from a repository variable."""

        directory, root = _repository(markers=["pom.xml"])
        with directory:
            output = root / "outputs.txt"
            result = self._run(
                root,
                "--service-name",
                "demo\nbuild_lane=python",
                "--format",
                "github",
                "--output",
                str(output),
            )

            self.assertEqual(1, result.returncode)
            self.assertIn("multi-line output", result.stderr)
            self.assertEqual("", output.read_text(encoding="utf-8") if output.exists() else "")

    def test_python_outputs_are_published_for_the_workflow_contract(self):
        directory, root = _repository(PYTHON_DESCRIPTOR, markers=["pyproject.toml", "uv.lock"])
        with directory:
            output = root / "outputs.txt"
            result = self._run(root, "--format", "github", "--output", str(output))

            self.assertEqual(0, result.returncode, result.stderr)
            written = output.read_text(encoding="utf-8")
            self.assertIn("build_lane=python\n", written)
            self.assertIn("lane_implemented=true\n", written)
            self.assertIn("app_module=wdmsworker.app:app\n", written)
            self.assertIn("python_runtime_version=3.12\n", written)
            self.assertIn("python_test_extras=dev\n", written)
            self.assertIn("python_runtime_extras=az\n", written)


if __name__ == "__main__":
    unittest.main()
