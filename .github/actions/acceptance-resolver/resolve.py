#!/usr/bin/env python3
"""Acceptance resolver engine.

Joins the fork-owned service descriptor (.spi/service.yaml, schema v3) with
the stack's facts envelope (spi info --json, apiVersion spi.osdu.dev/v1) and
caller-supplied Key Vault secret values into the environment map an acceptance
suite runs with.

Contract: README.md beside this file. Standard library only. Never calls
Azure or the cluster: facts and secret values arrive as files.
Deterministic: sorted output, no timestamps.

Exit codes:
  0  resolved (bind mode may carry warnings)
  2  descriptor contract violation -- the engine refuses to guess
  3  environment not ready (run mode: a required answer is missing)
  4  infra error (facts contract, agreement mismatch, unsafe value)
"""

import argparse
import json
import os
import re
import sys

ENGINE_VERSION = "1.0.0"
REPORT_SCHEMA = 1

FACTS_API_VERSION = "spi.osdu.dev/v1"

ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,127}$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
GROUP_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._@-]{0,254}$")
SECRET_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,126}$")
SUFFIX_RE = re.compile(r"^[A-Za-z0-9._~:/@+-]{1,200}$")
MAVEN_ARG_RE = re.compile(r"^[^\s\x00-\x1f\x7f]{1,240}$")
PATH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,119}$")
TEMPLATE_REF_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]{0,127})\}")
KEYVAULT_SOURCE_RE = re.compile(r"^keyvault:([A-Za-z0-9][A-Za-z0-9-]{0,126})$")

FACT_SOURCES = ("gateway", "partition", "openid", "tenant", "legalTag")
VALUE_SOURCES = ("static", "template")
SOURCE_VOCABULARY = FACT_SOURCES + VALUE_SOURCES + ("user", "keyvault:<name>")

# Envelope location per fact kind. `partition` and `legalTag` read the
# primary entry of the partitions list (legal tags are partition-scoped).
# openid is the OIDC v2.0 issuer URL, published explicitly by the stack --
# never derived from tenant_id here. openid and legalTag are agreed with the
# stack (osdu-spi-stack#131) but not yet published; until then they resolve
# as env-not-ready.
FACT_PATHS = {
    "gateway": ("base_url",),
    "openid": ("azure", "openid_issuer"),
    "tenant": ("azure", "tenant_id"),
}
PARTITION_FACT_KEYS = {"partition": "name", "legalTag": "legal_tag"}
VAULT_NAME_PATH = ("azure", "keyvault")

RESERVED_ENV_NAMES = frozenset({
    "AZURE_CLIENT_ID",
    "AZURE_FEDERATED_TOKEN_FILE",
    "AZURE_SUBSCRIPTION_ID",
    "AZURE_TENANT_ID",
    "BASH_ENV",
    "ENV",
    "HOME",
    "JAVA_TOOL_OPTIONS",
    "LD_LIBRARY_PATH",
    "LD_PRELOAD",
    "MAVEN_OPTS",
    "OLDPWD",
    "PATH",
    "PWD",
    "PYTHONPATH",
    "SHELL",
})
RESERVED_ENV_PREFIXES = ("ACTIONS_", "GITHUB_", "RUNNER_", "SPI_STACK_")


class Halt(Exception):
    """Exit 2: the descriptor violates the contract; the engine refuses to guess."""

    def __init__(self, code, detail):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


class EnvNotReady(Exception):
    """Exit 3: a required answer is missing from the environment."""

    def __init__(self, detail):
        super().__init__(f"ENV_NOT_READY: {detail}")
        self.code = "ENV_NOT_READY"
        self.detail = detail


class Infra(Exception):
    """Exit 4: the environment gave a broken or contradictory answer."""

    def __init__(self, code, detail):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


# ---------------------------------------------------------------------------
# Descriptor YAML subset
#
# Same posture as the upstream filter's config reader: a fixed-schema dialect,
# parsed by hand so the engine stays standard-library only. Block mappings,
# block lists of scalars, one level of flow mapping/list, quoted or plain
# scalars, comments. No anchors, no multi-line scalars, no tabs.

def _strip_inline_comment(value):
    # YAML rules: an inline comment's '#' must be preceded by whitespace (or
    # start the value) and must sit outside any quoted scalar.
    quote = ""
    for i, ch in enumerate(value):
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or value[i - 1] in " \t"):
            return value[:i]
    return value


def _scalar(text, line_no):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        return text[1:-1]
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?[0-9]+", text):
        return int(text)
    for forbidden in ("{", "}", "[", "]", "&", "*", "#"):
        if forbidden in text:
            raise Halt("DESCRIPTOR_INVALID",
                       f"line {line_no}: unquoted scalar contains '{forbidden}'")
    return text


def _split_flow_items(body, line_no):
    items, depth, quote, start = [], 0, "", 0
    for i, ch in enumerate(body):
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "'\"":
            quote = ch
        elif ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        elif ch == "," and depth == 0:
            items.append(body[start:i])
            start = i + 1
    if quote or depth:
        raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: unterminated flow value")
    items.append(body[start:])
    return [item for item in (piece.strip() for piece in items) if item]


def _flow_value(text, line_no):
    text = text.strip()
    if text.startswith("{"):
        if not text.endswith("}"):
            raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: unterminated flow mapping")
        result = {}
        for item in _split_flow_items(text[1:-1], line_no):
            m = re.match(r"^([A-Za-z0-9_.-]+):\s*(.*)$", item)
            if not m:
                raise Halt("DESCRIPTOR_INVALID",
                           f"line {line_no}: expected 'key: value' inside flow mapping")
            key = m.group(1)
            if key in result:
                raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: duplicate key '{key}'")
            result[key] = _flow_value(m.group(2), line_no)
        return result
    if text.startswith("["):
        if not text.endswith("]"):
            raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: unterminated flow list")
        return [_flow_value(item, line_no) for item in _split_flow_items(text[1:-1], line_no)]
    return _scalar(text, line_no)


def parse_descriptor_yaml(text):
    lines = []
    for idx, raw in enumerate(text.split("\n"), start=1):
        if "\t" in raw[:len(raw) - len(raw.lstrip())]:
            raise Halt("DESCRIPTOR_INVALID", f"line {idx}: tab indentation")
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        lines.append((idx, indent, raw.strip()))

    def parse_block(pos, indent):
        entries, kind = {}, None
        items = []
        while pos < len(lines):
            line_no, line_indent, body = lines[pos]
            if line_indent < indent:
                break
            if line_indent > indent:
                raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: unexpected indentation")
            if body.startswith("- "):
                if kind == "map":
                    raise Halt("DESCRIPTOR_INVALID",
                               f"line {line_no}: list entry inside a mapping block")
                kind = "list"
                items.append(_flow_value(_strip_inline_comment(body[2:]), line_no))
                pos += 1
                continue
            m = re.match(r"^([A-Za-z0-9_.-]+):(.*)$", body)
            if not m:
                raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: expected 'key:' form")
            if kind == "list":
                raise Halt("DESCRIPTOR_INVALID",
                           f"line {line_no}: mapping entry inside a list block")
            kind = "map"
            key = m.group(1)
            if key in entries:
                raise Halt("DESCRIPTOR_INVALID", f"line {line_no}: duplicate key '{key}'")
            rest = _strip_inline_comment(m.group(2)).strip()
            pos += 1
            if rest:
                entries[key] = _flow_value(rest, line_no)
            else:
                if pos < len(lines) and lines[pos][1] > indent:
                    entries[key], pos = parse_block(pos, lines[pos][1])
                else:
                    entries[key] = {}
        return (items if kind == "list" else entries), pos

    if not lines:
        raise Halt("DESCRIPTOR_INVALID", "descriptor is empty")
    if lines[0][1] != 0:
        raise Halt("DESCRIPTOR_INVALID", f"line {lines[0][0]}: top level must not be indented")
    value, pos = parse_block(0, 0)
    if pos != len(lines):
        raise Halt("DESCRIPTOR_INVALID", f"line {lines[pos][0]}: unexpected indentation")
    if not isinstance(value, dict):
        raise Halt("DESCRIPTOR_INVALID", "descriptor top level must be a mapping")
    return value


# ---------------------------------------------------------------------------
# Descriptor validation (schema v3)

def _require_keys(mapping, allowed, required, where):
    unknown = sorted(set(mapping) - set(allowed))
    if unknown:
        raise Halt("UNKNOWN_KEY", f"{where}.{unknown[0]} is not part of schema v3")
    for key in required:
        if key not in mapping:
            raise Halt("MISSING_KEY", f"{where}.{key} is required")


def _string_field(mapping, key, where, pattern=None):
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise Halt("DESCRIPTOR_INVALID", f"{where}.{key} must be a non-empty string")
    if pattern and not pattern.fullmatch(value):
        raise Halt("DESCRIPTOR_INVALID", f"{where}.{key} is not valid: {value}")
    return value


def _env_name(name, where):
    if not isinstance(name, str) or not ENV_NAME_RE.fullmatch(name):
        raise Halt("DESCRIPTOR_INVALID", f"{where}: '{name}' is not an environment variable name")
    if name in RESERVED_ENV_NAMES or name.startswith(RESERVED_ENV_PREFIXES):
        raise Halt("RESERVED_ENV_NAME", f"{where}: '{name}' is a reserved environment variable name")
    return name


def _slug_list(value, where, pattern, label):
    if value == {}:
        value = []
    if not isinstance(value, list):
        raise Halt("DESCRIPTOR_INVALID", f"{where} must be a list")
    for item in value:
        if not isinstance(item, str) or not pattern.fullmatch(item):
            raise Halt("DESCRIPTOR_INVALID", f"{where}: '{item}' is not a {label}")
    return value


def _validate_binding(name, binding, where):
    if not isinstance(binding, dict):
        raise Halt("DESCRIPTOR_INVALID", f"{where} must be a mapping")
    _require_keys(binding, ("source", "suffix", "value", "default"), ("source",), where)
    source = binding["source"]
    if not isinstance(source, str):
        raise Halt("DESCRIPTOR_INVALID", f"{where}.source must be a string")

    keyvault = KEYVAULT_SOURCE_RE.fullmatch(source)
    if source not in FACT_SOURCES + VALUE_SOURCES + ("user",) and not keyvault:
        raise Halt(
            "UNKNOWN_SOURCE",
            f"{where}.source '{source}' is not in the source vocabulary: "
            + " | ".join(SOURCE_VOCABULARY),
        )

    if "suffix" in binding:
        if source not in FACT_SOURCES:
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}.suffix is only valid for fact sources")
        if not isinstance(binding["suffix"], str) or not SUFFIX_RE.fullmatch(binding["suffix"]):
            raise Halt("DESCRIPTOR_INVALID", f"{where}.suffix is not valid")

    if source in VALUE_SOURCES:
        if "value" not in binding:
            raise Halt("MISSING_KEY", f"{where}.value is required for source {source}")
        if not isinstance(binding["value"], str) or binding["value"] == "":
            raise Halt("DESCRIPTOR_INVALID", f"{where}.value must be a non-empty string")
    elif "value" in binding:
        raise Halt("DESCRIPTOR_INVALID",
                   f"{where}.value is only valid for sources static and template")

    if "default" in binding:
        if keyvault:
            # A default for a secret would put a secret value in the repository.
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}.default is not valid for keyvault sources")
        if source in VALUE_SOURCES:
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}.default is not valid for source {source}")
        if not isinstance(binding["default"], str):
            raise Halt("DESCRIPTOR_INVALID", f"{where}.default must be a string")

    if source == "template":
        refs = TEMPLATE_REF_RE.findall(binding["value"])
        if not refs:
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}.value has no ${{NAME}} reference; use source static")
    return source


def validate_descriptor(data):
    _require_keys(data, ("schemaVersion", "service", "tests"),
                  ("schemaVersion", "service", "tests"), "descriptor")
    version = data["schemaVersion"]
    if version != 3:
        raise Halt("UNSUPPORTED_SCHEMA_VERSION",
                   f"descriptor.schemaVersion {version!r} is not supported; this engine reads 3")

    service = data["service"]
    if not isinstance(service, dict):
        raise Halt("DESCRIPTOR_INVALID", "descriptor.service must be a mapping")
    _require_keys(service, ("name", "archetype", "description"), ("name", "archetype"),
                  "descriptor.service")
    _string_field(service, "name", "descriptor.service", SLUG_RE)
    archetype = _string_field(service, "archetype", "descriptor.service")
    if archetype != "java-maven-azure":
        raise Halt("DESCRIPTOR_INVALID",
                   "descriptor.service.archetype must be java-maven-azure")

    tests = data["tests"]
    if not isinstance(tests, dict):
        raise Halt("DESCRIPTOR_INVALID", "descriptor.tests must be a mapping")
    _require_keys(tests, ("acceptance",), ("acceptance",), "descriptor.tests")
    acceptance = tests["acceptance"]
    if not isinstance(acceptance, dict):
        raise Halt("DESCRIPTOR_INVALID", "descriptor.tests.acceptance must be a mapping")
    where = "descriptor.tests.acceptance"
    _require_keys(
        acceptance,
        ("type", "path", "mavenArguments", "bindings", "keyVaultBindings",
         "requires", "dependencies", "timeoutMinutes"),
        ("type", "path"),
        where,
    )
    if acceptance["type"] != "maven":
        raise Halt("DESCRIPTOR_INVALID", f"{where}.type must be maven")
    path = _string_field(acceptance, "path", where, PATH_RE)
    if ".." in path.split("/"):
        raise Halt("DESCRIPTOR_INVALID", f"{where}.path must stay inside the repository")

    maven_arguments = acceptance.get("mavenArguments", ["verify"])
    if not isinstance(maven_arguments, list) or not maven_arguments:
        raise Halt("DESCRIPTOR_INVALID", f"{where}.mavenArguments must be a non-empty list")
    for position, argument in enumerate(maven_arguments):
        if not isinstance(argument, str) or not MAVEN_ARG_RE.fullmatch(argument):
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}.mavenArguments[{position}] must be one argv token "
                       "with no whitespace")

    bindings = acceptance.get("bindings", {})
    if not isinstance(bindings, dict):
        raise Halt("DESCRIPTOR_INVALID", f"{where}.bindings must be a mapping")
    sources = {}
    for name, binding in bindings.items():
        _env_name(name, f"{where}.bindings")
        sources[name] = _validate_binding(name, binding, f"{where}.bindings.{name}")

    for name, binding in bindings.items():
        if sources[name] != "template":
            continue
        for ref in TEMPLATE_REF_RE.findall(binding["value"]):
            if ref not in sources:
                raise Halt("TEMPLATE_REF",
                           f"{where}.bindings.{name} references undeclared binding '{ref}'")
            if sources[ref] == "template":
                raise Halt("TEMPLATE_REF",
                           f"{where}.bindings.{name} references template binding '{ref}'; "
                           "templates may only reference non-template bindings")
            if KEYVAULT_SOURCE_RE.fullmatch(sources[ref]):
                raise Halt("TEMPLATE_REF",
                           f"{where}.bindings.{name} references secret binding '{ref}'; "
                           "secrets stay leaf values")

    key_vault_bindings = acceptance.get("keyVaultBindings", {})
    if not isinstance(key_vault_bindings, dict):
        raise Halt("DESCRIPTOR_INVALID", f"{where}.keyVaultBindings must be a mapping")
    for name, secret in key_vault_bindings.items():
        _env_name(name, f"{where}.keyVaultBindings")
        if name in bindings:
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}: '{name}' is declared in both bindings and keyVaultBindings")
        if not isinstance(secret, str) or not SECRET_NAME_RE.fullmatch(secret):
            raise Halt("DESCRIPTOR_INVALID",
                       f"{where}.keyVaultBindings.{name} must be a Key Vault secret name")

    requires = acceptance.get("requires", {})
    if not isinstance(requires, dict):
        raise Halt("DESCRIPTOR_INVALID", f"{where}.requires must be a mapping")
    _require_keys(requires, ("loads", "groups"), (), f"{where}.requires")
    requires = {
        "loads": _slug_list(requires.get("loads", []), f"{where}.requires.loads",
                            SLUG_RE, "load name"),
        "groups": _slug_list(requires.get("groups", []), f"{where}.requires.groups",
                             GROUP_RE, "group name"),
    }

    dependencies = _slug_list(acceptance.get("dependencies", []),
                              f"{where}.dependencies", SLUG_RE, "service slug")

    timeout = acceptance.get("timeoutMinutes", 25)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1 <= timeout <= 180:
        raise Halt("DESCRIPTOR_INVALID", f"{where}.timeoutMinutes must be between 1 and 180")

    return {
        "service": service["name"],
        "test_type": acceptance["type"],
        "test_dir": path,
        "maven_arguments": maven_arguments,
        "bindings": bindings,
        "sources": sources,
        "key_vault_bindings": key_vault_bindings,
        "requires": requires,
        "dependencies": dependencies,
        "timeout_minutes": timeout,
    }


# ---------------------------------------------------------------------------
# Facts

def load_facts(path):
    try:
        with open(path, encoding="utf-8") as stream:
            facts = json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        raise Infra("FACTS_UNREADABLE", f"{path}: {error}")
    if not isinstance(facts, dict):
        raise Infra("FACTS_UNREADABLE", f"{path}: envelope is not a JSON object")
    api_version = facts.get("apiVersion", "")
    if api_version != FACTS_API_VERSION:
        raise Infra("FACTS_API_VERSION",
                    f"facts envelope declares {api_version!r}; this engine reads "
                    f"{FACTS_API_VERSION!r}")
    return facts


def _fact_at(facts, path):
    node = facts
    for key in path:
        if not isinstance(node, dict) or key not in node:
            return ""
        node = node[key]
    return node if isinstance(node, str) else ""


def fact_value(facts, kind):
    if kind in PARTITION_FACT_KEYS:
        partitions = facts.get("partitions")
        if not isinstance(partitions, list):
            return ""
        for entry in partitions:
            if isinstance(entry, dict) and entry.get("primary"):
                value = entry.get(PARTITION_FACT_KEYS[kind])
                return value.strip() if isinstance(value, str) else ""
        return ""
    return _fact_at(facts, FACT_PATHS[kind]).strip()


# ---------------------------------------------------------------------------
# Resolution

def _check_value_safe(name, value):
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in value):
        raise Infra("UNSAFE_VALUE",
                    f"resolved value for {name} contains a control character; "
                    "an env file cannot carry it")


def check_agreement(facts, expect_gateway, expect_partition):
    checks = []
    pairs = (
        ("gateway", expect_gateway, fact_value(facts, "gateway")),
        ("partition", expect_partition, fact_value(facts, "partition")),
    )
    for kind, expected, published in pairs:
        if not expected or not published:
            continue
        left, right = expected, published
        if kind == "gateway":
            left, right = left.rstrip("/"), right.rstrip("/")
        if left != right:
            raise Infra("AGREEMENT_MISMATCH",
                        f"caller and facts disagree on {kind}: "
                        f"caller says {expected!r}, facts say {published!r}")
        checks.append(kind)
    return checks


def resolve(contract, facts, secrets, environ):
    resolved = {}
    missing = []

    def miss(name, reason):
        missing.append({"name": name, "reason": reason})

    ordered = sorted(contract["bindings"])
    for name in ordered:
        if contract["sources"][name] == "template":
            continue
        binding = contract["bindings"][name]
        source = contract["sources"][name]
        override = environ.get(name, "")
        if override:
            resolved[name] = override
            continue
        keyvault = KEYVAULT_SOURCE_RE.fullmatch(source)
        if keyvault:
            # kv_name is the vault entry's NAME from the descriptor, never a value.
            kv_name = keyvault.group(1)
            if kv_name in secrets:
                resolved[name] = secrets[kv_name]
            else:
                miss(name, f"Key Vault secret '{kv_name}' was not supplied")
        elif source == "static":
            resolved[name] = binding["value"]
        elif source == "user":
            if "default" in binding:
                resolved[name] = binding["default"]
            else:
                miss(name, "source user: the caller must set this variable")
        else:
            base = fact_value(facts, source)
            if base:
                if source == "gateway":
                    base = base.rstrip("/")
                resolved[name] = base + binding.get("suffix", "")
            elif "default" in binding:
                resolved[name] = binding["default"]
            else:
                miss(name, f"fact '{source}' is not published by this environment")

    for name in ordered:
        if contract["sources"][name] != "template":
            continue
        override = environ.get(name, "")
        if override:
            resolved[name] = override
            continue
        value = contract["bindings"][name]["value"]
        refs = TEMPLATE_REF_RE.findall(value)
        unresolved = sorted(set(ref for ref in refs if ref not in resolved))
        if unresolved:
            miss(name, "template references unresolved bindings: " + ", ".join(unresolved))
            continue
        resolved[name] = TEMPLATE_REF_RE.sub(lambda m: resolved[m.group(1)], value)

    for name in sorted(contract["key_vault_bindings"]):
        kv_name = contract["key_vault_bindings"][name]
        override = environ.get(name, "")
        if override:
            resolved[name] = override
        elif kv_name in secrets:
            resolved[name] = secrets[kv_name]
        else:
            miss(name, f"Key Vault secret '{kv_name}' was not supplied")

    for name in sorted(resolved):
        _check_value_safe(name, resolved[name])
    return resolved, missing


def secret_names(contract):
    names = set(contract["key_vault_bindings"].values())
    for source in contract["sources"].values():
        keyvault = KEYVAULT_SOURCE_RE.fullmatch(source)
        if keyvault:
            names.add(keyvault.group(1))
    return sorted(names)


def load_secrets(path):
    if not path:
        return {}
    try:
        with open(path, encoding="utf-8") as stream:
            secrets = json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        raise Infra("SECRETS_UNREADABLE", f"{path}: {error}")
    if not isinstance(secrets, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in secrets.items()
    ):
        raise Infra("SECRETS_UNREADABLE",
                    f"{path}: expected a JSON object of secret name to value")
    return secrets


# ---------------------------------------------------------------------------
# Entry point

def build_report(mode, contract, facts, resolved, missing, agreement):
    return {
        "engine_version": ENGINE_VERSION,
        "report_schema": REPORT_SCHEMA,
        "mode": mode,
        "service": contract["service"],
        "contract": {
            "test_type": contract["test_type"],
            "test_dir": contract["test_dir"],
            "maven_arguments": contract["maven_arguments"],
            "timeout_minutes": contract["timeout_minutes"],
            "requires": contract["requires"],
            "dependencies": contract["dependencies"],
        },
        "key_vault": {
            "vault": _fact_at(facts, VAULT_NAME_PATH),
            "secret_names": secret_names(contract),
        },
        "agreement_checked": agreement,
        "resolved_names": sorted(resolved),
        "missing": missing,
        "error": None,
    }


def write_report(path, report):
    if not path:
        return
    with open(path, "w", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")


def write_env_file(path, resolved):
    with open(path, "w", encoding="utf-8") as stream:
        for name in sorted(resolved):
            stream.write(f"{name}={resolved[name]}\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--descriptor", required=True)
    parser.add_argument("--facts", required=True)
    parser.add_argument("--mode", required=True, choices=("bind", "run"))
    parser.add_argument("--env-file", required=True)
    parser.add_argument("--secrets", default="")
    parser.add_argument("--expect-gateway", default="")
    parser.add_argument("--expect-partition", default="")
    parser.add_argument("--report", default="")
    args = parser.parse_args(argv)

    report = None
    try:
        try:
            with open(args.descriptor, encoding="utf-8") as stream:
                descriptor_text = stream.read()
        except OSError as error:
            raise Halt("DESCRIPTOR_UNREADABLE", f"{args.descriptor}: {error}")
        contract = validate_descriptor(parse_descriptor_yaml(descriptor_text))
        facts = load_facts(args.facts)
        secrets = load_secrets(args.secrets)
        agreement = check_agreement(facts, args.expect_gateway, args.expect_partition)
        resolved, missing = resolve(contract, facts, secrets, os.environ)
        report = build_report(args.mode, contract, facts, resolved, missing, agreement)

        if missing and args.mode == "run":
            names = ", ".join(entry["name"] for entry in missing)
            raise EnvNotReady(f"unresolved required bindings: {names}")

        for entry in missing:
            print(f"warning: {entry['name']}: {entry['reason']}", file=sys.stderr)
        write_env_file(args.env_file, resolved)
        write_report(args.report, report)
        print(f"resolved {len(resolved)} bindings for service "
              f"'{contract['service']}' ({args.mode} mode"
              + (f", {len(missing)} missing" if missing else "") + ")")
        return 0
    except (Halt, EnvNotReady, Infra) as error:
        if report is None:
            report = {
                "engine_version": ENGINE_VERSION,
                "report_schema": REPORT_SCHEMA,
                "mode": args.mode,
                "error": None,
            }
        category = {Halt: "descriptor", EnvNotReady: "env-not-ready",
                    Infra: "infra"}[type(error)]
        report["error"] = {"category": category, "code": error.code,
                          "detail": error.detail}
        try:
            write_report(args.report, report)
        except OSError:
            pass
        print(f"error: {error}", file=sys.stderr)
        return {"descriptor": 2, "env-not-ready": 3, "infra": 4}[category]


if __name__ == "__main__":
    sys.exit(main())
