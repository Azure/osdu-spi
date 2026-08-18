"""Parser and validator for the fork-owned service descriptor (`.spi/service.yaml`).

The descriptor is service-owned, PR-editable metadata that selects a build
archetype for the copied workflows (ADR-039). Because it is PR-controlled it is
parsed with a deliberately small, strict YAML subset and validated against a
closed schema: unknown keys, unknown archetypes, future schema versions and any
privileged-looking key fail closed.

No third-party modules are used. GitHub runners are only guaranteed to provide
a standard-library Python, so the parser is checked in with the template and
never depends on PyYAML or `yq` being installed.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple


DESCRIPTOR_PATH = ".spi/service.yaml"
SCHEMA_PATH = Path(__file__).with_name("schema.json")
MAX_BYTES = 65536
MAX_LINES = 500
MAX_DEPTH = 6
MAX_ITEMS = 50

_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")
_INT_RE = re.compile(r"^-?[0-9]+$")
_PLAIN_FORBIDDEN_START = set("&*!|>%@`{}[],?")
_PATH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")


class DescriptorError(Exception):
    """Raised when the descriptor cannot be parsed at all."""

    def __init__(self, message: str, line: Optional[int] = None) -> None:
        self.line = line
        super().__init__(f"line {line}: {message}" if line else message)


def configure_stdio() -> None:
    """Make the emoji-bearing CLI output safe on non-UTF-8 consoles."""

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):  # pragma: no cover - stream already fixed
            pass


@dataclass(frozen=True)
class ValidationError:
    """A single schema violation.

    `code` is a stable, value-free identifier so automation (for example the
    settings-apply onboarding issue) can report problems without echoing
    descriptor content.
    """

    path: str
    code: str
    message: str

    def render(self, redact: bool = False) -> str:
        return f"{self.path}: {self.code}" if redact else f"{self.path}: {self.message}"


@dataclass
class ResolvedConfig:
    """Everything the copied workflows are allowed to learn from the descriptor."""

    descriptor_present: bool = False
    valid: bool = True
    schema_version: str = ""
    archetype: str = ""
    service_name: str = ""
    dockerfile_profile: str = ""
    unit_test_type: str = ""
    has_coverage: str = "false"
    build_lane: str = "none"
    lane_implemented: str = "false"
    fallback: str = "none"
    # Python lane inputs. Every value is schema-constrained (closed enum, PEP 508
    # name, dotted module or extras list), so a workflow may pass them straight to
    # the python-build action and the canonical Python image build arguments.
    python_runtime_version: str = ""
    python_distribution: str = ""
    python_import_package: str = ""
    python_test_extras: str = ""
    python_runtime_extras: str = ""
    app_module: str = ""
    errors: List[ValidationError] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)

    def outputs(self) -> Dict[str, str]:
        """The fixed workflow output contract (never arbitrary shell)."""

        return {
            "descriptor_present": "true" if self.descriptor_present else "false",
            "schema_version": self.schema_version,
            "archetype": self.archetype,
            "service_name": self.service_name,
            "dockerfile_profile": self.dockerfile_profile,
            "unit_test_type": self.unit_test_type,
            "has_coverage": self.has_coverage,
            "build_lane": self.build_lane,
            "lane_implemented": self.lane_implemented,
            "fallback": self.fallback,
            "python_runtime_version": self.python_runtime_version,
            "python_distribution": self.python_distribution,
            "python_import_package": self.python_import_package,
            "python_test_extras": self.python_test_extras,
            "python_runtime_extras": self.python_runtime_extras,
            "app_module": self.app_module,
        }

    def to_json_dict(self, redact: bool = False) -> Dict[str, Any]:
        data: Dict[str, Any] = dict(self.outputs())
        data["valid"] = self.valid
        data["errors"] = [error.render(redact=redact) for error in self.errors]
        data["warnings"] = list(self.warnings)
        return data


# ---------------------------------------------------------------------------
# YAML subset parser
# ---------------------------------------------------------------------------


def parse(text: str) -> Dict[str, Any]:
    """Parse the supported YAML subset into plain Python data.

    Supported: block mappings, block sequences of scalars, single-line flow
    sequences of scalars, comments, quoted and plain scalars, booleans and
    integers. Everything else (anchors, aliases, tags, block scalars, multiple
    documents, tabs, nulls) is rejected.
    """

    if len(text.encode("utf-8")) > MAX_BYTES:
        raise DescriptorError("descriptor is larger than 64 KiB")
    if "\t" in text:
        raise DescriptorError("tab characters are not allowed; indent with spaces")

    raw_lines = text.splitlines()
    if len(raw_lines) > MAX_LINES:
        raise DescriptorError("descriptor has more than 500 lines")

    lines: List[Tuple[int, str, int]] = []
    seen_document_start = False
    for number, raw in enumerate(raw_lines, start=1):
        stripped = _strip_comment(raw, number)
        if not stripped.strip():
            continue
        content = stripped.strip()
        if content == "---":
            if seen_document_start or lines:
                raise DescriptorError("multiple YAML documents are not supported", number)
            seen_document_start = True
            continue
        if content == "...":
            raise DescriptorError("document end markers are not supported", number)
        indent = len(stripped) - len(stripped.lstrip(" "))
        if indent % 2 != 0:
            raise DescriptorError("indentation must be a multiple of two spaces", number)
        lines.append((indent, content, number))

    if not lines:
        raise DescriptorError("descriptor is empty")
    if lines[0][0] != 0:
        raise DescriptorError("descriptor must start at column 0", lines[0][2])

    value, index = _parse_block(lines, 0, 0, depth=1)
    if index != len(lines):
        raise DescriptorError("unexpected content after the document", lines[index][2])
    if not isinstance(value, dict):
        raise DescriptorError("descriptor root must be a mapping")
    return value


def _strip_comment(raw: str, number: int) -> str:
    out: List[str] = []
    quote: Optional[str] = None
    for position, char in enumerate(raw):
        if quote:
            out.append(char)
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
            out.append(char)
            continue
        if char == "#" and (position == 0 or raw[position - 1] in " \t"):
            break
        out.append(char)
    if quote:
        raise DescriptorError("unterminated quoted string", number)
    return "".join(out).rstrip()


def _parse_block(
    lines: Sequence[Tuple[int, str, int]], index: int, indent: int, depth: int
) -> Tuple[Any, int]:
    if depth > MAX_DEPTH:
        raise DescriptorError("descriptor nests too deeply", lines[index][2])
    if lines[index][1].startswith("- "):
        return _parse_sequence(lines, index, indent, depth)
    return _parse_mapping(lines, index, indent, depth)


def _parse_mapping(
    lines: Sequence[Tuple[int, str, int]], index: int, indent: int, depth: int
) -> Tuple[Dict[str, Any], int]:
    mapping: Dict[str, Any] = {}
    while index < len(lines):
        line_indent, content, number = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise DescriptorError("unexpected indentation", number)
        if content.startswith("- "):
            raise DescriptorError("unexpected sequence item inside a mapping", number)
        key, separator, remainder = content.partition(":")
        if not separator or not _KEY_RE.match(key.strip()):
            raise DescriptorError(f"invalid mapping key '{content}'", number)
        key = key.strip()
        if key in mapping:
            raise DescriptorError(f"duplicate key '{key}'", number)
        remainder = remainder.strip()
        index += 1
        if remainder:
            mapping[key] = _parse_scalar_or_flow(remainder, number)
            continue
        if index >= len(lines) or lines[index][0] <= line_indent:
            raise DescriptorError(f"key '{key}' has no value", number)
        child_indent = lines[index][0]
        if lines[index][1].startswith("- "):
            if child_indent not in (line_indent, line_indent + 2):
                raise DescriptorError("unexpected indentation", lines[index][2])
        elif child_indent != line_indent + 2:
            raise DescriptorError("unexpected indentation", lines[index][2])
        mapping[key], index = _parse_block(lines, index, child_indent, depth + 1)
    return mapping, index


def _parse_sequence(
    lines: Sequence[Tuple[int, str, int]], index: int, indent: int, depth: int
) -> Tuple[List[Any], int]:
    items: List[Any] = []
    while index < len(lines):
        line_indent, content, number = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent or not content.startswith("- "):
            raise DescriptorError("unexpected indentation in sequence", number)
        item = content[2:].strip()
        if not item:
            raise DescriptorError("sequence item has no value", number)
        if ":" in item and not (item.startswith('"') or item.startswith("'")):
            raise DescriptorError("sequences of mappings are not supported", number)
        items.append(_parse_scalar_or_flow(item, number))
        if len(items) > MAX_ITEMS:
            raise DescriptorError("sequence has more than 50 items", number)
        index += 1
    return items, index


def _parse_scalar_or_flow(raw: str, number: int) -> Any:
    if raw.startswith("["):
        if not raw.endswith("]"):
            raise DescriptorError("unterminated flow sequence", number)
        inner = raw[1:-1].strip()
        if not inner:
            raise DescriptorError("empty sequences are not allowed", number)
        items = [_parse_scalar(part.strip(), number) for part in inner.split(",")]
        if len(items) > MAX_ITEMS:
            raise DescriptorError("sequence has more than 50 items", number)
        return items
    return _parse_scalar(raw, number)


def _parse_scalar(raw: str, number: int) -> Any:
    if not raw:
        raise DescriptorError("empty value", number)
    if raw[0] == '"':
        return _parse_double_quoted(raw, number)
    if raw[0] == "'":
        return _parse_single_quoted(raw, number)
    if raw in ("true", "false"):
        return raw == "true"
    if raw in ("null", "~", "Null", "NULL", "True", "False", "yes", "no", "on", "off"):
        raise DescriptorError(
            f"'{raw}' is not a supported value; use true/false or quote the string",
            number,
        )
    if _INT_RE.match(raw):
        return int(raw)
    if raw[0] in _PLAIN_FORBIDDEN_START:
        raise DescriptorError("anchors, tags and block scalars are not supported", number)
    if re.match(r"^-?[0-9]+\.[0-9]", raw):
        raise DescriptorError(
            f"'{raw}' looks like a number; quote version-like values", number
        )
    if ": " in raw or raw.endswith(":"):
        raise DescriptorError("inline mappings are not supported", number)
    return raw


def _parse_double_quoted(raw: str, number: int) -> str:
    if len(raw) < 2 or not raw.endswith('"'):
        raise DescriptorError("unterminated quoted string", number)
    body = raw[1:-1]
    if "\\" in body.replace('\\"', "").replace("\\\\", ""):
        raise DescriptorError("escape sequences are not supported", number)
    return body.replace('\\"', '"').replace("\\\\", "\\")


def _parse_single_quoted(raw: str, number: int) -> str:
    if len(raw) < 2 or not raw.endswith("'"):
        raise DescriptorError("unterminated quoted string", number)
    return raw[1:-1].replace("''", "'")


# ---------------------------------------------------------------------------
# Schema validation
# ---------------------------------------------------------------------------


def load_schema(path: Optional[Path] = None) -> Dict[str, Any]:
    return json.loads((path or SCHEMA_PATH).read_text(encoding="utf-8"))


def validate(document: Dict[str, Any], schema: Optional[Dict[str, Any]] = None) -> List[ValidationError]:
    """Validate a parsed descriptor. An empty result means the descriptor is usable."""

    schema = schema or load_schema()
    errors: List[ValidationError] = []

    forbidden = {key.lower() for key in schema.get("forbiddenKeys", [])}
    _check_forbidden(document, "", forbidden, errors)

    version = document.get("schemaVersion")
    supported = schema.get("supportedSchemaVersions", [])
    deprecated = schema.get("deprecatedSchemaVersions", [])
    if version is None:
        errors.append(ValidationError("schemaVersion", "missing-key", "schemaVersion is required"))
    elif isinstance(version, bool) or not isinstance(version, int):
        errors.append(
            ValidationError("schemaVersion", "invalid-type", "schemaVersion must be an integer")
        )
    elif version not in supported and version not in deprecated:
        errors.append(
            ValidationError(
                "schemaVersion",
                "unsupported-schema-version",
                f"schemaVersion {version} is not supported by this template version "
                f"(supported: {', '.join(str(item) for item in supported)})",
            )
        )

    archetype = ""
    service = document.get("service")
    if isinstance(service, dict) and isinstance(service.get("archetype"), str):
        archetype = service["archetype"]

    _validate_mapping(document, schema["properties"], "", archetype, schema, errors)

    if not errors:
        errors.extend(_validate_consistency(document, archetype, schema))
    return errors


def _check_forbidden(
    node: Any, path: str, forbidden: Sequence[str], errors: List[ValidationError]
) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            child = f"{path}.{key}" if path else key
            if key.lower() in forbidden:
                errors.append(
                    ValidationError(
                        child,
                        "forbidden-key",
                        "privileged configuration is not allowed in the service descriptor",
                    )
                )
            _check_forbidden(value, child, forbidden, errors)


def _validate_mapping(
    node: Any,
    properties: Dict[str, Any],
    path: str,
    archetype: str,
    schema: Dict[str, Any],
    errors: List[ValidationError],
) -> None:
    if not isinstance(node, dict):
        errors.append(ValidationError(path or "<root>", "invalid-type", "expected a mapping"))
        return

    for key, value in node.items():
        child_path = f"{path}.{key}" if path else key
        rule = properties.get(key)
        if rule is None:
            errors.append(
                ValidationError(child_path, "unknown-key", f"'{key}' is not part of the schema")
            )
            continue
        rule = _resolve_ref(rule, schema)
        allowed = rule.get("archetypes")
        if allowed and archetype and archetype not in allowed:
            errors.append(
                ValidationError(
                    child_path,
                    "archetype-mismatch",
                    f"'{key}' is only valid for archetypes: {', '.join(allowed)}",
                )
            )
            continue
        _validate_value(value, rule, child_path, archetype, schema, errors)

    for key, rule in properties.items():
        if _resolve_ref(rule, schema).get("required") and key not in node:
            child_path = f"{path}.{key}" if path else key
            errors.append(ValidationError(child_path, "missing-key", f"'{key}' is required"))


def _resolve_ref(rule: Dict[str, Any], schema: Dict[str, Any]) -> Dict[str, Any]:
    ref = rule.get("$ref")
    if not ref:
        return rule
    resolved = dict(schema.get("definitions", {})[ref])
    resolved.update({key: value for key, value in rule.items() if key != "$ref"})
    return resolved


def _validate_value(
    value: Any,
    rule: Dict[str, Any],
    path: str,
    archetype: str,
    schema: Dict[str, Any],
    errors: List[ValidationError],
) -> None:
    expected = rule.get("type")

    if expected == "mapping":
        _validate_mapping(value, rule.get("properties", {}), path, archetype, schema, errors)
        return

    if expected == "list":
        if not isinstance(value, list):
            errors.append(ValidationError(path, "invalid-type", "expected a list"))
            return
        if not value:
            errors.append(ValidationError(path, "empty-list", "list must not be empty"))
            return
        for position, item in enumerate(value):
            _validate_value(item, rule["items"], f"{path}[{position}]", archetype, schema, errors)
        return

    if expected == "integer":
        if isinstance(value, bool) or not isinstance(value, int):
            errors.append(ValidationError(path, "invalid-type", "expected an integer"))
        return

    if expected == "coverage":
        allowed = schema.get("coverageValues", [])
        if isinstance(value, bool):
            return
        if not isinstance(value, str) or value not in allowed:
            errors.append(
                ValidationError(
                    path,
                    "invalid-value",
                    f"coverage must be true/false or one of: {', '.join(allowed)}",
                )
            )
        return

    if expected == "path":
        if not isinstance(value, str):
            errors.append(ValidationError(path, "invalid-type", "expected a string path"))
            return
        if len(value) > rule.get("maxLength", 120):
            errors.append(ValidationError(path, "too-long", "path is too long"))
            return
        # fullmatch, not match: Python's '$' also matches before a trailing newline, and
        # these values are written to $GITHUB_OUTPUT and build arguments.
        if value.startswith("/") or ".." in value.split("/") or not _PATH_RE.fullmatch(value):
            errors.append(
                ValidationError(
                    path,
                    "invalid-path",
                    "path must be relative, free of '..' and limited to [A-Za-z0-9._/-]",
                )
            )
        return

    if expected == "string":
        if not isinstance(value, str):
            errors.append(ValidationError(path, "invalid-type", "expected a string"))
            return
        if "enum" in rule and value not in rule["enum"]:
            errors.append(
                ValidationError(
                    path,
                    "invalid-value",
                    f"'{value}' is not one of: {', '.join(rule['enum'])}",
                )
            )
            return
        if "pattern" in rule and not re.fullmatch(rule["pattern"], value):
            errors.append(
                ValidationError(path, "invalid-value", f"'{value}' does not match {rule['pattern']}")
            )
        if "maxLength" in rule and len(value) > rule["maxLength"]:
            errors.append(ValidationError(path, "too-long", "value is too long"))
        return

    errors.append(ValidationError(path, "schema-error", f"unsupported schema type '{expected}'"))


def _lookup(document: Dict[str, Any], dotted: str) -> Any:
    """Return the value at a dotted descriptor path, or None when absent."""

    node: Any = document
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def _validate_consistency(
    document: Dict[str, Any], archetype: str, schema: Dict[str, Any]
) -> List[ValidationError]:
    errors: List[ValidationError] = []
    archetype_rule = schema["archetypes"].get(archetype)
    if not archetype_rule:
        return errors

    defaults = archetype_rule["defaults"]
    profile = document.get("container", {}).get("dockerfileProfile")
    if profile and profile != defaults["dockerfileProfile"]:
        errors.append(
            ValidationError(
                "container.dockerfileProfile",
                "profile-mismatch",
                f"archetype '{archetype}' requires the '{defaults['dockerfileProfile']}' Dockerfile profile",
            )
        )

    # Archetype-conditional required keys. The Python image bakes its uvicorn target at
    # build time (the Stack chart cannot override a container command), so a Python
    # descriptor without `container.appModule` would produce an unstartable image; it is
    # rejected here rather than at container start.
    for dotted in archetype_rule.get("requiredKeys", []):
        if _lookup(document, dotted) is None:
            errors.append(
                ValidationError(
                    dotted,
                    "missing-key",
                    f"archetype '{archetype}' requires '{dotted}'",
                )
            )

    allowed_test_types = {defaults["unitTestType"], "postman"}
    for suite, definition in document.get("tests", {}).items():
        suite_type = definition.get("type") if isinstance(definition, dict) else None
        if suite_type and suite_type not in allowed_test_types:
            errors.append(
                ValidationError(
                    f"tests.{suite}.type",
                    "test-type-mismatch",
                    f"archetype '{archetype}' supports test types: {', '.join(sorted(allowed_test_types))}",
                )
            )
    return errors


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------


def java_markers_present(root: Path) -> bool:
    """Legacy Java inference: the same signal the copied workflows used before ADR-039."""

    excluded = {".git", ".venv", "node_modules", "target"}
    return any(not excluded.intersection(path.relative_to(root).parts) for path in root.rglob("pom.xml"))


def resolve(
    root: Path,
    service_name: str = "",
    schema: Optional[Dict[str, Any]] = None,
    descriptor_path: str = DESCRIPTOR_PATH,
) -> ResolvedConfig:
    """Read, validate and resolve the descriptor for a checked-out repository."""

    schema = schema or load_schema()
    config = ResolvedConfig(service_name=service_name)
    path = root / descriptor_path

    if not path.is_file():
        config.descriptor_present = False
        if java_markers_present(root):
            config.build_lane = "java"
            config.lane_implemented = "true"
            config.archetype = ""
            config.dockerfile_profile = "java"
            config.unit_test_type = "maven"
            config.has_coverage = "true"
            config.fallback = "java-inference"
            config.warnings.append(
                f"No {descriptor_path} found; using legacy Java inference. "
                "Add a service descriptor to make the build archetype explicit (ADR-039)."
            )
        else:
            config.warnings.append(
                f"No {descriptor_path} and no Maven project markers found; no build lane selected."
            )
        return config

    config.descriptor_present = True
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        config.valid = False
        config.errors.append(
            ValidationError(descriptor_path, "invalid-encoding", "descriptor must be UTF-8")
        )
        return config

    try:
        document = parse(text)
    except DescriptorError as error:
        config.valid = False
        config.errors.append(ValidationError(descriptor_path, "parse-error", str(error)))
        return config

    errors = validate(document, schema)
    if errors:
        config.valid = False
        config.errors = errors
        return config

    service = document["service"]
    archetype = service["archetype"]
    archetype_rule = schema["archetypes"][archetype]
    defaults = archetype_rule["defaults"]

    config.schema_version = str(document["schemaVersion"])
    config.archetype = archetype
    config.service_name = service["name"]
    config.build_lane = archetype_rule["lane"]
    config.lane_implemented = "true" if archetype_rule.get("laneImplemented") else "false"
    config.dockerfile_profile = document.get("container", {}).get(
        "dockerfileProfile", defaults["dockerfileProfile"]
    )

    unit = document.get("tests", {}).get("unit", {})
    config.unit_test_type = unit.get("type", defaults["unitTestType"])
    coverage = unit.get("coverage", defaults["coverage"])
    config.has_coverage = "false" if coverage in (False, "none") else "true"

    if config.build_lane == "python":
        python = document.get("build", {}).get("python", {})
        config.python_runtime_version = python.get(
            "runtimeVersion", defaults.get("runtimeVersion", "")
        )
        config.python_distribution = python.get("distribution", "")
        config.python_import_package = python.get("importPackage", "")
        # Lists are joined with commas: the python-build action and the canonical image
        # both take comma-separated extras, and every entry is pattern-validated above.
        config.python_test_extras = ",".join(python.get("testExtras", []))
        config.python_runtime_extras = ",".join(python.get("runtimeExtras", []))
        config.app_module = document.get("container", {}).get("appModule", "")

    if document["schemaVersion"] in schema.get("deprecatedSchemaVersions", []):
        config.warnings.append(
            f"schemaVersion {document['schemaVersion']} is deprecated; migrate to "
            f"{max(schema['supportedSchemaVersions'])}."
        )
    if config.lane_implemented != "true":
        config.warnings.append(
            f"Archetype '{archetype}' has no build lane in this template version; "
            "the required Docker Build check fails closed until the lane is installed."
        )
    return config
