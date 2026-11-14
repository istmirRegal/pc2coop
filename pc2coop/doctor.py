"""Read-only Steam/game inspection, using only the Python standard library."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import struct
from typing import Any

APP_ID = "2688950"


class VDFError(ValueError):
    pass


def parse_vdf(text: str) -> dict[str, Any]:
    """Parse quoted Steam KeyValues, preserving backslashes and nested objects."""
    tokens: list[str] = []
    position = 0
    while position < len(text):
        if text[position].isspace() or text[position] == "\ufeff":
            position += 1
        elif text.startswith("//", position):
            end = text.find("\n", position)
            position = len(text) if end == -1 else end + 1
        elif text[position] in "{}":
            tokens.append(text[position])
            position += 1
        elif text[position] == '"':
            position += 1
            value: list[str] = []
            while position < len(text) and text[position] != '"':
                char = text[position]
                if char == "\\" and position + 1 < len(text):
                    following = text[position + 1]
                    if following in ('"', "\\"):
                        char = following
                        position += 1
                value.append(char)
                position += 1
            if position >= len(text):
                raise VDFError("Unterminated quoted string")
            # A prefix distinguishes quoted braces from structural braces.
            tokens.append("s:" + "".join(value))
            position += 1
        else:
            raise VDFError(f"Unexpected unquoted character at {position}")

    cursor = 0

    def read_object(nested: bool = False) -> dict[str, Any]:
        nonlocal cursor
        result: dict[str, Any] = {}
        while cursor < len(tokens):
            key = tokens[cursor]
            cursor += 1
            if key == "}":
                if not nested:
                    raise VDFError("Unexpected closing brace")
                return result
            if not key.startswith("s:") or cursor == len(tokens):
                raise VDFError("Expected a key and value")
            token = tokens[cursor]
            cursor += 1
            if token == "{":
                value = read_object(True)
            elif token.startswith("s:"):
                value = token[2:]
            else:
                raise VDFError("Expected a string or object")
            key = key[2:]
            if key in result:
                raise VDFError(f"Duplicate key: {key}")
            result[key] = value
        if nested:
            raise VDFError("Missing closing brace")
        return result

    return read_object()


def read_vdf(path: Path) -> dict[str, Any]:
    return parse_vdf(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def pe_architecture(path: Path) -> str:
    try:
        with path.open("rb") as stream:
            header = stream.read(64)
            if len(header) < 64 or header[:2] != b"MZ":
                return "not-pe"
            offset = struct.unpack_from("<I", header, 0x3C)[0]
            if offset > path.stat().st_size - 6:
                return "invalid-pe"
            stream.seek(offset)
            pe = stream.read(6)
            if pe[:4] != b"PE\0\0":
                return "invalid-pe"
            return {0x8664: "x64", 0x14C: "x86", 0xAA64: "arm64"}.get(
                struct.unpack_from("<H", pe, 4)[0], "unknown"
            )
    except OSError:
        return "unreadable"


def steam_roots(explicit: list[Path] | None = None) -> list[Path]:
    roots = list(explicit or [])
    if explicit is None:
        if os.name == "nt":
            import winreg

            for hive, key, field in (
                (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
            ):
                try:
                    with winreg.OpenKey(hive, key) as handle:
                        roots.append(Path(winreg.QueryValueEx(handle, field)[0]))
                except OSError:
                    pass
        for variable in ("ProgramFiles(x86)", "ProgramFiles"):
            if os.environ.get(variable):
                roots.append(Path(os.environ[variable]) / "Steam")
    for root in list(roots):
        libraries = root / "steamapps" / "libraryfolders.vdf"
        if libraries.is_file():
            data = read_vdf(libraries).get("libraryfolders", {})
            for value in data.values():
                if isinstance(value, dict) and isinstance(value.get("path"), str):
                    roots.append(Path(value["path"]))
                elif isinstance(value, str):
                    candidate = Path(value)
                    if candidate.is_absolute():
                        roots.append(candidate)
    return list(dict.fromkeys(path.resolve() for path in roots))


def inspect_game(game_dir: Path, manifest: dict[str, Any] | None = None) -> dict[str, Any]:
    manifest = manifest or {}
    win64 = game_dir / "Win64"
    executable = win64 / "PlanetCoaster2.exe"
    # Require the known main executable, not CrashReporter or another helper.
    if not executable.is_file():
        executable = game_dir / "PlanetCoaster2.exe"
    available = executable.is_file()
    build_id = manifest.get("buildid", "unknown")
    # Installed=4 is not enough if Steam is concurrently updating the installation.
    installed_state = manifest.get("StateFlags") == "4"
    data_available = (win64 / "ovldata").is_dir()
    ready = available and data_available and (not manifest or installed_state)
    report: dict[str, Any] = {
        "game": "Planet Coaster 2",
        "appid": APP_ID,
        "store": "Steam" if manifest else "unknown (explicit path)",
        "os": platform.system(),
        "game_dir": str(game_dir.resolve()),
        "status": "ready-for-inspection" if ready else "installation-incomplete",
        "build_id": build_id,
        "steam_state_flags": manifest.get("StateFlags", "unknown"),
        "bytes_on_disk": manifest.get("SizeOnDisk", "unknown"),
        "downloaded_bytes": manifest.get("BytesDownloaded", "unknown"),
        "download_total_bytes": manifest.get("BytesToDownload", "unknown"),
        "exe": None,
        "engine": "Cobra (upstream modding references; not binary-verified)",
        "packages": [],
        "compatibility": "unverified; no supported executable profile yet",
        "in_game_qa": "not-run",
    }
    if available:
        report["exe"] = {
            "path": str(executable.resolve()),
            "size": executable.stat().st_size,
            "architecture": pe_architecture(executable),
            "sha256": sha256(executable),
        }
    for name in ("ACSE", "ForgeUtils", "ACSEDebug"):
        directory = win64 / "ovldata" / name
        if not directory.is_dir():
            continue
        version_file = directory / "Version.txt"
        version = version_file.read_text(encoding="utf-8-sig", errors="replace").strip()[:200] if version_file.is_file() else "unknown"
        packages = []
        for file in sorted(directory.iterdir()):
            if file.is_file() and file.suffix.lower() in {".xml", ".ini", ".ovl", ".ovs", ".dll"}:
                packages.append({"name": file.name, "sha256": sha256(file)})
        report["packages"].append({"name": name, "version": version, "files": packages})
    return report


def discover(explicit_roots: list[Path] | None = None) -> list[dict[str, Any]]:
    reports = []
    for root in steam_roots(explicit_roots):
        path = root / "steamapps" / f"appmanifest_{APP_ID}.acf"
        if not path.is_file():
            continue
        state = read_vdf(path).get("AppState", {})
        install_name = state.get("installdir", "Planet Coaster 2")
        # A malformed manifest must not redirect inspection out of common/.
        if not isinstance(install_name, str) or not re.fullmatch(r"[^/\\:]+", install_name) or install_name in {".", ".."}:
            raise VDFError("Invalid installation directory in manifest")
        reports.append(inspect_game(root / "steamapps" / "common" / install_name, state))
    return reports


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, help="Inspect an existing game folder")
    parser.add_argument("--steam-root", action="append", type=Path)
    parser.add_argument("--out", type=Path, help="Optional private report; use local/ for personal paths")
    args = parser.parse_args()
    try:
        reports = [inspect_game(args.game_dir)] if args.game_dir else discover(args.steam_root)
        result = {"schema": 1, "read_only": True, "installations": reports}
        output = json.dumps(result, indent=2, ensure_ascii=True) + "\n"
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(output, encoding="utf-8")
        print(output, end="")
        return 0 if any(r["status"] == "ready-for-inspection" for r in reports) else 2
    except (OSError, ValueError) as exc:
        print(json.dumps({"schema": 1, "read_only": True, "error": str(exc)}))
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
