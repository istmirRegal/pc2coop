"""Original MIT code. Checks that the documentation matches the code (FEAT-221).

Run from anywhere: python tools/check_docs.py  (exit code 1 when something is off).
tests/test_docs.py runs the same checks with the unit tests.

What is checked:
- Feature registry (docs/project/FEATURES.md) and the `### FEAT-nnn` sections in
  docs/features/*.md: every ID once, same status, valid status words.
- Every FEAT-/ADR- reference in the docs exists.
- Every repository path in backticks exists.
- Every `Module.Function` in backticks is defined in the Lua code (or the JS class has
  the method).
- Every network message kind, DLL command and event, sync and session log line is in
  docs/architecture/NETWORKING.md; every UI action is in docs/ui-ux/UI_INVENTORY.md;
  every QA command is in docs/features/dev-and-qa.md.
- The newest version in docs/changelog/CHANGELOG.md is Session.VERSION.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
MAINTAINED = ["project", "features", "architecture", "ui-ux", "decisions", "development", "changelog"]
MOD = ROOT / "probe/PC2CoopProbe/Main/pc2coop"
LUA_ROOT = ROOT / "probe/PC2CoopProbe/Main"
JS = ROOT / "probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js"
DLL = ROOT / "native/steam_net.cpp"
STATUSES = {"Implemented", "Implemented-Untested", "Legacy", "Replaced", "Removed", "Planned"}
REPO_TOPS = ("probe/", "native/", "tools/", "tests/", "docs/", "alpha-dist/", "pc2coop/", "profiles/")
ROOT_FILES = {"README.md", "CLAUDE.md", "LICENSE", "release.json", ".gitattributes", ".gitignore"}
PLACEHOLDER = re.compile(r"[<>*…{}|]")
FILE_TYPES = {"js", "lua", "md", "py", "cpp", "txt", "json", "ps1", "cmd", "rc", "xml", "dll", "log", "flag", "zip", "ovl"}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def doc_files(root: Path = ROOT) -> list[Path]:
    files = [root / "CLAUDE.md", root / "docs/README.md"]
    for folder in MAINTAINED:
        files += sorted((root / "docs" / folder).glob("*.md"))
    return [f for f in files if f.exists()]


def without_fences(text: str) -> str:
    return re.sub(r"```.*?```", "", text, flags=re.S)


def inline_code(text: str) -> list[tuple[int, str, str]]:
    """(line number, code, whole line) of every `code` outside fenced blocks."""
    out = []
    for number, line in enumerate(without_fences(text).splitlines(), 1):
        for code in re.findall(r"`([^`\n]+)`", line):
            out.append((number, code, line))
    return out


# Registry -------------------------------------------------------------------------------

def registry_rows(text: str) -> list[tuple[str, str, str]]:
    """(id, status, area file) for every row of the registry."""
    rows, area = [], ""
    for line in text.splitlines():
        heading = re.match(r"^## .*\]\(\.\./features/([\w-]+\.md)\)", line)
        if heading:
            area = heading.group(1)
            continue
        row = re.match(r"^\|\s*(FEAT-\d{3})\s*\|[^|]*\|\s*`?([\w-]+)`?\s*\|", line)
        if row:
            rows.append((row.group(1), row.group(2), area))
    return rows


def feature_sections(features: dict[str, str]) -> dict[str, list[tuple[str, str]]]:
    """id -> [(file, status in the section)]."""
    found: dict[str, list[tuple[str, str]]] = {}
    for name, text in features.items():
        parts = re.split(r"(?m)^### (FEAT-\d{3})\b.*$", text)
        for i in range(1, len(parts), 2):
            status = re.search(r"\*\*Status:\*\*\s*([\w-]+)", parts[i + 1])
            found.setdefault(parts[i], []).append((name, status.group(1) if status else ""))
    return found


def check_registry(registry: str, features: dict[str, str]) -> list[str]:
    problems = []
    rows = registry_rows(registry)
    sections = feature_sections(features)
    seen = set()
    for fid, status, area in rows:
        if fid in seen:
            problems.append(f"FEATURES.md: {fid} listed twice")
        seen.add(fid)
        if status not in STATUSES:
            problems.append(f"FEATURES.md: {fid} has unknown status {status!r}")
        places = sections.get(fid, [])
        if not places:
            problems.append(f"{fid}: no '### {fid}' section in docs/features/")
            continue
        if len(places) > 1:
            problems.append(f"{fid}: described {len(places)} times ({', '.join(p for p, _ in places)})")
        if area and places[0][0] != area:
            problems.append(f"{fid}: registry says {area}, section is in {places[0][0]}")
        if places[0][1] != status:
            problems.append(f"{fid}: status {status!r} in FEATURES.md but {places[0][1]!r} in {places[0][0]}")
    for fid in sections:
        if fid not in seen:
            problems.append(f"{fid}: section in {sections[fid][0][0]} but not in FEATURES.md")
    return problems


def check_references(texts: dict[str, str], feature_ids: set[str], root: Path = ROOT) -> list[str]:
    problems = []
    adrs = {m.group(1) for f in (root / "docs/decisions").glob("ADR-*.md") if (m := re.match(r"ADR-(\d{3})", f.name))}
    for name, text in texts.items():
        for fid in sorted(set(re.findall(r"\bFEAT-(\d{3})\b", text))):
            if "FEAT-" + fid not in feature_ids:
                problems.append(f"{name}: FEAT-{fid} is not in the registry")
        for adr in sorted(set(re.findall(r"\bADR-(\d{3})\b", text))):
            if adr not in adrs and adr != "nnn":
                problems.append(f"{name}: ADR-{adr} does not exist in docs/decisions/")
    return problems


# Paths and functions --------------------------------------------------------------------

def check_paths(texts: dict[str, str], root: Path = ROOT) -> list[str]:
    problems = []
    for name, text in texts.items():
        for number, code, line in inline_code(text):
            if "(entfernt)" in line:
                continue
            token = code.split()[0].rstrip(",;:)")
            token = re.sub(r":\d+$", "", token)
            if PLACEHOLDER.search(token):
                continue
            if token.startswith(REPO_TOPS) or token in ROOT_FILES:
                if not (root / token).exists():
                    problems.append(f"{name}:{number}: path `{token}` does not exist")
    return problems


def lua_definitions(root: Path = ROOT) -> set[str]:
    names = set()
    for path in (root / "probe/PC2CoopProbe/Main").rglob("*.lua"):
        text = read(path)
        for a, b in re.findall(r"(?m)^\s*function\s+([A-Z]\w*)[.:](\w+)\s*\(", text):
            names.add(f"{a}.{b}")
        for a, b in re.findall(r"(?m)^\s*([A-Z]\w*)\.(\w+)\s*=", text):
            names.add(f"{a}.{b}")
    # Hook slots filled from outside: `session.OnMenuKey = function` defines Session.OnMenuKey.
    modules = {n.split(".")[0].lower(): n.split(".")[0] for n in names}
    for path in (root / "probe/PC2CoopProbe/Main").rglob("*.lua"):
        for receiver, member in re.findall(r"\b(\w+)\.(\w+)\s*=\s*function", read(path)):
            if receiver.lower() in modules:
                names.add(f"{modules[receiver.lower()]}.{member}")
    return names


def js_methods(root: Path = ROOT) -> dict[str, str]:
    text = read(root / "probe/PC2CoopProbe/ui/UIGameface/js/pc2coop/CoopLayer.js")
    return {cls: text for cls in re.findall(r"\bclass (\w+)", text)}


def check_functions(texts: dict[str, str], root: Path = ROOT) -> list[str]:
    problems = []
    defined = lua_definitions(root)
    prefixes = {d.split(".")[0] for d in defined}
    js = js_methods(root)
    for name, text in texts.items():
        for number, code, line in inline_code(text):
            if "(entfernt)" in line:
                continue
            for prefix, member in re.findall(r"(?<![\w.])([A-Z]\w*)[.:]([A-Za-z_]\w*)", code):
                if member in FILE_TYPES:
                    continue  # a file name such as CoopLayer.js
                if prefix in prefixes and f"{prefix}.{member}" not in defined:
                    problems.append(f"{name}:{number}: `{prefix}.{member}` is not defined in the Lua code")
                elif prefix in js and prefix not in prefixes and not re.search(r"\b" + member + r"\s*\(", js[prefix]):
                    problems.append(f"{name}:{number}: `{prefix}.{member}` is not a method in CoopLayer.js")
    return problems


# Coverage of protocol, UI actions and QA commands ----------------------------------------

def codes_in(text: str) -> set[str]:
    return {code.strip() for _, code, _ in inline_code(text)}


def wire_kinds(root: Path = ROOT) -> set[str]:
    session = read(root / "probe/PC2CoopProbe/Main/pc2coop/session.lua")
    return set(re.findall(r'(?:kind|f\[1\])\s*==\s*"([^"]+)"', session))


def dll_verbs(root: Path = ROOT) -> set[str]:
    return set(re.findall(r'verb == "([\w-]+)"', read(root / "native/steam_net.cpp")))


def dll_events(root: Path = ROOT) -> set[str]:
    text = read(root / "native/steam_net.cpp")
    events = set(re.findall(r'queue\("([a-z]+(?::[a-z-]+)?)[|"]', text))
    events |= set(re.findall(r'"([a-z]+:[a-z-]+)[|"]', text))
    return events


def log_lines(prefix: str, root: Path = ROOT) -> set[str]:
    found = set()
    for path in (root / "probe/PC2CoopProbe/Main/pc2coop").glob("*.lua"):
        found |= set(re.findall(r'"' + prefix + r':([a-z-]+)', read(path)))
    return found


def ui_actions(root: Path = ROOT) -> set[str]:
    text = read(root / "probe/PC2CoopProbe/Main/pc2coop/ui.lua")
    table = re.search(r"(?ms)^local actions = \{\n(.*?)^\}", text)
    if not table:
        return set()
    names = set()
    for quoted, plain in re.findall(r'(?m)^    (?:\["(\w+)"\]|(\w+)) = function', table.group(1)):
        names.add(quoted or plain)
    return names


def qa_commands(root: Path = ROOT) -> set[str]:
    return set(re.findall(r'command\s*==\s*"([\w-]+)"', read(root / "probe/PC2CoopProbe/Main/pc2coop/qa.lua")))


def check_coverage(root: Path = ROOT) -> list[str]:
    problems = []
    networking = codes_in(read(root / "docs/architecture/NETWORKING.md"))
    groups = [
        ("network message", wire_kinds(root), networking),
        ("DLL command", dll_verbs(root), networking),
        ("DLL event", dll_events(root), networking),
        ("sync line", log_lines("sync", root), networking),
        ("session log line", log_lines("session", root), networking | {c.split(":", 1)[-1] for c in networking}),
        ("UI action", ui_actions(root), codes_in(read(root / "docs/ui-ux/UI_INVENTORY.md"))),
        ("QA command", qa_commands(root), codes_in(read(root / "docs/features/dev-and-qa.md"))),
    ]
    for label, found, documented in groups:
        if not found:
            problems.append(f"no {label}s found in the code: the check itself needs fixing")
        for item in sorted(found - documented):
            problems.append(f"{label} `{item}` is not documented")
    return problems


def check_version(root: Path = ROOT) -> list[str]:
    session = read(root / "probe/PC2CoopProbe/Main/pc2coop/session.lua")
    version = re.search(r'Session\.VERSION = "([\d.]+)"', session)
    newest = re.search(r"(?m)^## (\d+\.\d+\.\d+)", read(root / "docs/changelog/CHANGELOG.md"))
    if not version or not newest:
        return ["version: Session.VERSION or a version heading in CHANGELOG.md not found"]
    if version.group(1) != newest.group(1):
        return [f"version: Session.VERSION is {version.group(1)}, newest CHANGELOG entry is {newest.group(1)}"]
    return []


def check(root: Path = ROOT) -> list[str]:
    texts = {str(p.relative_to(root)).replace("\\", "/"): read(p) for p in doc_files(root)}
    features = {p.name: read(p) for p in sorted((root / "docs/features").glob("*.md"))}
    registry = read(root / "docs/project/FEATURES.md")
    ids = {fid for fid, _, _ in registry_rows(registry)}
    return (check_registry(registry, features) + check_references(texts, ids, root) + check_paths(texts, root)
            + check_functions(texts, root) + check_coverage(root) + check_version(root))


def main() -> int:
    problems = check()
    for problem in problems:
        print(problem)
    print(f"check_docs: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
