#!/usr/bin/env python3
"""Resolve and validate the Python build plan for the python-build action.

The action never accepts a raw command line. Every caller input is either a
closed enum, a version string, a dotted module name, a package/extra name, or a
repository-relative path, and each one is validated here before any shell phase
runs. Unvalidated or unknown values fail closed with an actionable message.

Three input conventions apply to every optional input:

* empty string -> convention based auto-detection (skip when nothing is found);
* ``none`` -> explicitly disabled;
* any other value -> used strictly and validated (missing paths are an error).
"""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Mapping, Sequence

try:  # Python 3.11+
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - only on legacy interpreters
    tomllib = None  # type: ignore[assignment]


DISABLED = "none"
REPORTS_DIR = ".spi-build-reports"
DEFAULT_TEST_EXTRA = "dev"
DEFAULT_RUNTIME_EXTRA = "az"
DEFAULT_UNIT_TEST_PATH = "tests/unit"
DEFAULT_SERVICE_TEST_PATH = "tests/service"
DEFAULT_SOURCE_PATH = "src"
SERVICE_MODES = ("in-process", "subprocess")
TOOL_MODES = ("auto", "required", "off")

VERSION_PATTERN = re.compile(r"^\d+\.\d+(\.\d+)?$")
UV_VERSION_PATTERN = re.compile(r"^(\d+\.\d+\.\d+|latest|latest-known)$")
EXTRA_PATTERN = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$")
MODULE_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$")
DISTRIBUTION_PATTERN = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$")
PATH_PATTERN = re.compile(r"^[A-Za-z0-9._][A-Za-z0-9._/-]*$")
PYTEST_FLAG_PATTERN = re.compile(r"^--[A-Za-z0-9][A-Za-z0-9-]*$")
INDEX_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ARTIFACT_SUFFIX_PATTERN = re.compile(r"^(-[A-Za-z0-9][A-Za-z0-9._-]{0,39})?$")

BOOLEAN_TRUE = ("true", "1", "yes", "on")
BOOLEAN_FALSE = ("false", "0", "no", "off", "")


class PlanError(Exception):
    """Raised when a caller input is invalid or a required path is missing."""


@dataclass(frozen=True)
class BuildPlan:
    python_version: str
    uv_version: str
    source_paths: tuple[str, ...]
    format_check_paths: tuple[str, ...]
    package_name: str
    distribution_name: str
    coverage_target: str
    test_extras: tuple[str, ...]
    runtime_extras: tuple[str, ...]
    runtime_import_modules: tuple[str, ...]
    unit_test_path: str
    service_in_process_test_path: str
    service_subprocess_test_path: str
    service_in_process_flag: str
    run_unit_tests: bool
    run_service_in_process: bool
    run_service_subprocess: bool
    generate_coverage: bool
    lint_mode: str
    typecheck_mode: str
    lock_regeneration_script: str
    lock_drift_paths: tuple[str, ...]
    package_build: bool
    index_name: str
    artifact_suffix: str
    reports_dir: str = REPORTS_DIR
    warnings: tuple[str, ...] = field(default=())

    @property
    def run_lock_export_drift(self) -> bool:
        return bool(self.lock_regeneration_script)


def _as_bool(name: str, value: str) -> bool:
    normalized = (value or "").strip().lower()
    if normalized in BOOLEAN_TRUE:
        return True
    if normalized in BOOLEAN_FALSE:
        return False
    raise PlanError(f"{name} must be 'true' or 'false' (received '{value}')")


def _clean(value: str | None) -> str:
    return (value or "").strip()


def _is_disabled(value: str) -> bool:
    return value.lower() == DISABLED


def _split_list(value: str) -> list[str]:
    return [item.strip() for item in value.replace("\n", ",").split(",") if item.strip()]


def _validate_token(name: str, value: str, pattern: re.Pattern[str], hint: str) -> str:
    if not pattern.match(value):
        raise PlanError(f"Invalid {name} '{value}' ({hint})")
    return value


def _validate_relative_path(name: str, value: str, root: Path, must_exist: bool) -> str:
    if not PATH_PATTERN.match(value):
        raise PlanError(
            f"Invalid {name} '{value}' (must be a repository-relative path using "
            "A-Z a-z 0-9 . _ - /)"
        )
    if value.startswith("/") or ".." in Path(value).parts:
        raise PlanError(f"Invalid {name} '{value}' (absolute paths and '..' are not allowed)")
    resolved = (root / value).resolve()
    root_resolved = root.resolve()
    if resolved != root_resolved and root_resolved not in resolved.parents:
        raise PlanError(f"Invalid {name} '{value}' (resolves outside the repository)")
    if must_exist and not resolved.exists():
        raise PlanError(f"{name} '{value}' does not exist in the repository")
    return value


def _read_pyproject(root: Path) -> tuple[dict, list[str]]:
    warnings: list[str] = []
    pyproject = root / "pyproject.toml"
    if not pyproject.is_file():
        raise PlanError("pyproject.toml is required for the python-uv build archetype")
    if tomllib is None:  # pragma: no cover - legacy interpreters only
        warnings.append("tomllib is unavailable; pyproject.toml metadata checks were skipped")
        return {}, warnings
    try:
        with pyproject.open("rb") as stream:
            return tomllib.load(stream), warnings
    except (OSError, ValueError) as error:
        raise PlanError(f"pyproject.toml could not be parsed: {error}") from error


def _declared_extras(pyproject: Mapping) -> set[str]:
    project = pyproject.get("project")
    if not isinstance(project, dict):
        return set()
    optional = project.get("optional-dependencies")
    if not isinstance(optional, dict):
        return set()
    return {str(key) for key in optional}


def _project_name(pyproject: Mapping) -> str:
    project = pyproject.get("project")
    if isinstance(project, dict) and isinstance(project.get("name"), str):
        return str(project["name"]).strip()
    return ""


def _resolve_extras(
    name: str,
    raw: str,
    default_extra: str,
    declared: set[str],
    metadata_known: bool,
    warnings: list[str],
) -> tuple[str, ...]:
    if _is_disabled(raw):
        return ()
    if not raw:
        return (default_extra,) if default_extra in declared else ()
    extras: list[str] = []
    for extra in _split_list(raw):
        _validate_token(name, extra, EXTRA_PATTERN, "extras use PEP 685 names")
        if metadata_known and extra not in declared:
            available = ", ".join(sorted(declared)) or "<none declared>"
            raise PlanError(
                f"{name} '{extra}' is not declared in pyproject.toml "
                f"[project.optional-dependencies] (available: {available})"
            )
        if extra not in extras:
            extras.append(extra)
    if not metadata_known:
        warnings.append(f"{name} could not be verified against pyproject.toml metadata")
    return tuple(extras)


def _resolve_paths(
    name: str,
    raw: str,
    default: str,
    root: Path,
    fallback: str,
) -> tuple[str, ...]:
    if _is_disabled(raw):
        return ()
    if not raw:
        if (root / default).exists():
            return (default,)
        return (fallback,) if fallback else ()
    return tuple(
        _validate_relative_path(name, path, root, must_exist=True) for path in _split_list(raw)
    )


def _default_format_paths(root: Path) -> tuple[str, ...]:
    """Select service-owned roots without sweeping injected `.github/**` tooling."""

    candidates: list[str] = []
    if (root / DEFAULT_SOURCE_PATH).is_dir():
        candidates.append(DEFAULT_SOURCE_PATH)
    else:
        candidates.extend(
            child.name
            for child in sorted(root.iterdir())
            if child.is_dir()
            and (child / "__init__.py").is_file()
            and MODULE_PATTERN.fullmatch(child.name)
        )
    candidates.extend(
        path for path in ("tests", "scripts") if (root / path).is_dir()
    )
    return tuple(dict.fromkeys(candidates)) or (".",)


def _resolve_test_path(name: str, raw: str, default: str, root: Path) -> tuple[str, bool]:
    if _is_disabled(raw):
        return "", False
    if not raw:
        return (default, True) if (root / default).is_dir() else ("", False)
    path = _validate_relative_path(name, raw, root, must_exist=True)
    if not (root / path).is_dir():
        raise PlanError(f"{name} '{raw}' is not a directory")
    return path, True


def _detect_package_name(root: Path, source_paths: Sequence[str], distribution: str) -> str:
    candidates: list[str] = []
    for source in source_paths:
        base = root / source
        if not base.is_dir():
            continue
        for child in sorted(base.iterdir()):
            if (
                child.is_dir()
                and (child / "__init__.py").is_file()
                and MODULE_PATTERN.fullmatch(child.name)
            ):
                candidates.append(child.name)
    unique = sorted(set(candidates))
    if len(unique) == 1:
        return unique[0]
    normalized = re.sub(r"[-.]+", "_", distribution).lower() if distribution else ""
    if normalized and normalized in unique:
        return normalized
    return ""


def _resolve_service_modes(raw: str) -> tuple[bool, bool]:
    if _is_disabled(raw):
        return False, False
    modes = _split_list(raw) or list(SERVICE_MODES)
    for mode in modes:
        if mode not in SERVICE_MODES:
            raise PlanError(
                f"Invalid service_test_modes entry '{mode}' "
                f"(allowed: {', '.join(SERVICE_MODES)}, or '{DISABLED}')"
            )
    return "in-process" in modes, "subprocess" in modes


def _resolve_tool_mode(name: str, raw: str) -> str:
    mode = (raw or "auto").strip().lower()
    if mode not in TOOL_MODES:
        raise PlanError(f"Invalid {name} '{raw}' (allowed: {', '.join(TOOL_MODES)})")
    return mode


def resolve_plan(inputs: Mapping[str, str], root: Path) -> BuildPlan:
    """Validate caller inputs and return the fully resolved build plan."""

    warnings: list[str] = []
    pyproject, metadata_warnings = _read_pyproject(root)
    warnings.extend(metadata_warnings)
    metadata_known = bool(pyproject)
    declared = _declared_extras(pyproject)

    if not (root / "uv.lock").is_file():
        raise PlanError(
            "uv.lock is required for the python-uv build archetype "
            "(run 'uv lock' and commit the lockfile)"
        )

    python_version = _validate_token(
        "python_version",
        _clean(inputs.get("PYTHON_VERSION")) or "3.12",
        VERSION_PATTERN,
        "expected MAJOR.MINOR or MAJOR.MINOR.PATCH",
    )

    uv_version = _clean(inputs.get("UV_VERSION"))
    if uv_version:
        _validate_token(
            "uv_version",
            uv_version,
            UV_VERSION_PATTERN,
            "expected X.Y.Z, 'latest' or 'latest-known'",
        )

    source_paths = _resolve_paths(
        "source_paths",
        _clean(inputs.get("SOURCE_PATHS")),
        DEFAULT_SOURCE_PATH,
        root,
        fallback=".",
    )
    raw_format_paths = _clean(inputs.get("FORMAT_CHECK_PATHS"))
    if _is_disabled(raw_format_paths):
        format_check_paths: tuple[str, ...] = ()
    elif raw_format_paths:
        format_check_paths = tuple(
            _validate_relative_path(
                "format_check_paths", path, root, must_exist=True
            )
            for path in _split_list(raw_format_paths)
        )
    else:
        format_check_paths = _default_format_paths(root)

    distribution_name = _clean(inputs.get("DISTRIBUTION_NAME")) or _project_name(pyproject)
    if distribution_name:
        _validate_token(
            "distribution_name",
            distribution_name,
            DISTRIBUTION_PATTERN,
            "expected a PEP 508 distribution name",
        )

    raw_package = _clean(inputs.get("PACKAGE_NAME"))
    if _is_disabled(raw_package):
        package_name = ""
    elif raw_package:
        package_name = _validate_token(
            "package_name",
            raw_package,
            MODULE_PATTERN,
            "expected a dotted Python import name",
        )
    else:
        package_name = _detect_package_name(root, source_paths, distribution_name)
        if not package_name:
            warnings.append(
                "package_name could not be detected; coverage falls back to the source path"
            )

    test_extras = _resolve_extras(
        "test_extras",
        _clean(inputs.get("TEST_EXTRAS")),
        DEFAULT_TEST_EXTRA,
        declared,
        metadata_known,
        warnings,
    )
    runtime_extras = _resolve_extras(
        "runtime_extras",
        _clean(inputs.get("RUNTIME_EXTRAS")),
        DEFAULT_RUNTIME_EXTRA,
        declared,
        metadata_known,
        warnings,
    )

    raw_modules = _clean(inputs.get("RUNTIME_IMPORT_MODULES"))
    if _is_disabled(raw_modules):
        runtime_import_modules: tuple[str, ...] = ()
    elif raw_modules:
        runtime_import_modules = tuple(
            _validate_token(
                "runtime_import_modules",
                module,
                MODULE_PATTERN,
                "expected dotted Python import names",
            )
            for module in _split_list(raw_modules)
        )
    else:
        runtime_import_modules = (package_name,) if package_name else ()

    unit_test_path, run_unit_tests = _resolve_test_path(
        "unit_test_path",
        _clean(inputs.get("UNIT_TEST_PATH")),
        DEFAULT_UNIT_TEST_PATH,
        root,
    )
    shared_service_path = _clean(inputs.get("SERVICE_TEST_PATH"))
    service_in_process_test_path, in_process_present = _resolve_test_path(
        "service_in_process_test_path",
        _clean(inputs.get("SERVICE_IN_PROCESS_TEST_PATH")) or shared_service_path,
        DEFAULT_SERVICE_TEST_PATH,
        root,
    )
    service_subprocess_test_path, subprocess_present = _resolve_test_path(
        "service_subprocess_test_path",
        _clean(inputs.get("SERVICE_SUBPROCESS_TEST_PATH")) or shared_service_path,
        DEFAULT_SERVICE_TEST_PATH,
        root,
    )
    wants_in_process, wants_subprocess = _resolve_service_modes(
        _clean(inputs.get("SERVICE_TEST_MODES"))
    )

    raw_flag = _clean(inputs.get("SERVICE_IN_PROCESS_FLAG"))
    if _is_disabled(raw_flag):
        service_in_process_flag = ""
    elif not raw_flag:
        service_in_process_flag = "--no-subprocess"
    else:
        service_in_process_flag = _validate_token(
            "service_in_process_flag",
            raw_flag,
            PYTEST_FLAG_PATTERN,
            "expected a single '--flag' token with no value or spaces",
        )

    generate_coverage = _as_bool("generate_coverage", _clean(inputs.get("GENERATE_COVERAGE")))
    coverage_target = package_name or (source_paths[0] if source_paths else ".")

    lint_mode = _resolve_tool_mode("lint_mode", _clean(inputs.get("LINT_MODE")))
    typecheck_mode = _resolve_tool_mode("typecheck_mode", _clean(inputs.get("TYPECHECK_MODE")))

    raw_script = _clean(inputs.get("LOCK_REGENERATION_SCRIPT"))
    if raw_script and not _is_disabled(raw_script):
        if not raw_script.endswith(".sh"):
            raise PlanError(
                f"Invalid lock_regeneration_script '{raw_script}' (must be a '.sh' script)"
            )
        lock_regeneration_script = _validate_relative_path(
            "lock_regeneration_script", raw_script, root, must_exist=True
        )
    else:
        lock_regeneration_script = ""

    raw_drift_paths = _clean(inputs.get("LOCK_DRIFT_PATHS"))
    if _is_disabled(raw_drift_paths):
        lock_drift_paths: tuple[str, ...] = ()
    elif raw_drift_paths:
        lock_drift_paths = tuple(
            _validate_relative_path("lock_drift_paths", path, root, must_exist=False)
            for path in _split_list(raw_drift_paths)
        )
    else:
        lock_drift_paths = tuple(
            candidate
            for candidate in ("uv.lock", "requirements.txt", "requirements_dev.txt")
            if (root / candidate).is_file()
        )

    index_name = _clean(inputs.get("INDEX_NAME"))
    if index_name:
        _validate_token(
            "index_name",
            index_name,
            INDEX_NAME_PATTERN,
            "expected the uv index name declared in pyproject.toml or uv.toml",
        )

    artifact_suffix = _clean(inputs.get("ARTIFACT_SUFFIX"))
    _validate_token(
        "artifact_suffix",
        artifact_suffix,
        ARTIFACT_SUFFIX_PATTERN,
        "expected empty or '-name' using A-Z a-z 0-9 . _ -",
    )

    if not in_process_present and wants_in_process:
        warnings.append(
            "in-process service tests were requested but no test path exists; skipping them"
        )
    if not subprocess_present and wants_subprocess:
        warnings.append(
            "subprocess service tests were requested but no test path exists; skipping them"
        )

    return BuildPlan(
        python_version=python_version,
        uv_version=uv_version,
        source_paths=source_paths,
        format_check_paths=format_check_paths,
        package_name=package_name,
        distribution_name=distribution_name,
        coverage_target=coverage_target,
        test_extras=test_extras,
        runtime_extras=runtime_extras,
        runtime_import_modules=runtime_import_modules,
        unit_test_path=unit_test_path,
        service_in_process_test_path=service_in_process_test_path,
        service_subprocess_test_path=service_subprocess_test_path,
        service_in_process_flag=service_in_process_flag,
        run_unit_tests=run_unit_tests,
        run_service_in_process=in_process_present and wants_in_process,
        run_service_subprocess=subprocess_present and wants_subprocess,
        generate_coverage=generate_coverage,
        lint_mode=lint_mode,
        typecheck_mode=typecheck_mode,
        lock_regeneration_script=lock_regeneration_script,
        lock_drift_paths=lock_drift_paths,
        package_build=_as_bool("package_build", _clean(inputs.get("PACKAGE_BUILD"))),
        index_name=index_name,
        artifact_suffix=artifact_suffix,
        warnings=tuple(warnings),
    )


def _bool_text(value: bool) -> str:
    return "true" if value else "false"


def plan_outputs(plan: BuildPlan) -> list[tuple[str, str]]:
    """Return the ordered GITHUB_OUTPUT key/value pairs for a resolved plan."""

    return [
        ("python_version", plan.python_version),
        ("uv_version", plan.uv_version),
        ("source_paths", ",".join(plan.source_paths)),
        ("format_check_paths", ",".join(plan.format_check_paths)),
        ("package_name", plan.package_name),
        ("distribution_name", plan.distribution_name),
        ("coverage_target", plan.coverage_target),
        ("test_extras", ",".join(plan.test_extras)),
        ("runtime_extras", ",".join(plan.runtime_extras)),
        ("runtime_import_modules", ",".join(plan.runtime_import_modules)),
        ("unit_test_path", plan.unit_test_path),
        ("service_in_process_test_path", plan.service_in_process_test_path),
        ("service_subprocess_test_path", plan.service_subprocess_test_path),
        ("service_in_process_flag", plan.service_in_process_flag),
        ("run_unit_tests", _bool_text(plan.run_unit_tests)),
        ("run_service_in_process", _bool_text(plan.run_service_in_process)),
        ("run_service_subprocess", _bool_text(plan.run_service_subprocess)),
        ("generate_coverage", _bool_text(plan.generate_coverage)),
        ("lint_mode", plan.lint_mode),
        ("typecheck_mode", plan.typecheck_mode),
        ("run_lock_export_drift", _bool_text(plan.run_lock_export_drift)),
        ("lock_regeneration_script", plan.lock_regeneration_script),
        ("lock_drift_paths", ",".join(plan.lock_drift_paths)),
        ("package_build", _bool_text(plan.package_build)),
        ("index_name", plan.index_name),
        ("artifact_suffix", plan.artifact_suffix),
        ("reports_dir", plan.reports_dir),
    ]


def render_plan_summary(plan: BuildPlan) -> str:
    """Render the human-readable plan table written to the job step summary."""

    def phase(enabled: bool, detail: str) -> str:
        return f"{'✅' if enabled else '⏭️'} {detail}"

    in_process_detail = (
        f"{plan.service_in_process_test_path} {plan.service_in_process_flag}".strip()
        if plan.run_service_in_process
        else "skipped"
    )
    subprocess_detail = (
        plan.service_subprocess_test_path if plan.run_service_subprocess else "skipped"
    )
    drift_detail = plan.lock_regeneration_script or "no regeneration script"

    lines = [
        "### 🐍 Python Build Plan",
        "",
        "| Item | Value |",
        "| --- | --- |",
        f"| Python | `{plan.python_version}` |",
        f"| uv | `{plan.uv_version or 'repository required-version'}` |",
        f"| Distribution | `{plan.distribution_name or 'unknown'}` |",
        f"| Import package | `{plan.package_name or 'not detected'}` |",
        f"| Test extras | `{', '.join(plan.test_extras) or 'none'}` |",
        f"| Runtime extras | `{', '.join(plan.runtime_extras) or 'none'}` |",
        f"| Unit tests | {phase(plan.run_unit_tests, plan.unit_test_path or 'skipped')} |",
        f"| Service tests (in-process) | {phase(plan.run_service_in_process, in_process_detail)} |",
        f"| Service tests (subprocess) | {phase(plan.run_service_subprocess, subprocess_detail)} |",
        f"| Coverage | {phase(plan.generate_coverage, plan.coverage_target)} |",
        f"| Lock export drift | {phase(plan.run_lock_export_drift, drift_detail)} |",
        f"| Lint / type check | `{plan.lint_mode}` / `{plan.typecheck_mode}` |",
    ]
    for warning in plan.warnings:
        lines.append("")
        lines.append(f"> ⚠️ {warning}")
    return "\n".join(lines) + "\n"


def write_outputs(pairs: Iterable[tuple[str, str]], destination: Path) -> None:
    with destination.open("a", encoding="utf-8") as stream:
        for key, value in pairs:
            if "\r" in value or "\n" in value:
                raise PlanError(f"Resolved output '{key}' contains a newline")
            stream.write(f"{key}={value}\n")


def main(argv: Sequence[str] | None = None) -> int:
    argv = list(argv if argv is not None else sys.argv[1:])
    root = Path(argv[0]) if argv else Path.cwd()

    try:
        plan = resolve_plan(os.environ, root)
        pairs = plan_outputs(plan)
        output_file = os.environ.get("GITHUB_OUTPUT")
        if output_file:
            write_outputs(pairs, Path(output_file))
    except PlanError as error:
        print(f"::error::{error}")
        return 1

    for warning in plan.warnings:
        print(f"::warning::{warning}")

    summary = render_plan_summary(plan)
    print(summary)
    summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_file:
        with Path(summary_file).open("a", encoding="utf-8") as stream:
            stream.write(summary)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
