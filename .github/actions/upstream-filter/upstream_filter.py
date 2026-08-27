#!/usr/bin/env python3
"""Upstream filter engine.

Transforms a checkout of the verbatim upstream tip into the generated
fork_upstream tree, verifies generated trees, stamps fork-owned pom versions,
and seeds the fork-owned Azure trees.

Contract: README.md beside this file. Standard library only. Never runs git.
Deterministic: sorted walks, verbatim injection, no timestamps.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET

ENGINE_VERSION = "1.0.0"
REPORT_SCHEMA = 1

WHOLESALE_DIRS = ("provider", "devops")
VERDICTS = {
    "top_level": {"keep", "strip"},
    "testing": {"keep", "strip", "fork"},
    "profiles": {"keep", "strip", "inject"},
    "fossa_modules": {"keep", "strip"},
}
REQUIRED_KEYS = {
    "service": str,
    "top_level": dict,
    "testing": dict,
    "profiles": dict,
    "fossa_modules": dict,
    "expected_kept": list,
    "expected_absent": list,
    "inject_root_pom_azure_profile": str,
    "inject_testing_pom_azure_module": str,
}


class Halt(Exception):
    """Exit 2: the engine refuses to guess."""

    def __init__(self, code, detail):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


# ---------------------------------------------------------------------------
# Config

def _unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def _strip_inline_comment(value):
    # YAML rule: an inline comment's '#' must be preceded by whitespace.
    if value.lstrip().startswith("#"):
        return ""
    m = re.search(r"\s#", value)
    return value[:m.start()] if m else value


def parse_config(text):
    """Fixed-schema reader for the accepted YAML subset (see README)."""
    data = {}
    lines = text.split("\n")
    i, n = 0, len(lines)

    def skippable(line):
        stripped = line.strip()
        return not stripped or stripped.startswith("#")

    while i < n:
        line = lines[i]
        if skippable(line):
            i += 1
            continue
        if line[0] in " \t":
            raise Halt("CONFIG_INVALID", f"line {i + 1}: unexpected indentation")
        m = re.match(r"^([A-Za-z0-9_.-]+):(.*)$", line)
        if not m:
            raise Halt("CONFIG_INVALID", f"line {i + 1}: expected 'key:' form")
        key, rest = m.group(1), _strip_inline_comment(m.group(2)).strip()
        i += 1
        if rest == "|":
            block = []
            while i < n:
                raw = lines[i]
                if raw.strip() == "":
                    block.append("")
                    i += 1
                elif raw.startswith("  "):
                    block.append(raw[2:])
                    i += 1
                else:
                    break
            while block and block[-1] == "":
                block.pop()
            data[key] = ("\n".join(block) + "\n") if block else ""
        elif rest == "":
            entries_map, entries_list, kind = {}, [], None
            while i < n:
                raw = lines[i]
                if skippable(raw):
                    i += 1
                    continue
                if not raw.startswith("  "):
                    break
                body = raw[2:]
                if body[0] in " \t":
                    raise Halt("CONFIG_INVALID", f"line {i + 1}: nests deeper than the schema allows")
                if body.startswith("- "):
                    if kind == "map":
                        raise Halt("CONFIG_INVALID", f"line {i + 1}: list entry inside a map block")
                    kind = "list"
                    entries_list.append(_unquote(_strip_inline_comment(body[2:]).strip()))
                else:
                    mm = re.match(r"^(.+?):\s*(.*)$", body)
                    if not mm:
                        raise Halt("CONFIG_INVALID", f"line {i + 1}: expected 'name: verdict'")
                    if kind == "list":
                        raise Halt("CONFIG_INVALID", f"line {i + 1}: map entry inside a list block")
                    kind = "map"
                    name = _unquote(mm.group(1).strip())
                    if name in entries_map:
                        raise Halt("CONFIG_INVALID", f"line {i + 1}: duplicate entry '{name}'")
                    entries_map[name] = _unquote(_strip_inline_comment(mm.group(2)).strip())
                i += 1
            if kind is None:
                data[key] = [] if REQUIRED_KEYS.get(key) is list else {}
            else:
                data[key] = entries_list if kind == "list" else entries_map
        else:
            data[key] = _unquote(rest)
    return data


def load_config(path):
    if not os.path.isfile(path):
        raise Halt("CONFIG_MISSING", f"config not found at {path}; the sync fails closed with no merge fallback")
    with open(path, "rb") as fh:
        raw = fh.read()
    cfg = parse_config(raw.decode("utf-8"))
    for key, expected_type in REQUIRED_KEYS.items():
        if key not in cfg:
            raise Halt("CONFIG_INVALID", f"missing required key '{key}'")
        if not isinstance(cfg[key], expected_type):
            raise Halt("CONFIG_INVALID", f"key '{key}' has the wrong shape")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", cfg["service"]):
        raise Halt("CONFIG_INVALID", f"service '{cfg['service']}' is not a valid slug")
    for section, allowed in VERDICTS.items():
        for name, verdict in cfg[section].items():
            if verdict not in allowed:
                raise Halt("CONFIG_INVALID", f"{section}.{name}: verdict '{verdict}' not in {sorted(allowed)}")
    injects = [name for name, verdict in cfg["profiles"].items() if verdict == "inject"]
    if len(injects) > 1:
        raise Halt("CONFIG_INVALID", f"profiles: at most one inject verdict, found {injects}")
    if injects and not cfg["inject_root_pom_azure_profile"].strip():
        raise Halt("CONFIG_INVALID", "profiles declare an inject verdict but inject_root_pom_azure_profile is empty")
    if cfg["inject_root_pom_azure_profile"].strip() and not injects:
        raise Halt("CONFIG_INVALID", "inject_root_pom_azure_profile is set but no profile declares an inject verdict")
    forks = [name for name, verdict in cfg["testing"].items() if verdict == "fork"]
    if forks and not cfg["inject_testing_pom_azure_module"].strip():
        raise Halt("CONFIG_INVALID", "testing declares a fork verdict but inject_testing_pom_azure_module is empty")
    if cfg["inject_testing_pom_azure_module"].strip() and not forks:
        raise Halt("CONFIG_INVALID", "inject_testing_pom_azure_module is set but no testing entry declares a fork verdict")
    cfg["_sha256"] = hashlib.sha256(raw).hexdigest()
    return cfg


# ---------------------------------------------------------------------------
# Small file helpers

def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def count_files(root):
    total = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d != ".git")
        total += len(filenames)
    return total


def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.remove(path)


def module_paths_in(block):
    return set(re.findall(r"<module>([^<]+)</module>", block))


# ---------------------------------------------------------------------------
# Pom surgery (text-level: pom formatting and comments survive untouched)

def in_xml_comment(text, pos):
    open_idx = text.rfind("<!--", 0, pos)
    return open_idx != -1 and text.find("-->", open_idx, pos) == -1


def find_element_region(text, tag):
    """First <tag>...</tag> region that is not inside an XML comment."""
    for m in re.finditer(rf"<{tag}>.*?</{tag}>", text, re.S):
        if not in_xml_comment(text, m.start()):
            return m
    return None


def classify_profiles(pom_text, profiles_cfg):
    """Return (profile blocks with spans and ids, unknown ids). A block inside
    an XML comment is dead text: it is neither classified nor stripped."""
    region = find_element_region(pom_text, "profiles")
    if not region:
        return [], []
    blocks, unknown = [], []
    for m in re.finditer(r"[ \t]*<profile>.*?</profile>[ \t]*\n?", region.group(0), re.S):
        tag_pos = region.start() + m.start() + m.group(0).index("<profile>")
        if in_xml_comment(pom_text, tag_pos):
            continue
        block = m.group(0)
        idm = re.search(r"<id>\s*([^<]+?)\s*</id>", block)
        pid = idm.group(1) if idm else "(missing id)"
        span = (region.start() + m.start(), region.start() + m.end())
        verdict = profiles_cfg.get(pid)
        if verdict is None:
            unknown.append(pid)
        blocks.append((pid, verdict, span))
    return blocks, unknown


def strip_profiles(pom_text, blocks):
    """Remove profile blocks whose verdict is strip or inject."""
    out, last = [], 0
    for _pid, verdict, (start, end) in blocks:
        if verdict in ("strip", "inject"):
            out.append(pom_text[last:start])
            last = end
    out.append(pom_text[last:])
    return "".join(out)


def prune_dangling_modules(pom_path, exempt):
    """Drop <module> lines whose target no longer exists. Derivation, not a list:
    the file pass halts on unknowns, so a missing path can only mean a strip."""
    base = os.path.dirname(pom_path)
    removed, kept_lines = [], []
    for line in read_text(pom_path).splitlines(keepends=True):
        m = re.match(r"^\s*<module>([^<]+)</module>\s*(?:<!--.*?-->\s*)?$", line)
        if m:
            target = m.group(1).strip()
            if target not in exempt and not os.path.exists(os.path.join(base, target)):
                removed.append(target)
                continue
        kept_lines.append(line)
    if removed:
        write_text(pom_path, "".join(kept_lines))
    return removed


def iter_live_modules(pom_text):
    """Yield <module> targets that are not inside XML comments."""
    for m in re.finditer(r"<module>([^<]+)</module>", pom_text):
        if not in_xml_comment(pom_text, m.start()):
            yield m.group(1).strip()


def inject_into_region(pom_path, tag, block, halt_detail):
    """Insert the stored block verbatim before the closing line of the first
    live <tag> region, the same region classification and stripping used."""
    text = read_text(pom_path)
    region = find_element_region(text, tag)
    if region is None:
        raise Halt("INJECT_TARGET_MISSING", halt_detail)
    close_pos = region.end() - len(f"</{tag}>")
    line_start = text.rfind("\n", 0, close_pos) + 1
    write_text(pom_path, text[:line_start] + block + text[line_start:])


# ---------------------------------------------------------------------------
# .fossa.yml surgery (v1 shape: analyze.modules, items keyed by name)

def parse_fossa_modules(text):
    """Return (module items as (name, start_line, end_line), lines) or halt."""
    lines = text.split("\n")
    mod_idx, mod_indent = None, None
    in_analyze = False
    for idx, line in enumerate(lines):
        if re.match(r"^analyze:\s*$", line):
            in_analyze = True
            continue
        if in_analyze and line and line[0] not in " \t" and not line.startswith("#"):
            in_analyze = False
        m = re.match(r"^(\s+)modules:\s*$", line)
        if in_analyze and m:
            mod_idx, mod_indent = idx, len(m.group(1))
            break
    if mod_idx is None:
        raise Halt("FOSSA_UNPARSEABLE", ".fossa.yml has no analyze.modules key")
    # YAML allows list items at the key's own column or deeper; accept both.
    items = []
    idx = mod_idx + 1
    current_start, current_indent = None, None
    while idx < len(lines):
        line = lines[idx]
        if line.strip() and not line.lstrip().startswith("#"):
            indent = len(line) - len(line.lstrip(" "))
            is_item = bool(re.match(r"^\s*- ", line)) and indent >= mod_indent \
                and (current_indent is None or indent == current_indent)
            if indent < mod_indent:
                break
            if indent == mod_indent and not is_item:
                break
            if is_item:
                if current_start is not None:
                    items.append((current_start, idx))
                current_start, current_indent = idx, indent
            elif current_start is None:
                raise Halt("FOSSA_UNPARSEABLE",
                           f".fossa.yml analyze.modules is not a list (line {idx + 1})")
        idx += 1
    if current_start is not None:
        items.append((current_start, idx))
    if not items:
        raise Halt("FOSSA_UNPARSEABLE", ".fossa.yml analyze.modules has no list items")
    named = []
    for start, end in items:
        body = "\n".join(lines[start:end])
        nm = re.search(r"\bname:\s*(\S+)", body)
        if not nm:
            raise Halt("FOSSA_UNPARSEABLE", f".fossa.yml module at line {start + 1} has no name")
        named.append((_unquote(nm.group(1)), start, end))
    return named, lines


def filter_fossa(path, fossa_cfg, checkout):
    text = read_text(path)
    named, lines = parse_fossa_modules(text)
    unknown = [name for name, _s, _e in named if name not in fossa_cfg]
    if unknown:
        raise Halt("UNKNOWN_FOSSA_MODULE", f"unclassified .fossa.yml modules: {', '.join(sorted(unknown))}")
    drop = set()
    stripped = []
    for name, start, end in named:
        if fossa_cfg[name] == "strip":
            drop.update(range(start, end))
            stripped.append(name)
        else:
            body = "\n".join(lines[start:end])
            tm = re.search(r"\btarget:\s*(\S+)", body)
            if tm and not os.path.exists(os.path.join(checkout, _unquote(tm.group(1)))):
                raise Halt("FOSSA_TARGET_MISSING", f"kept FOSSA module '{name}' targets missing path {tm.group(1)}")
    if drop:
        write_text(path, "\n".join(line for idx, line in enumerate(lines) if idx not in drop))
    return stripped


# ---------------------------------------------------------------------------
# Generate

def generate(checkout, cfg, report):
    initial = count_files(checkout)
    discarded = []

    def discard(rel):
        discarded.append(rel)
        remove_path(os.path.join(checkout, rel))

    unknown = []
    for entry in sorted(os.listdir(checkout)):
        if entry == ".git":
            continue
        if entry in WHOLESALE_DIRS:
            discard(entry)
            continue
        if entry == "testing" and os.path.isdir(os.path.join(checkout, entry)):
            continue
        verdict = cfg["top_level"].get(entry)
        if verdict is None:
            unknown.append(entry)
        elif verdict == "strip":
            discard(entry)
    if unknown:
        raise Halt("UNKNOWN_TOP_LEVEL", f"unclassified top-level entries: {', '.join(unknown)}")

    testing_dir = os.path.join(checkout, "testing")
    if os.path.isdir(testing_dir):
        unknown = []
        for entry in sorted(os.listdir(testing_dir)):
            verdict = cfg["testing"].get(entry)
            if verdict is None:
                unknown.append(entry)
            elif verdict in ("strip", "fork"):
                discard(os.path.join("testing", entry))
        if unknown:
            raise Halt("UNKNOWN_TESTING_ENTRY", f"unclassified testing/ entries: {', '.join(unknown)}")

    root_pom = os.path.join(checkout, "pom.xml")
    if os.path.isfile(root_pom):
        text = read_text(root_pom)
        blocks, unknown = classify_profiles(text, cfg["profiles"])
        if unknown:
            raise Halt("UNKNOWN_PROFILE", f"unclassified root pom profiles: {', '.join(unknown)}")
        write_text(root_pom, strip_profiles(text, blocks))
        prune_dangling_modules(root_pom, exempt=set())
        if any(verdict == "inject" for _pid, verdict, _span in blocks) or cfg["inject_root_pom_azure_profile"].strip():
            inject_into_region(root_pom, "profiles", cfg["inject_root_pom_azure_profile"],
                               "root pom has no <profiles> element for the azure profile injection")

    testing_pom = os.path.join(testing_dir, "pom.xml")
    if os.path.isfile(testing_pom):
        prune_dangling_modules(testing_pom, exempt=set())
        if cfg["inject_testing_pom_azure_module"].strip():
            inject_into_region(testing_pom, "modules", cfg["inject_testing_pom_azure_module"],
                               "testing/pom.xml has no <modules> element for the azure module injection")

    fossa = os.path.join(checkout, ".fossa.yml")
    if os.path.isfile(fossa):
        filter_fossa(fossa, cfg["fossa_modules"], checkout)

    verify(checkout, cfg)

    kept = count_files(checkout)
    report["counts"] = {"initial_files": initial, "kept_files": kept, "discarded_files": initial - kept}
    report["discarded"] = sorted(discarded)


# ---------------------------------------------------------------------------
# Verify

def verify(checkout, cfg):
    problems = []

    def check(cond, code, detail):
        if not cond:
            problems.append(Halt(code, detail))

    for entry in WHOLESALE_DIRS:
        check(not os.path.exists(os.path.join(checkout, entry)), "STRIPPED_PATH_SURVIVES", f"{entry}/ survives")

    for entry in sorted(os.listdir(checkout)):
        if entry == ".git" or (entry == "testing" and os.path.isdir(os.path.join(checkout, entry))):
            continue
        verdict = cfg["top_level"].get(entry)
        check(verdict is not None, "UNKNOWN_TOP_LEVEL", f"unclassified top-level entry: {entry}")
        check(verdict != "strip", "STRIPPED_PATH_SURVIVES", f"stripped top-level entry survives: {entry}")

    testing_dir = os.path.join(checkout, "testing")
    if os.path.isdir(testing_dir):
        for entry in sorted(os.listdir(testing_dir)):
            verdict = cfg["testing"].get(entry)
            check(verdict is not None, "UNKNOWN_TESTING_ENTRY", f"unclassified testing/ entry: {entry}")
            check(verdict == "keep" or verdict is None, "STRIPPED_PATH_SURVIVES",
                  f"non-kept testing/ entry survives: testing/{entry}")

    for rel in cfg["expected_kept"]:
        check(os.path.exists(os.path.join(checkout, rel)), "EXPECTED_KEPT_MISSING",
              f"expected_kept path missing: {rel} (an upstream rename fails loud, not silent)")
    for rel in cfg["expected_absent"]:
        check(not os.path.exists(os.path.join(checkout, rel)), "EXPECTED_ABSENT_PRESENT",
              f"expected_absent path present: {rel}")

    root_pom = os.path.join(checkout, "pom.xml")
    root_exempt = module_paths_in(cfg["inject_root_pom_azure_profile"])
    if os.path.isfile(root_pom):
        text = read_text(root_pom)
        blocks, unknown = classify_profiles(text, cfg["profiles"])
        for pid in unknown:
            problems.append(Halt("UNKNOWN_PROFILE", f"unclassified root pom profile: {pid}"))
        for pid, verdict, _span in blocks:
            check(verdict != "strip", "STRIPPED_PATH_SURVIVES", f"stripped profile survives: {pid}")
        for name, verdict in cfg["profiles"].items():
            if verdict == "inject":
                count = sum(1 for pid, _v, _s in blocks if pid == name)
                check(count == 1, "INJECT_MISSING",
                      f"injected profile '{name}' appears {count} times in pom.xml, expected exactly once")
        for target in iter_live_modules(text):
            check(target in root_exempt or os.path.exists(os.path.join(checkout, target)),
                  "MODULE_UNRESOLVED", f"pom.xml module does not resolve: {target}")

    testing_pom = os.path.join(testing_dir, "pom.xml")
    testing_exempt = module_paths_in(cfg["inject_testing_pom_azure_module"])
    if os.path.isfile(testing_pom):
        live = list(iter_live_modules(read_text(testing_pom)))
        for target in live:
            check(target in testing_exempt or os.path.exists(os.path.join(testing_dir, target)),
                  "MODULE_UNRESOLVED", f"testing/pom.xml module does not resolve: {target}")
        for target in sorted(testing_exempt):
            check(target in live, "INJECT_MISSING",
                  f"injected testing module missing from testing/pom.xml: {target}")

    fossa = os.path.join(checkout, ".fossa.yml")
    if os.path.isfile(fossa):
        named, _lines = parse_fossa_modules(read_text(fossa))
        for name, _s, _e in named:
            verdict = cfg["fossa_modules"].get(name)
            check(verdict is not None, "UNKNOWN_FOSSA_MODULE", f"unclassified .fossa.yml module: {name}")
            check(verdict != "strip", "STRIPPED_PATH_SURVIVES", f"stripped .fossa.yml module survives: {name}")

    if problems:
        raise Halt(problems[0].code, "; ".join(p.detail for p in problems))


# ---------------------------------------------------------------------------
# Stamp

def _pom_child(element, name):
    for child in element:
        if child.tag.rsplit("}", 1)[-1] == name:
            return child
    return None


def _own_version(pom_path):
    root = ET.parse(pom_path).getroot()
    version = _pom_child(root, "version")
    if version is not None and version.text:
        return version.text.strip()
    parent = _pom_child(root, "parent")
    if parent is not None:
        version = _pom_child(parent, "version")
        if version is not None and version.text:
            return version.text.strip()
    return None


def _reference_version(checkout, rel):
    path = os.path.join(checkout, rel)
    if not os.path.isfile(path):
        raise Halt("STAMP_REF_MISSING", f"reference pom missing: {rel}")
    version = _own_version(path)
    if not version:
        raise Halt("STAMP_REF_MISSING", f"reference pom carries no version: {rel}")
    return version


def _fork_poms(checkout, tree):
    poms = []
    top = os.path.join(checkout, tree)
    for dirpath, dirnames, filenames in os.walk(top):
        dirnames[:] = sorted(dirnames)
        if "pom.xml" in filenames:
            poms.append(os.path.join(dirpath, "pom.xml"))
    return sorted(poms)


def _version_site(value):
    # Element text may carry whitespace padding that ElementTree strips away.
    return re.compile(">(\\s*)" + re.escape(value) + "(\\s*)<")


def stamp(checkout, cfg, report):
    svc = cfg["service"]
    root_version = _reference_version(checkout, "pom.xml")
    testing_version = _reference_version(checkout, os.path.join("testing", "pom.xml"))
    testcore_version = _reference_version(checkout, os.path.join("testing", f"{svc}-test-core", "pom.xml"))

    targets = [
        (os.path.join("provider", f"{svc}-azure"), root_version),
        (os.path.join("testing", f"{svc}-test-azure"), testing_version),
    ]
    rewrites, survivors = [], []
    total_poms = 0

    # One mapping per tree: the provider tree follows the root pom version and the
    # testing tree follows the testing pom version, which may legitimately differ.
    for tree, tree_version in targets:
        poms = _fork_poms(checkout, tree)
        total_poms += len(poms)
        if not poms:
            continue
        mapping = {}

        def add(old, new):
            # Identity claims (old == new) register too: a literal one reference
            # bumps while another keeps must halt as ambiguous, not silently
            # rewrite the site that should have stayed.
            if not old or "${" in old:
                return
            if old in mapping and mapping[old] != new:
                raise Halt("STAMP_AMBIGUOUS", f"in {tree}: '{old}' would become both '{mapping[old]}' and '{new}'")
            mapping[old] = new

        for pom in poms:
            root = ET.parse(pom).getroot()
            parent = _pom_child(root, "parent")
            if parent is not None:
                version = _pom_child(parent, "version")
                if version is not None and version.text:
                    add(version.text.strip(), tree_version)
            version = _pom_child(root, "version")
            if version is not None and version.text:
                add(version.text.strip(), tree_version)
            dependencies = _pom_child(root, "dependencies")
            if dependencies is not None:
                for dep in dependencies:
                    artifact = _pom_child(dep, "artifactId")
                    version = _pom_child(dep, "version")
                    if artifact is not None and artifact.text and artifact.text.strip() == f"{svc}-test-core" \
                            and version is not None and version.text:
                        add(version.text.strip(), testcore_version)

        for pom in poms:
            text = read_text(pom)
            updated = text
            for old, new in sorted(mapping.items()):
                if old == new:
                    continue
                updated, count = _version_site(old).subn(
                    lambda m: f">{m.group(1)}{new}{m.group(2)}<", updated)
                if count:
                    rewrites.append({"pom": os.path.relpath(pom, checkout), "from": old, "to": new})
            if updated != text:
                write_text(pom, updated)

        # Post-condition, not a site list: no pre-bump version string survives.
        for pom in poms:
            text = read_text(pom)
            for old, new in mapping.items():
                if old == new:
                    continue
                if _version_site(old).search(text):
                    survivors.append(f"{os.path.relpath(pom, checkout)} still carries {old}")

    if total_poms == 0:
        raise Halt("STAMP_NO_FORK_POMS", f"no fork-owned poms found under {' or '.join(t for t, _v in targets)}")
    if survivors:
        raise Halt("STAMP_INCOMPLETE", "; ".join(survivors))

    report["stamp"] = {
        "references": {"root": root_version, "testing": testing_version, "test_core": testcore_version},
        "rewrites": rewrites,
    }


# ---------------------------------------------------------------------------
# Seed

def seed(checkout, cfg, seed_source, report):
    svc = cfg["service"]
    seeded = []
    for tree in (os.path.join("provider", f"{svc}-azure"), os.path.join("testing", f"{svc}-test-azure")):
        src = os.path.join(seed_source, tree)
        dst = os.path.join(checkout, tree)
        if not os.path.isdir(src) or not os.path.isfile(os.path.join(src, "pom.xml")):
            raise Halt("SEED_SOURCE_MISSING", f"seed source lacks {tree} (or its pom.xml)")
        if os.path.exists(dst):
            raise Halt("SEED_TARGET_EXISTS", f"seed target already exists: {tree}")
        shutil.copytree(src, dst)
        seeded.append(tree)
    report["seeded"] = seeded


# ---------------------------------------------------------------------------
# Entry point

class _ArgumentParser(argparse.ArgumentParser):
    """Exit 1 on a bad invocation; exit 2 is reserved for halts."""

    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"error: {message}", file=sys.stderr)
        sys.exit(1)


def main(argv=None):
    parser = _ArgumentParser(description="Upstream filter engine")
    parser.add_argument("--mode", required=True, choices=["generate", "verify", "stamp", "seed"])
    parser.add_argument("--config", required=True)
    parser.add_argument("--checkout", required=True)
    parser.add_argument("--seed-source")
    parser.add_argument("--report")
    args = parser.parse_args(argv)

    report = {
        "schema": REPORT_SCHEMA,
        "mode": args.mode,
        "engine_version": ENGINE_VERSION,
        "ok": False,
        "halts": [],
    }

    def emit(code):
        payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
        sys.stdout.write(payload)
        if args.report:
            write_text(args.report, payload)
        return code

    try:
        if not os.path.isdir(args.checkout):
            print(f"error: checkout directory not found: {args.checkout}", file=sys.stderr)
            return 1
        if args.mode == "seed" and not args.seed_source:
            print("error: --seed-source is required for seed mode", file=sys.stderr)
            return 1

        cfg = load_config(args.config)
        report["service"] = cfg["service"]
        report["config_sha256"] = cfg["_sha256"]
        report["filter_rev"] = f"{ENGINE_VERSION}+{cfg['_sha256'][:12]}"

        if args.mode == "generate":
            generate(args.checkout, cfg, report)
        elif args.mode == "verify":
            verify(args.checkout, cfg)
        elif args.mode == "stamp":
            stamp(args.checkout, cfg, report)
        elif args.mode == "seed":
            seed(args.checkout, cfg, args.seed_source, report)
        report["ok"] = True
        return emit(0)
    except Halt as halt:
        report["halts"].append({"code": halt.code, "detail": halt.detail})
        return emit(2)


if __name__ == "__main__":
    sys.exit(main())
