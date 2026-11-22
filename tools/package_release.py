"""Build the player ZIP for PC2Coop (GitHub, Nexus Mods and Vortex alike, ADR-023, ADR-024)
and put PC2Coop-Setup.exe next to it as a release file of its own.

    PC2Coop/LIES MICH - READ ME.txt      short, German and English
    PC2Coop/LICENSE.txt
    PC2Coop/payload-manifest.json        version, tested game build, SHA-256 of every mod file
    PC2Coop/Mod/PC2CoopProbe/...         the mod (Main.ovl, Manifest.xml, PC2CoopDiagnostic.dll)

No programs but the mod's DLL (Nexus takes no .exe, ADR-024; scripts are flagged, ADR-010),
no ACSE (ADR-009), no source (on GitHub). Setup.exe goes to GitHub as its own file; started
without a package it installs the newest release from there. The mod sits in Mod/ so that Vortex's Planet Coaster 2 extension
installs exactly PC2CoopProbe into Win64/ovldata (its "ACSE Mod" installer takes the folder
with Main.ovl and its siblings only). Never installs or launches the game. No downloads.
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
# The game EXE the release was tested with (Steam build TESTED_BUILD). Setup only shows a
# hint when the player's EXE differs; it installs anyway.
EXE_HASH = "4082bd57eeccfda54824409e9be32e952461cfb422caa201662c00deb54217f3"
TESTED_BUILD = "26494896"
README = "LIES MICH - READ ME.txt"
FORBIDDEN = (".cmd", ".bat", ".ps1", ".vbs", ".js", ".py", ".msi", ".scr", ".com")


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy(source: Path, destination: Path) -> None:
    if not source.is_file() or source.is_symlink():
        raise RuntimeError(f"Missing or unsafe input: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def payload(folder: Path) -> None:
    for file in ("Main.ovl", "Manifest.xml"):
        copy(PROJECT / "build/PC2CoopProbe" / file, folder / file)
    copy(PROJECT / "build/native/PC2CoopDiagnostic.dll", folder / "PC2CoopDiagnostic.dll")


def check(names: list[str]) -> None:
    """The rules every published ZIP must meet."""
    if not names or any(not name.startswith("PC2Coop/") or ".." in name or "\\" in name for name in names):
        raise RuntimeError("Every entry must sit under PC2Coop/")
    if any("/ACSE/" in "/" + name for name in names):
        raise RuntimeError("ACSE ended up in the package")
    if any(name.lower().endswith(FORBIDDEN) for name in names):
        raise RuntimeError("A script ended up in the package")
    programs = [name for name in names if name.lower().endswith((".exe", ".dll"))]
    if programs != ["PC2Coop/Mod/PC2CoopProbe/PC2CoopDiagnostic.dll"]:
        raise RuntimeError(f"Unexpected programs in the package: {programs}")
    for required in ("PC2Coop/payload-manifest.json", f"PC2Coop/{README}", "PC2Coop/Mod/PC2CoopProbe/Main.ovl"):
        if required not in names:
            raise RuntimeError(f"Missing in the package: {required}")


def readme(version: str) -> str:
    text = (PROJECT / "alpha-dist" / "LIESMICH.txt").read_text(encoding="utf8")
    if "{version}" not in text:
        raise RuntimeError("alpha-dist/LIESMICH.txt needs a {version} placeholder")
    return text.replace("{version}", version).replace("\r\n", "\n").replace("\n", "\r\n")


def build(out: Path, version: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="pc2coop-release-", dir=WORKSPACE / "work") as temporary:
        stage = Path(temporary) / "PC2Coop"
        stage.mkdir(parents=True)
        (stage / README).write_bytes(readme(version).encode("utf-8-sig"))
        copy(PROJECT / "LICENSE", stage / "LICENSE.txt")
        payload(stage / "Mod/PC2CoopProbe")
        files = [{"path": f.relative_to(stage / "Mod").as_posix(), "sha256": sha(f), "bytes": f.stat().st_size}
                 for f in sorted((stage / "Mod").rglob("*")) if f.is_file()]
        manifest = {"schema": 2, "version": version, "tested_steam_build": TESTED_BUILD,
                    "tested_exe_sha256": EXE_HASH, "acse_commit": "external", "files": files}
        (stage / "payload-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf8")
        temp_zip = out.with_suffix(".tmp.zip")
        with zipfile.ZipFile(temp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for file in sorted(stage.rglob("*")):
                if file.is_file():
                    archive.write(file, file.relative_to(stage.parent).as_posix())
        with zipfile.ZipFile(temp_zip) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("Archive CRC check failed")
            check(archive.namelist())
        temp_zip.replace(out)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
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
    setup = json.loads((PROJECT / "build/setup/build-report.json").read_text(encoding="utf8"))
    if sha(PROJECT / "build/setup/PC2Coop-Setup.exe") != setup["sha256"] or setup["version"] != version:
        raise RuntimeError("Setup build does not match; run tools/build_setup.py")
    for name, expected in setup["source_sha256"].items():
        if sha(PROJECT / "setup" / name) != expected:
            raise RuntimeError("Setup source changed since its build; run tools/build_setup.py")
    build(out, version)
    digest = sha(out)
    # Uploaded next to the ZIP; Setup (and the old UPDATE.cmd) refuse a download without it.
    out.with_name(out.name + ".sha256").write_text(f"{digest}  {out.name}\n", encoding="ascii")
    setup_out = out.with_name("PC2Coop-Setup.exe")
    shutil.copy2(PROJECT / "build/setup/PC2Coop-Setup.exe", setup_out)
    # Linux (Steam/Proton): the same job as Setup as a bash script, LF line ends (FEAT-013).
    linux_out = out.with_name("PC2Coop-Linux-install.sh")
    linux_out.write_bytes((PROJECT / "alpha-dist/install-linux.sh").read_bytes().replace(b"\r\n", b"\n"))
    print(json.dumps({"zip": str(out.resolve()), "bytes": out.stat().st_size, "sha256": digest, "version": version,
                      "setup": str(setup_out.resolve()), "setup_sha256": sha(setup_out)}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
