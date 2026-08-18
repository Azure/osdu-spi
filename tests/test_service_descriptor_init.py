"""Behaviour tests for initialization-time descriptor detection and CODEOWNERS seeding (ADR-039)."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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


descriptor = _load_module("descriptor_for_init", ".github/scripts/service-config/descriptor.py")
generator = _load_module(
    "generate_descriptor_for_init",
    ".github/scripts/service-config/generate_descriptor.py",
)
codeowners = _load_module(
    "generate_codeowners", ".github/scripts/service-config/generate_codeowners.py"
)


def _run(script: str, *args):
    return subprocess.run(
        [sys.executable, str(SERVICE_CONFIG_DIR / script), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def _repository(files: dict):
    directory = tempfile.TemporaryDirectory()
    root = Path(directory.name)
    for name, content in files.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    return directory, root


class DescriptorGenerationTests(unittest.TestCase):
    def test_maven_repository_receives_a_minimal_java_descriptor(self):
        directory, root = _repository({"pom.xml": "<project/>"})
        with directory:
            result = _run("generate_descriptor.py", "--root", str(root), "--service-name", "partition")

            self.assertEqual(0, result.returncode, result.stderr)
            generated = (root / ".spi" / "service.yaml").read_text(encoding="utf-8")
            self.assertIn("schemaVersion: 1", generated)
            self.assertIn("archetype: java-maven-azure", generated)
            self.assertIn("name: partition", generated)

            config = descriptor.resolve(root)
            self.assertTrue(config.valid)
            self.assertEqual("java", config.outputs()["build_lane"])

    def test_uv_python_repository_receives_a_python_descriptor(self):
        directory, root = _repository(
            {
                "pyproject.toml": (
                    '[project]\nname = "osdu-wbddms-worker"\nrequires-python = ">=3.12,<3.14"\n\n'
                    '[project.optional-dependencies]\ndev = ["pytest"]\naz = ["azure-identity"]\n'
                ),
                "uv.lock": "version = 1\n",
                "src/wdmsworker/__init__.py": "",
                "src/wdmsworker/app.py": "from fastapi import FastAPI\n\napp = FastAPI()\n",
            }
        )
        with directory:
            result = _run(
                "generate_descriptor.py", "--root", str(root), "--service-name", "wellbore-worker"
            )

            self.assertEqual(0, result.returncode, result.stderr)
            generated = (root / ".spi" / "service.yaml").read_text(encoding="utf-8")
            self.assertIn("archetype: python-uv-fastapi", generated)
            self.assertIn("packageManager: uv", generated)
            self.assertIn("lockfile: uv.lock", generated)
            self.assertIn('runtimeVersion: "3.12"', generated)
            self.assertIn("distribution: osdu-wbddms-worker", generated)
            self.assertIn("importPackage: wdmsworker", generated)
            self.assertIn("testExtras: [dev]", generated)
            self.assertIn("runtimeExtras: [az]", generated)
            self.assertIn("appModule: wdmsworker.app:app", generated)

            config = descriptor.resolve(root)
            self.assertTrue(config.valid, [error.render() for error in config.errors])
            self.assertEqual("python", config.outputs()["build_lane"])
            self.assertEqual("wdmsworker.app:app", config.outputs()["app_module"])

    def test_python_generation_selects_the_canonical_runtime_when_compatible(self):
        directory, root = _repository(
            {
                "pyproject.toml": (
                    '[project]\nname = "demo"\nrequires-python = ">=3.11,<4"\n'
                ),
                "uv.lock": "version = 1\n",
                "src/demo/__init__.py": "",
                "src/demo/app.py": "app = object()\n",
            }
        )
        with directory:
            result = _run("generate_descriptor.py", "--root", str(root))

            self.assertEqual(0, result.returncode, result.stdout)
            generated = (root / ".spi" / "service.yaml").read_text(encoding="utf-8")
            self.assertIn('runtimeVersion: "3.12"', generated)
            self.assertNotIn('runtimeVersion: "3.11"', generated)

    def test_python_generation_halts_when_the_canonical_runtime_is_excluded(self):
        directory, root = _repository(
            {
                "pyproject.toml": '[project]\nname = "demo"\nrequires-python = ">=3.13"\n',
                "uv.lock": "version = 1\n",
                "src/demo/__init__.py": "",
                "src/demo/app.py": "app = object()\n",
            }
        )
        with directory:
            first = _run("generate_descriptor.py", "--root", str(root))
            second = _run("generate_descriptor.py", "--root", str(root))
            check = _run("generate_descriptor.py", "--root", str(root), "--check")

            self.assertEqual(2, first.returncode)
            self.assertEqual(2, second.returncode)
            self.assertEqual(2, check.returncode)
            self.assertIn("excludes the canonical Python 3.12 runtime", first.stdout)
            self.assertFalse((root / ".spi" / "service.yaml").exists())

    def test_generated_descriptor_is_removed_when_post_write_validation_fails(self):
        directory, root = _repository({"pom.xml": "<project/>"})
        invalid = generator.descriptor_module.ResolvedConfig(
            valid=False,
            errors=[
                generator.descriptor_module.ValidationError(
                    path="service.archetype",
                    code="invalid",
                    message="synthetic validation failure",
                )
            ],
        )
        with directory, mock.patch.object(
            generator.descriptor_module, "resolve", return_value=invalid
        ):
            result = generator.main(
                ["--root", str(root), "--service-name", "partition"]
            )

            self.assertEqual(2, result)
            self.assertFalse((root / ".spi" / "service.yaml").exists())

    def test_python_generation_halts_when_the_application_module_is_unclear(self):
        base = {
            "pyproject.toml": '[project]\nname = "demo"\n',
            "uv.lock": "version = 1\n",
        }
        cases = {
            "no package at all": ({}, "No importable Python package"),
            "package without an app module": (
                {"src/demo/__init__.py": "", "src/demo/main.py": "x = 1\n"},
                "No unambiguous ASGI application module",
            ),
            "app module without an app attribute": (
                {"src/demo/__init__.py": "", "src/demo/app.py": "def create_app():\n    pass\n"},
                "No unambiguous ASGI application module",
            ),
            "two candidate packages": (
                {
                    "src/one/__init__.py": "",
                    "src/one/app.py": "app = 1\n",
                    "src/two/__init__.py": "",
                    "src/two/app.py": "app = 2\n",
                },
                "Several packages define an ASGI application module",
            ),
        }

        for label, (extra, expected) in cases.items():
            with self.subTest(label=label):
                directory, root = _repository({**base, **extra})
                with directory:
                    result = _run("generate_descriptor.py", "--root", str(root))

                    self.assertEqual(2, result.returncode)
                    self.assertIn(expected, result.stdout)
                    self.assertIn("hand-written .spi/service.yaml", result.stdout)
                    self.assertFalse((root / ".spi" / "service.yaml").exists())

    def test_python_check_mode_reports_the_detected_application_module(self):
        directory, root = _repository(
            {
                "pyproject.toml": '[project]\nname = "demo"\n',
                "uv.lock": "version = 1\n",
                "src/demo/__init__.py": "",
                "src/demo/app.py": "app = object()\n",
            }
        )
        with directory:
            result = _run("generate_descriptor.py", "--root", str(root), "--check")

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("demo.app:app", result.stdout)
            self.assertFalse((root / ".spi" / "service.yaml").exists())

    def test_flat_layout_python_project_is_supported(self):
        directory, root = _repository(
            {
                "pyproject.toml": '[project]\nname = "demo"\n',
                "uv.lock": "version = 1\n",
                "demo/__init__.py": "",
                "demo/app.py": "app: object = object()\n",
                "tests/__init__.py": "",
                "tests/app.py": "app = 1\n",
            }
        )
        with directory:
            result = _run("generate_descriptor.py", "--root", str(root), "--service-name", "demo")

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn(
                "appModule: demo.app:app", (root / ".spi" / "service.yaml").read_text(encoding="utf-8")
            )

    def test_halts_on_ambiguous_or_unsupported_repositories(self):
        cases = {
            "both java and python": ({"pom.xml": "<project/>", "pyproject.toml": "x"}, "Both Maven"),
            "python without a lockfile": ({"pyproject.toml": "x"}, "uv.lock is missing"),
            "no recognised build file": ({"README.md": "x"}, "No supported build file"),
        }

        for label, (files, expected) in cases.items():
            with self.subTest(label=label):
                directory, root = _repository(files)
                with directory:
                    result = _run("generate_descriptor.py", "--root", str(root))

                    self.assertEqual(2, result.returncode)
                    self.assertIn("::error::", result.stdout)
                    self.assertIn(expected, result.stdout)
                    self.assertFalse((root / ".spi" / "service.yaml").exists())

    def test_never_overwrites_an_existing_fork_owned_descriptor(self):
        existing = "schemaVersion: 1\nservice:\n  name: custom\n  archetype: java-maven-azure\n"
        directory, root = _repository({"pom.xml": "<project/>", ".spi/service.yaml": existing})
        with directory:
            result = _run("generate_descriptor.py", "--root", str(root))

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(existing, (root / ".spi" / "service.yaml").read_text(encoding="utf-8"))

    def test_check_mode_reports_the_archetype_without_writing(self):
        directory, root = _repository({"pom.xml": "<project/>"})
        with directory:
            result = _run("generate_descriptor.py", "--root", str(root), "--check")

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("java-maven-azure", result.stdout)
            self.assertFalse((root / ".spi" / "service.yaml").exists())

    def test_normalizes_repository_names_into_valid_service_names(self):
        generator = _load_module(
            "generate_descriptor", ".github/scripts/service-config/generate_descriptor.py"
        )

        self.assertEqual("osdu-spi-partition", generator.normalize_service_name("OSDU-SPI-Partition"))
        self.assertEqual("wellbore-worker", generator.normalize_service_name("wellbore_worker"))
        with self.assertRaises(generator.DetectionError):
            generator.normalize_service_name("...")


class CodeownersSeedingTests(unittest.TestCase):
    def test_configured_owners_produce_an_enforceable_rule(self):
        directory, root = _repository({})
        with directory:
            path = root / "CODEOWNERS"
            result = _run(
                "generate_codeowners.py", "--path", str(path), "--owners", "@my-org/engineering-system"
            )

            self.assertEqual(0, result.returncode, result.stderr)
            content = path.read_text(encoding="utf-8")
            self.assertIn("/.spi/ @my-org/engineering-system", content)
            self.assertTrue(codeowners.has_active_rule(content))
            self.assertEqual(0, _run("generate_codeowners.py", "--path", str(path), "--check").returncode)

    def test_missing_owners_produce_a_documented_placeholder_not_an_invented_team(self):
        directory, root = _repository({})
        with directory:
            path = root / "CODEOWNERS"
            result = _run("generate_codeowners.py", "--path", str(path))

            self.assertEqual(0, result.returncode, result.stderr)
            content = path.read_text(encoding="utf-8")
            self.assertIn("# /.spi/ @<org>/<engineering-system-team>", content)
            self.assertIn("SPI_ENGINEERING_OWNERS", content)
            self.assertFalse(codeowners.has_active_rule(content))
            # No uncommented owner line at all: an unknown team would silently disable
            # require_code_owner_review.
            for line in content.splitlines():
                self.assertFalse(line.strip().startswith("/"), line)
            self.assertEqual(1, _run("generate_codeowners.py", "--path", str(path), "--check").returncode)

    def test_invalid_owner_values_fall_back_to_the_placeholder(self):
        directory, root = _repository({})
        with directory:
            path = root / "CODEOWNERS"
            result = _run("generate_codeowners.py", "--path", str(path), "--owners", "engineering-system")

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertFalse(codeowners.has_active_rule(path.read_text(encoding="utf-8")))
            self.assertIn("::warning::", result.stdout)

    def test_existing_ownership_is_preserved_and_seeding_is_idempotent(self):
        directory, root = _repository({"CODEOWNERS": "* @service-team\n"})
        with directory:
            path = root / "CODEOWNERS"
            _run("generate_codeowners.py", "--path", str(path), "--owners", "@my-org/eng")
            first = path.read_text(encoding="utf-8")
            _run("generate_codeowners.py", "--path", str(path), "--owners", "@my-org/eng")
            second = path.read_text(encoding="utf-8")

            self.assertIn("* @service-team", second)
            self.assertEqual(first, second)
            self.assertEqual(1, second.count("/.spi/ @my-org/eng"))

    def test_a_hand_written_rule_is_never_rewritten(self):
        directory, root = _repository({"CODEOWNERS": "/.spi/ @my-org/custom-team\n"})
        with directory:
            path = root / "CODEOWNERS"
            result = _run("generate_codeowners.py", "--path", str(path), "--owners", "@my-org/eng")

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("/.spi/ @my-org/custom-team\n", path.read_text(encoding="utf-8"))

    def test_owner_syntax_validation(self):
        self.assertEqual(["@org/team"], codeowners.valid_owners("@org/team"))
        self.assertEqual(["@user"], codeowners.valid_owners("@user"))
        self.assertEqual(["@a/b", "@c"], codeowners.valid_owners("@a/b, @c"))
        self.assertEqual([], codeowners.valid_owners("org/team"))
        self.assertEqual([], codeowners.valid_owners("@org/team; rm -rf /"))


if __name__ == "__main__":
    unittest.main()
