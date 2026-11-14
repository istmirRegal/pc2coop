"""Create an offline friend-test ZIP from explicit redistributable inputs only.

Never installs or launches the game. No downloads; no recursive game copy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parents[1]
EXE_HASH = "9da90ae2611bf41af532a30611082bd90cdda6b325e570ac63a469051e736c12"
ACSE_COMMIT = "8a843e61bcb57779778536e635d334d882cee7b1"
RUNTIME_FILES = (
    "python.exe", "python3.dll", "python311.dll", "python311.zip",
    "vcruntime140.dll", "vcruntime140_1.dll", "_socket.pyd", "select.pyd",
    "_ssl.pyd", "_hashlib.pyd", "libcrypto-3.dll", "libssl-3.dll",
    "_ctypes.pyd", "libffi-8.dll", "_queue.pyd", "_uuid.pyd",
    "unicodedata.pyd", "pyexpat.pyd",
)
ACSE_FILES = ("Init.ovl", "Main.ovl", "Extras.ovl", "Manifest.xml", "Version.txt", "Readme.md", "LICENSE")


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy(source: Path, destination: Path) -> None:
    if not source.is_file() or source.is_symlink():
        raise RuntimeError(f"Missing or unsafe input: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=WORKSPACE / "work/toolchain/python311")
    parser.add_argument("--acse-source", type=Path, default=WORKSPACE / "work/toolchain/acse-source")
    parser.add_argument("--acse-built", type=Path, default=WORKSPACE / "work/coop-anything/local/test-install/Win64/ovldata/ACSE")
    parser.add_argument("--out", type=Path, default=PROJECT.parent / "PC2Coop.zip")
    parser.add_argument("--skip-runtime-check", action="store_true", help="For non-Windows build hosts only; recorded as not checked")
    args = parser.parse_args()
    report = json.loads((PROJECT / "build/PC2CoopProbe/build-report.json").read_text(encoding="utf8"))
    if sha(PROJECT / "build/PC2CoopProbe/Main.ovl") != report["ovl_sha256"]:
        raise RuntimeError("Probe build-report hash does not match Main.ovl")
    native_report = json.loads((PROJECT / "build/native/build-report.json").read_text(encoding="utf8"))
    if sha(PROJECT / "build/native/PC2CoopDiagnostic.dll") != native_report["sha256"]:
        raise RuntimeError("Native build-report hash does not match DLL")
    for name, expected in native_report["source_sha256"].items():
        if Path(name).name != name or sha(PROJECT / "native" / name) != expected:
            raise RuntimeError("Native source has changed since its build; rebuild before packaging")
    if not (PROJECT / "pc2coop/alpha.py").is_file():
        raise RuntimeError("Network alpha module has not been supplied; refusing to package a stub")
    if not (args.acse_source / "LICENSE").read_text(encoding="utf8").startswith("                    GNU GENERAL PUBLIC LICENSE"):
        raise RuntimeError("Unexpected ACSE license; review before distribution")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pc2coop-package-", dir=WORKSPACE / "work") as temporary:
        stage = Path(temporary) / "PC2Coop"
        stage.mkdir()
        for file in sorted((PROJECT / "alpha-dist").iterdir()):
            if file.is_file() and file.suffix in {".ps1", ".cmd", ".txt"}:
                copy(file, stage / file.name)
        for name in RUNTIME_FILES:
            copy(args.runtime / name, stage / "runtime" / name)
        (stage / "runtime/python311._pth").write_text("python311.zip\n.\n..\n", encoding="ascii")
        copy(args.runtime / "LICENSE.txt", stage / "licenses/Python.txt")
        copy(PROJECT / "LICENSE", stage / "LICENSE-PC2Coop.txt")
        for file in sorted((PROJECT / "pc2coop").glob("*.py")):
            copy(file, stage / "pc2coop" / file.name)
        for file in ("Main.ovl", "Manifest.xml"):
            copy(PROJECT / "build/PC2CoopProbe" / file, stage / "payload/PC2CoopProbe" / file)
        copy(PROJECT / "build/native/PC2CoopDiagnostic.dll", stage / "payload/PC2CoopProbe/PC2CoopDiagnostic.dll")
        for file in ACSE_FILES:
            copy(args.acse_built / file, stage / "payload/ACSE" / file)
        copy(args.acse_source / "LICENSE", stage / "licenses/ACSE-GPL-3.0.txt")
        for folder in ("pc2coop", "probe", "native", "tools", "tests", "docs", "profiles", "alpha-dist"):
            for file in sorted((PROJECT / folder).rglob("*")):
                if file.is_file() and file.suffix in {".py", ".lua", ".cpp", ".h", ".hpp", ".md", ".json", ".xml", ".ps1", ".cmd", ".txt"} and "__pycache__" not in file.parts:
                    copy(file, stage / "source" / file.relative_to(PROJECT))
        for name in ("LICENSE", "README.md"):
            copy(PROJECT / name, stage / "source" / name)
        for relative in ("build/PC2CoopProbe/build-report.json", "build/native/build-report.json"):
            copy(PROJECT / relative, stage / "source" / relative)
        for file in sorted((args.acse_source / "Source/ACSE").rglob("*")):
            if file.is_file():
                copy(file, stage / "source/third-party/ACSE" / file.relative_to(args.acse_source))
        copy(args.acse_source / "LICENSE", stage / "source/third-party/ACSE/LICENSE")
        (stage / "source/third-party/ACSE/BUILD.txt").write_text(
            "Advanced Cobra Script Extender (ACSE) 0.729\n"
            "Upstream: https://github.com/OpenNaja/ACSE\n"
            f"Pinned commit: {ACSE_COMMIT}\n"
            "License: GPL-3.0; see LICENSE. The complete Source/ACSE tree is included.\n"
            "Built for Planet Coaster 2 using Cobra Tools commit\n"
            "2dd9d1445608d6171c1ec1f2333cefb4d81a1317 (Python 3.11).\n"
            "No upstream ACSE Lua source was modified for this binary build.\n"
            "For each folder Init, Main, Extras, run Cobra Tools:\n"
            'python ovl_tool_cmd.py new -i Source/ACSE/Init -g "Planet Coaster 2" -o Init.ovl\n'
            "Repeat with Main/Main.ovl and Extras/Extras.ovl.\n"
            "Use ZLIB compression. Keep the supplied ACSE Manifest.xml beside all three OVLs.\n"
            "Cobra Tools and its build dependencies are general-purpose build tools;\n"
            "they are not needed to install or run this friend-test package.\n",
            encoding="utf8",
        )
        files = [{"path": file.relative_to(stage / "payload").as_posix(), "sha256": sha(file), "bytes": file.stat().st_size}
                 for file in sorted((stage / "payload").rglob("*")) if file.is_file()]
        manifest = {"schema": 1, "version": report["probe_version"], "supported_steam_build": "26255360",
                    "supported_exe_sha256": EXE_HASH, "acse_commit": ACSE_COMMIT, "files": files}
        (stage / "payload-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf8")
        checked = False
        if not args.skip_runtime_check:
            command = [str(stage / "runtime/python.exe"), "-c", "import socket,select,ssl,hashlib,ctypes,http.server,webbrowser,pc2coop.alpha,pc2coop.coop,pc2coop.coop_ui; print('bundled runtime import OK')"]
            subprocess.run(command, cwd=stage, check=True)
            checked = True
        audit = {"schema": 1, "version": report["probe_version"], "bundled_runtime_import_checked": checked,
                 "game_files_included": False, "payload_count": len(files), "files":
                 [{"path": file.relative_to(stage).as_posix(), "sha256": sha(file), "bytes": file.stat().st_size}
                  for file in sorted(stage.rglob("*")) if file.is_file()]}
        (stage / "package-inventory.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf8")
        temp_zip = args.out.with_suffix(".tmp.zip")
        with zipfile.ZipFile(temp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for file in sorted(stage.rglob("*")):
                if file.is_file():
                    archive.write(file, file.relative_to(stage.parent).as_posix())
        with zipfile.ZipFile(temp_zip) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("Archive CRC check failed")
        temp_zip.replace(args.out)
    print(json.dumps({"zip": str(args.out.resolve()), "bytes": args.out.stat().st_size,
                      "sha256": sha(args.out), "version": report["probe_version"], "runtime_import_checked": checked}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
