#!/usr/bin/env python3
"""Detect the service shape during initialization and generate `.spi/service.yaml`.

Detection is deliberately narrow (ADR-039 §"halt instead of guessing"):

  pom.xml                      -> java-maven-azure
  pyproject.toml + uv.lock     -> python-uv-fastapi
  anything else / both / neither -> halt with an actionable error

For a Python service the ASGI application module is detected the same way: an
unambiguous `src/<package>/app.py` that defines a top-level `app` becomes
`container.appModule`. Anything less clear halts and asks for a reviewed,
hand-written descriptor — the canonical image bakes this value into its
entrypoint, so a guess would only fail when the container starts.

An existing descriptor is never overwritten: the descriptor is fork-owned.

Usage:
  generate_descriptor.py --root . --service-name partition
  generate_descriptor.py --root . --check      # detect only, write nothing

Exit codes:
  0  descriptor generated, or already present
  2  service shape is ambiguous or unsupported — initialization must halt
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

try:  # Python 3.11+
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - legacy interpreters only
    tomllib = None  # type: ignore[assignment]

sys.path.insert(0, str(Path(__file__).resolve().parent))

import descriptor as descriptor_module  # noqa: E402  (path set above for standalone use)


CANONICAL_PYTHON_RUNTIME = "3.12"
_CANONICAL_RUNTIME_PARTS = (3, 12)
DEFAULT_TEST_EXTRA = "dev"
DEFAULT_RUNTIME_EXTRA = "az"
EXCLUDED_PACKAGE_DIRS = frozenset(
    {"tests", "test", "docs", "doc", "build", "dist", "scripts", "examples"}
)
_NAME_RE = re.compile(r"[^a-z0-9-]+")


class DetectionError(Exception):
    """Raised when the repository shape cannot be classified safely."""

    def __init__(self, message: str, remediation: str) -> None:
        self.remediation = remediation
        super().__init__(message)


def normalize_service_name(raw: str) -> str:
    name = _NAME_RE.sub("-", raw.strip().lower()).strip("-")[:63]
    if not name or not re.match(r"^[a-z0-9][a-z0-9-]*$", name):
        raise DetectionError(
            f"Cannot derive a valid service name from '{raw}'.",
            "Pass --service-name with a lowercase name such as 'partition'.",
        )
    return name


def _maven_markers(root: Path) -> List[Path]:
    found = [path for path in [root / "pom.xml"] if path.is_file()]
    found.extend(sorted(root.glob("*/pom.xml")))
    found.extend(sorted(root.glob("*/*/pom.xml")))
    return found


def detect_archetype(root: Path) -> Tuple[str, List[str]]:
    """Return `(archetype, evidence)` or raise `DetectionError`."""

    maven = _maven_markers(root)
    pyproject = (root / "pyproject.toml").is_file()
    uv_lock = (root / "uv.lock").is_file()

    if maven and pyproject:
        raise DetectionError(
            "Both Maven (pom.xml) and Python (pyproject.toml) build files were found.",
            "Commit a hand-written .spi/service.yaml that names the intended archetype, "
            "then re-run initialization.",
        )
    if maven:
        return "java-maven-azure", [str(path.relative_to(root)).replace("\\", "/") for path in maven[:3]]
    if pyproject and uv_lock:
        return "python-uv-fastapi", ["pyproject.toml", "uv.lock"]
    if pyproject and not uv_lock:
        raise DetectionError(
            "pyproject.toml was found but uv.lock is missing.",
            "Only uv-managed Python services are supported; commit uv.lock upstream or "
            "add a hand-written .spi/service.yaml.",
        )
    raise DetectionError(
        "No supported build file was found (expected pom.xml, or pyproject.toml with uv.lock).",
        "Add a hand-written .spi/service.yaml declaring a supported archetype, or onboard the "
        "service once its build system is supported by the template.",
    )


def _requires_python_allows_canonical_runtime(specifier: str) -> bool:
    """Evaluate the common major/minor-only PEP 440 subset used by OSDU services.

    The descriptor selects a runtime *line*, not a patch release. Patch-specific
    or otherwise unfamiliar constraints halt generation rather than guessing.
    """

    for raw_clause in specifier.split(","):
        clause = raw_clause.strip()
        match = re.fullmatch(
            r"(~=|==|!=|<=|>=|<|>)\s*(\d+)(?:\.(\d+|\*))?(?:\.(\d+|\*))?",
            clause,
        )
        if not match:
            raise DetectionError(
                f"Cannot safely evaluate requires-python '{specifier}' against "
                f"the canonical Python {CANONICAL_PYTHON_RUNTIME} runtime.",
                "Use a major/minor-only Python version constraint, or wait until the "
                "required runtime is supported by the python-uv-fastapi archetype.",
            )

        operator, major, minor, patch = match.groups()
        if patch is not None and patch != "*":
            raise DetectionError(
                f"requires-python '{specifier}' is more specific than the descriptor's "
                f"Python {CANONICAL_PYTHON_RUNTIME} runtime line.",
                "Use a major/minor-only Python version constraint, or wait until the "
                "required runtime is supported by the python-uv-fastapi archetype.",
            )

        runtime = _CANONICAL_RUNTIME_PARTS
        wildcard_parts = 1 if minor == "*" else 2 if patch == "*" else 0
        if wildcard_parts and operator not in {"==", "!="}:
            raise DetectionError(
                f"Cannot safely evaluate requires-python '{specifier}' against "
                f"the canonical Python {CANONICAL_PYTHON_RUNTIME} runtime.",
                "Use a standard major/minor Python version constraint.",
            )
        if operator == "~=" and minor is None:
            raise DetectionError(
                f"requires-python '{specifier}' uses an invalid compatible-release clause.",
                "Use at least a major/minor compatible-release constraint such as '~=3.12'.",
            )

        required = (int(major), int(minor or 0)) if not wildcard_parts else (0, 0)
        if wildcard_parts == 1:
            equal = runtime[:1] == (int(major),)
        elif wildcard_parts == 2:
            equal = runtime == (int(major), int(minor))
        else:
            equal = runtime == required

        matches = {
            ">=": runtime >= required,
            ">": runtime > required,
            "<=": runtime <= required,
            "<": runtime < required,
            "==": equal,
            "!=": not equal,
            "~=": runtime >= required and runtime[0] == required[0],
        }[operator]
        if not matches:
            return False
    return True


def _detect_python_runtime(root: Path) -> str:
    project = _read_python_project(root)
    specifier = project.get("requires-python")
    if not isinstance(specifier, str) or not specifier:
        return CANONICAL_PYTHON_RUNTIME
    if not _requires_python_allows_canonical_runtime(specifier):
        raise DetectionError(
            f"requires-python '{specifier}' excludes the canonical "
            f"Python {CANONICAL_PYTHON_RUNTIME} runtime.",
            f"The python-uv-fastapi archetype currently requires Python "
            f"{CANONICAL_PYTHON_RUNTIME}; update the service constraint or wait for "
            "a new canonical runtime.",
        )
    return CANONICAL_PYTHON_RUNTIME


def _detect_python_distribution(root: Path) -> Optional[str]:
    project = _read_python_project(root)
    distribution = project.get("name")
    if not isinstance(distribution, str):
        return None
    return distribution if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", distribution) else None


def _read_python_project(root: Path) -> dict:
    """Return the parsed `[project]` table or halt on invalid project metadata."""

    if tomllib is None:  # pragma: no cover - initialization runs on Python 3.11+
        raise DetectionError(
            "Python project metadata cannot be read because tomllib is unavailable.",
            "Run initialization with Python 3.11 or newer.",
        )
    try:
        with (root / "pyproject.toml").open("rb") as stream:
            document = tomllib.load(stream)
    except (OSError, ValueError) as error:
        raise DetectionError(
            f"pyproject.toml could not be parsed: {error}",
            "Fix the project metadata before running initialization.",
        ) from error
    project = document.get("project", {})
    return project if isinstance(project, dict) else {}


def _detect_python_compatibility_versions(root: Path) -> List[str]:
    """Return non-runtime Python versions explicitly advertised by classifiers."""

    classifiers = _read_python_project(root).get("classifiers", [])
    if not isinstance(classifiers, list):
        return []
    advertised = {
        item.rsplit("::", 1)[-1].strip()
        for item in classifiers
        if isinstance(item, str) and item.startswith("Programming Language :: Python :: 3.")
    }
    return [version for version in ("3.11", "3.13") if version in advertised]


def _import_packages(root: Path) -> List[str]:
    """Return the importable packages of a src-layout (preferred) or flat project."""

    def packages_in(base: Path) -> List[str]:
        if not base.is_dir():
            return []
        return sorted(
            child.name
            for child in base.iterdir()
            if child.is_dir()
            and (child / "__init__.py").is_file()
            and re.match(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$", child.name)
            and child.name not in EXCLUDED_PACKAGE_DIRS
        )

    src_packages = packages_in(root / "src")
    return src_packages or packages_in(root)


def _declares_asgi_app(module: Path) -> bool:
    """True when the module assigns a top-level `app` (the uvicorn target)."""

    try:
        text = module.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False
    return bool(re.search(r"^app\s*(?::[^=\n]+)?=", text, re.MULTILINE))


def detect_app_module(root: Path) -> Tuple[str, str]:
    """Return `(app_module, evidence)` for an unambiguous `src/<package>/app.py`.

    The canonical Python image bakes its uvicorn target at build time, so the module
    is part of the descriptor rather than deploy-time configuration. Generation halts
    when the target cannot be identified without guessing: a wrong module produces an
    image that only fails when the container starts.
    """

    packages = _import_packages(root)
    base = root / "src" if (root / "src").is_dir() else root
    candidates = [
        package
        for package in packages
        if (base / package / "app.py").is_file() and _declares_asgi_app(base / package / "app.py")
    ]

    if len(candidates) == 1:
        package = candidates[0]
        relative = f"{base.name}/{package}/app.py" if base != root else f"{package}/app.py"
        return f"{package}.app:app", relative

    if not packages:
        raise DetectionError(
            "No importable Python package was found under src/ (or the repository root).",
            "Commit a hand-written .spi/service.yaml declaring 'container.appModule' "
            "(for example 'wdmsworker.app:app'), then re-run initialization.",
        )
    if not candidates:
        raise DetectionError(
            "No unambiguous ASGI application module was found "
            f"(expected src/<package>/app.py defining 'app'; packages: {', '.join(packages)}).",
            "Add 'container.appModule' to a hand-written .spi/service.yaml (for example "
            "'wdmsworker.app:app') so the container entrypoint is reviewed rather than guessed.",
        )
    raise DetectionError(
        f"Several packages define an ASGI application module ({', '.join(candidates)}).",
        "Declare the intended target in 'container.appModule' in a hand-written "
        ".spi/service.yaml, then re-run initialization.",
    )


def _declared_extras(root: Path) -> List[str]:
    """Return the `[project.optional-dependencies]` names declared by the project."""

    optional = _read_python_project(root).get("optional-dependencies", {})
    if not isinstance(optional, dict):
        return []
    return [
        name
        for name in optional
        if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", name)
    ]


HEADER = """# Service descriptor — owned by this repository, not by the template.
#
# Template-sync never overwrites `.spi/**`. Changes here are normal reviewed
# pull requests and select only unprivileged build/test behaviour: no Azure
# identity, cluster, namespace, environment, secret or workflow reference may
# appear in this file (ADR-039).
#
# Schema: .github/scripts/service-config/schema.json
# Generated during repository initialization; edit as the service evolves.
"""


def render_descriptor(archetype: str, service_name: str, root: Path, app_module: str = "") -> str:
    lines = [
        HEADER,
        "schemaVersion: 1",
        "",
        "service:",
        f"  name: {service_name}",
        f"  archetype: {archetype}",
    ]
    if archetype == "python-uv-fastapi":
        if not app_module:
            app_module, _ = detect_app_module(root)
        lines.extend(["", "build:", "  python:", "    packageManager: uv", "    lockfile: uv.lock"])
        runtime = _detect_python_runtime(root)
        lines.append(f'    runtimeVersion: "{runtime}"')
        compatibility = _detect_python_compatibility_versions(root)
        if compatibility:
            quoted = ", ".join(f'"{version}"' for version in compatibility)
            lines.append(f"    compatibilityVersions: [{quoted}]")
        distribution = _detect_python_distribution(root)
        if distribution:
            lines.append(f"    distribution: {distribution}")
        import_package = app_module.split(".", 1)[0]
        lines.append(f"    importPackage: {import_package}")
        extras = _declared_extras(root)
        if DEFAULT_TEST_EXTRA in extras:
            lines.append(f"    testExtras: [{DEFAULT_TEST_EXTRA}]")
        if DEFAULT_RUNTIME_EXTRA in extras:
            lines.append(f"    runtimeExtras: [{DEFAULT_RUNTIME_EXTRA}]")
        lines.extend(["", "container:", f"  appModule: {app_module}"])
    lines.append("")
    return "\n".join(lines)


def _parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Repository root to inspect")
    parser.add_argument("--service-name", default="", help="Service name (defaults to the repository directory name)")
    parser.add_argument("--check", action="store_true", help="Detect only; do not write a descriptor")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = _parse_args(argv)
    descriptor_module.configure_stdio()
    root = Path(args.root).resolve()
    target = root / descriptor_module.DESCRIPTOR_PATH

    if target.is_file():
        print(f"✅ {descriptor_module.DESCRIPTOR_PATH} already exists — leaving the fork-owned descriptor untouched.")
        return 0

    try:
        archetype, evidence = detect_archetype(root)
        service_name = normalize_service_name(args.service_name or root.name)
        app_module = ""
        if archetype == "python-uv-fastapi":
            # Detected before anything is written so an unclear entrypoint halts
            # initialization rather than producing an unstartable image later.
            app_module, app_evidence = detect_app_module(root)
            evidence = [*evidence, app_evidence]
    except DetectionError as error:
        print(f"::error::Service descriptor generation halted: {error}")
        print(f"::error::{error.remediation}")
        return 2

    try:
        rendered = render_descriptor(archetype, service_name, root, app_module)
    except DetectionError as error:
        print(f"::error::Service descriptor generation halted: {error}")
        print(f"::error::{error.remediation}")
        return 2

    print(f"Detected archetype '{archetype}' from: {', '.join(evidence)}")
    if app_module:
        print(f"Detected application module '{app_module}'")
    if args.check:
        return 0

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(rendered, encoding="utf-8")

    config = descriptor_module.resolve(root, service_name=service_name)
    if not config.valid:
        for error in config.errors:
            print(f"::error::Generated descriptor failed validation: {error.render()}")
        target.unlink(missing_ok=True)
        return 2

    print(f"✅ Generated {descriptor_module.DESCRIPTOR_PATH} (archetype: {archetype}, service: {service_name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
