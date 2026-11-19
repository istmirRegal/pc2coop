"""Build the player ZIP for PC2Coop 1.x: installer, mod payload, license, source.

No ACSE in any package (since 1.12.3): players install the loader themselves (Nexus Mods);
the installer refuses without one.

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
INSTALLER_FILES = ("INSTALL.cmd", "UNINSTALL.cmd", "UPDATE.cmd", "install.ps1", "update.ps1", "LIESMICH.txt")
# GitHub repository whose releases UPDATE.cmd reads ("owner/name"); set in release.json.
RELEASE_CONFIG = PROJECT / "release.json"

# The Nexus package: no source folder (on GitHub), no self-updater (updates come from
# Nexus). The readme says so.
NEXUS_INSTALLER_FILES = ("INSTALL.cmd", "UNINSTALL.cmd", "install.ps1", "LIESMICH.txt")
NEXUS_README = [
    ("Planet Coaster 2 beenden, UPDATE.cmd doppelklicken. Es holt die neueste Version von\n"
     "GitHub, prueft die Pruefsumme und installiert sie. Alle Mitspieler brauchen dieselbe\n",
     "Planet Coaster 2 beenden, die neue Version von Nexus Mods in einen eigenen Ordner\n"
     "entpacken und dort INSTALL.cmd doppelklicken. Alle Mitspieler brauchen dieselbe\n"),
    ("Die neue Version liegt danach unter %LOCALAPPDATA%\\PC2Coop\\<Version>\\PC2Coop.\n", ""),
    ("- Kein eigener Server: die Verbindung laeuft ueber Steam. UPDATE.cmd spricht nur mit\n"
     "  GitHub (istmirRegal/pc2coop) und installiert nur, wenn die Pruefsumme stimmt.\n",
     "- Kein eigener Server: die Verbindung laeuft ueber Steam. Der Installer laedt nichts\n"
     "  aus dem Internet.\n"),
    ("Eigener Code: MIT (LICENSE-PC2Coop.txt, source\\).\n",
     "Eigener Code: MIT (LICENSE-PC2Coop.txt). Quellcode und Bauanleitung:\n"
     "https://github.com/istmirRegal/pc2coop\n"),
]


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
    parser.add_argument("--out", type=Path)
    parser.add_argument("--repo", help="GitHub owner/name for updates (default: release.json)")
    parser.add_argument("--nexus", action="store_true", help="Package for Nexus Mods: without source and updater")
    args = parser.parse_args()
    repo = args.repo or ""
    if not repo and RELEASE_CONFIG.is_file():
        repo = json.loads(RELEASE_CONFIG.read_text(encoding="utf8")).get("repo", "")
    report = json.loads((PROJECT / "build/PC2CoopProbe/build-report.json").read_text(encoding="utf8"))
    version = report["probe_version"]
    out = args.out or PROJECT.parent / (f"PC2Coop-{version}-nexus.zip" if args.nexus else f"PC2Coop-{version}.zip")
    if sha(PROJECT / "build/PC2CoopProbe/Main.ovl") != report["ovl_sha256"]:
        raise RuntimeError("Probe build-report hash does not match Main.ovl")
    native = json.loads((PROJECT / "build/native/build-report.json").read_text(encoding="utf8"))
    if sha(PROJECT / "build/native/PC2CoopDiagnostic.dll") != native["sha256"]:
        raise RuntimeError("Native build-report hash does not match DLL")
    for name, expected in native["source_sha256"].items():
        if Path(name).name != name or sha(PROJECT / "native" / name) != expected:
            raise RuntimeError("Native source changed since its build; rebuild before packaging")
    with tempfile.TemporaryDirectory(prefix="pc2coop-release-", dir=WORKSPACE / "work") as temporary:
        stage = Path(temporary) / "PC2Coop"
        for name in (NEXUS_INSTALLER_FILES if args.nexus else INSTALLER_FILES):
            copy(PROJECT / "alpha-dist" / name, stage / name)
        if args.nexus:
            readme = (stage / "LIESMICH.txt").read_text(encoding="utf8")
            for old, new in NEXUS_README:
                if readme.count(old) != 1:
                    raise RuntimeError(f"LIESMICH changed; update NEXUS_README: {old[:40]!r}")
                readme = readme.replace(old, new)
            (stage / "LIESMICH.txt").write_text(readme, encoding="utf8")
        copy(PROJECT / "LICENSE", stage / "LICENSE-PC2Coop.txt")
        if not args.nexus:
            (stage / "update.json").write_text(json.dumps({"repo": repo}) + "\n", encoding="utf8")
        for file in ("Main.ovl", "Manifest.xml"):
            copy(PROJECT / "build/PC2CoopProbe" / file, stage / "payload/PC2CoopProbe" / file)
        copy(PROJECT / "build/native/PC2CoopDiagnostic.dll", stage / "payload/PC2CoopProbe/PC2CoopDiagnostic.dll")
        for folder in (() if args.nexus else ("probe", "native", "tools", "tests", "docs", "alpha-dist")):
            for file in sorted((PROJECT / folder).rglob("*")):
                if file.is_file() and file.suffix in {".py", ".lua", ".cpp", ".h", ".js", ".html", ".css", ".md", ".json", ".xml", ".ps1", ".cmd", ".txt"} \
                        and "__pycache__" not in file.parts:
                    copy(file, stage / "source" / file.relative_to(PROJECT))
        if not args.nexus:
            for name in ("LICENSE", "README.md"):
                copy(PROJECT / name, stage / "source" / name)
        files = [{"path": f.relative_to(stage / "payload").as_posix(), "sha256": sha(f), "bytes": f.stat().st_size}
                 for f in sorted((stage / "payload").rglob("*")) if f.is_file()]
        manifest = {"schema": 1, "version": version, "tested_steam_build": "26255360",
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
            if any(name.startswith("PC2Coop/payload/ACSE/") or "/third-party/ACSE/" in name for name in archive.namelist()):
                raise RuntimeError("ACSE ended up in the package")
        temp_zip.replace(out)
    digest = sha(out)
    # Uploaded next to the ZIP; UPDATE.cmd refuses a download without it.
    if not args.nexus:
        out.with_name(out.name + ".sha256").write_text(f"{digest}  {out.name}\n", encoding="ascii")
    print(json.dumps({"zip": str(out.resolve()), "bytes": out.stat().st_size, "sha256": digest, "version": version,
                      "update_repo": repo or None}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
