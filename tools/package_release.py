"""Build the player ZIP for PC2Coop 1.x: installer, mod payload, ACSE, licenses, source.

Everything runs inside the game (Lua + DLL + Steam); no Python or browser is shipped.
Never installs or launches the game. No downloads.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parents[1]
EXE_HASH = "9da90ae2611bf41af532a30611082bd90cdda6b325e570ac63a469051e736c12"
ACSE_COMMIT = "8a843e61bcb57779778536e635d334d882cee7b1"
ACSE_FILES = ("Init.ovl", "Main.ovl", "Extras.ovl", "Manifest.xml", "Version.txt", "Readme.md", "LICENSE")
INSTALLER_FILES = ("INSTALL.cmd", "UNINSTALL.cmd", "UPDATE.cmd", "install.ps1", "update.ps1", "LIESMICH.txt")
# GitHub repository whose releases UPDATE.cmd reads ("owner/name"); set in release.json.
RELEASE_CONFIG = PROJECT / "release.json"


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
    parser.add_argument("--acse-source", type=Path, default=WORKSPACE / "work/toolchain/acse-source")
    parser.add_argument("--acse-built", type=Path, default=WORKSPACE / "work/coop-anything/local/test-install/Win64/ovldata/ACSE")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--repo", help="GitHub owner/name for updates (default: release.json)")
    args = parser.parse_args()
    repo = args.repo or ""
    if not repo and RELEASE_CONFIG.is_file():
        repo = json.loads(RELEASE_CONFIG.read_text(encoding="utf8")).get("repo", "")
    report = json.loads((PROJECT / "build/PC2CoopProbe/build-report.json").read_text(encoding="utf8"))
    version = report["probe_version"]
    out = args.out or PROJECT.parent / f"PC2Coop-{version}.zip"
    if sha(PROJECT / "build/PC2CoopProbe/Main.ovl") != report["ovl_sha256"]:
        raise RuntimeError("Probe build-report hash does not match Main.ovl")
    native = json.loads((PROJECT / "build/native/build-report.json").read_text(encoding="utf8"))
    if sha(PROJECT / "build/native/PC2CoopDiagnostic.dll") != native["sha256"]:
        raise RuntimeError("Native build-report hash does not match DLL")
    for name, expected in native["source_sha256"].items():
        if Path(name).name != name or sha(PROJECT / "native" / name) != expected:
            raise RuntimeError("Native source changed since its build; rebuild before packaging")
    if not (args.acse_source / "LICENSE").read_text(encoding="utf8").startswith("                    GNU GENERAL PUBLIC LICENSE"):
        raise RuntimeError("Unexpected ACSE license; review before distribution")
    with tempfile.TemporaryDirectory(prefix="pc2coop-release-", dir=WORKSPACE / "work") as temporary:
        stage = Path(temporary) / "PC2Coop"
        for name in INSTALLER_FILES:
            copy(PROJECT / "alpha-dist" / name, stage / name)
        copy(PROJECT / "LICENSE", stage / "LICENSE-PC2Coop.txt")
        (stage / "update.json").write_text(json.dumps({"repo": repo}) + "\n", encoding="utf8")
        for file in ("Main.ovl", "Manifest.xml"):
            copy(PROJECT / "build/PC2CoopProbe" / file, stage / "payload/PC2CoopProbe" / file)
        copy(PROJECT / "build/native/PC2CoopDiagnostic.dll", stage / "payload/PC2CoopProbe/PC2CoopDiagnostic.dll")
        for file in ACSE_FILES:
            copy(args.acse_built / file, stage / "payload/ACSE" / file)
        copy(args.acse_source / "LICENSE", stage / "licenses/ACSE-GPL-3.0.txt")
        for folder in ("probe", "native", "tools", "tests", "docs", "alpha-dist"):
            for file in sorted((PROJECT / folder).rglob("*")):
                if file.is_file() and file.suffix in {".py", ".lua", ".cpp", ".h", ".js", ".html", ".css", ".md", ".json", ".xml", ".ps1", ".cmd", ".txt"} \
                        and "__pycache__" not in file.parts:
                    copy(file, stage / "source" / file.relative_to(PROJECT))
        for name in ("LICENSE", "README.md"):
            copy(PROJECT / name, stage / "source" / name)
        for file in sorted((args.acse_source / "Source/ACSE").rglob("*")):
            if file.is_file():
                copy(file, stage / "source/third-party/ACSE" / file.relative_to(args.acse_source))
        copy(args.acse_source / "LICENSE", stage / "source/third-party/ACSE/LICENSE")
        (stage / "source/third-party/ACSE/BUILD.txt").write_text(
            f"ACSE 0.729, https://github.com/OpenNaja/ACSE, commit {ACSE_COMMIT}, GPL-3.0.\n"
            "Built unmodified with Cobra Tools 2dd9d1445608d6171c1ec1f2333cefb4d81a1317 (Python 3.11),\n"
            "one OVL per folder (Init, Main, Extras), ZLIB, with the supplied Manifest.xml.\n", encoding="utf8")
        files = [{"path": f.relative_to(stage / "payload").as_posix(), "sha256": sha(f), "bytes": f.stat().st_size}
                 for f in sorted((stage / "payload").rglob("*")) if f.is_file()]
        manifest = {"schema": 1, "version": version, "tested_steam_build": "26255360",
                    "tested_exe_sha256": EXE_HASH, "acse_commit": ACSE_COMMIT, "files": files}
        (stage / "payload-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf8")
        temp_zip = out.with_suffix(".tmp.zip")
        with zipfile.ZipFile(temp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for file in sorted(stage.rglob("*")):
                if file.is_file():
                    archive.write(file, file.relative_to(stage.parent).as_posix())
        with zipfile.ZipFile(temp_zip) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("Archive CRC check failed")
        temp_zip.replace(out)
    digest = sha(out)
    # Uploaded next to the ZIP; UPDATE.cmd refuses a download without it.
    out.with_name(out.name + ".sha256").write_text(f"{digest}  {out.name}\n", encoding="ascii")
    print(json.dumps({"zip": str(out.resolve()), "bytes": out.stat().st_size, "sha256": digest, "version": version,
                      "update_repo": repo or None}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
