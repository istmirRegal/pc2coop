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
# The game EXE the release was tested with (Steam build TESTED_BUILD; informational in the manifest).
EXE_HASH = "4082bd57eeccfda54824409e9be32e952461cfb422caa201662c00deb54217f3"
TESTED_BUILD = "26494896"
INSTALLER_FILES = ("INSTALL.cmd", "UNINSTALL.cmd", "UPDATE.cmd", "install.ps1", "update.ps1", "LIESMICH.txt", "README-EN.txt")
# GitHub repository whose releases UPDATE.cmd reads ("owner/name"); set in release.json.
RELEASE_CONFIG = PROJECT / "release.json"

# The Nexus package: no scripts at all (a .cmd that starts PowerShell is what virus scanners
# flag), no source folder (on GitHub), no self-updater. It holds the game's own folder layout
# (Win64\ovldata\PC2CoopProbe) to copy into the game folder; the readme says so.
NEXUS_README = [
    ("0. ACSE (Mod-Loader fuer Planet Coaster 2) von Nexus Mods installieren, falls noch nicht\n"
     "   vorhanden. Es ist nicht in diesem Paket. Wer schon eine fruehere PC2Coop-Version hatte,\n"
     "   hat ACSE bereits. Ohne ACSE bricht INSTALL.cmd mit einem Hinweis ab und installiert nichts.\n"
     "1. ZIP in einen eigenen Ordner entpacken.\n"
     "2. Planet Coaster 2 beenden, INSTALL.cmd doppelklicken. Der Steam-Ordner wird gesucht.\n"
     "   Falls nicht gefunden: INSTALL.cmd -GameDir \"D:\\SteamLibrary\\steamapps\\common\\Planet Coaster 2\"\n",
     "0. ACSE (Mod-Loader fuer Planet Coaster 2) von Nexus Mods installieren, falls noch nicht\n"
     "   vorhanden. Es ist nicht in diesem Paket; ohne ACSE startet PC2Coop nicht.\n"
     "1. Planet Coaster 2 beenden.\n"
     "2. Den Ordner \"Win64\" aus diesem ZIP in den Spielordner kopieren (Steam: Rechtsklick auf\n"
     "   Planet Coaster 2 -> Verwalten -> Lokale Dateien durchsuchen). Danach liegen in\n"
     "   Win64\\ovldata\\PC2CoopProbe die Dateien Main.ovl, Manifest.xml und PC2CoopDiagnostic.dll.\n"
     "   Eine fruehere Installation wird dabei einfach ueberschrieben.\n"),
    ("Planet Coaster 2 beenden, UPDATE.cmd doppelklicken. Es holt die neueste Version von\n"
     "GitHub, prueft die Pruefsumme und installiert sie. Alle Mitspieler brauchen dieselbe\n",
     "Planet Coaster 2 beenden, die neue Version von Nexus Mods genauso in den Spielordner\n"
     "kopieren und die alten Dateien ersetzen. Alle Mitspieler brauchen dieselbe\n"),
    ("Die neue Version liegt danach unter %LOCALAPPDATA%\\PC2Coop\\<Version>\\PC2Coop.\n", ""),
    ("- Kein eigener Server: die Verbindung laeuft ueber Steam. UPDATE.cmd spricht nur mit\n"
     "  GitHub (istmirRegal/pc2coop) und installiert nur, wenn die Pruefsumme stimmt.\n",
     "- Kein eigener Server: die Verbindung laeuft ueber Steam.\n"),
    ("Entfernen\nPC2 beenden, UNINSTALL.cmd doppelklicken.\n",
     "Entfernen\nPC2 beenden, im Spielordner den Ordner Win64\\ovldata\\PC2CoopProbe loeschen.\n"),
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


def payload(folder: Path) -> None:
    for file in ("Main.ovl", "Manifest.xml"):
        copy(PROJECT / "build/PC2CoopProbe" / file, folder / file)
    copy(PROJECT / "build/native/PC2CoopDiagnostic.dll", folder / "PC2CoopDiagnostic.dll")


def check(names: list[str], scripts_allowed: bool = True) -> None:
    if any("/ACSE/" in "/" + name for name in names):
        raise RuntimeError("ACSE ended up in the package")
    if not scripts_allowed and any(name.lower().endswith((".cmd", ".bat", ".ps1", ".exe", ".vbs", ".js")) for name in names):
        raise RuntimeError("Scripts ended up in the Nexus package")


def nexus(stage: Path, out: Path, version: str) -> int:
    """Copy-in package: Win64\\ovldata\\PC2CoopProbe plus readme and license, nothing that runs."""
    readme = (PROJECT / "alpha-dist" / "LIESMICH.txt").read_text(encoding="utf8")
    for old, new in NEXUS_README:
        if readme.count(old) != 1:
            raise RuntimeError(f"LIESMICH changed; update NEXUS_README: {old[:40]!r}")
        readme = readme.replace(old, new)
    if "INSTALL.cmd" in readme or "UPDATE.cmd" in readme:
        raise RuntimeError("Nexus readme still mentions the installer")
    stage.mkdir(parents=True)
    (stage / "PC2Coop-LIESMICH.txt").write_text(readme, encoding="utf8")
    # English readme (ADR-022): covers the GitHub and the Nexus package in one text.
    copy(PROJECT / "alpha-dist" / "README-EN.txt", stage / "PC2Coop-README-EN.txt")
    copy(PROJECT / "LICENSE", stage / "PC2Coop-LICENSE.txt")
    payload(stage / "Win64/ovldata/PC2CoopProbe")
    temp_zip = out.with_suffix(".tmp.zip")
    with zipfile.ZipFile(temp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in sorted(stage.rglob("*")):
            if file.is_file():
                archive.write(file, file.relative_to(stage).as_posix())
    with zipfile.ZipFile(temp_zip) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Archive CRC check failed")
        check(archive.namelist(), scripts_allowed=False)
    temp_zip.replace(out)
    print(json.dumps({"zip": str(out.resolve()), "bytes": out.stat().st_size, "sha256": sha(out), "version": version}, indent=2))
    return 0


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
        if args.nexus:
            return nexus(Path(temporary) / "nexus", out, version)
        stage = Path(temporary) / "PC2Coop"
        for name in INSTALLER_FILES:
            copy(PROJECT / "alpha-dist" / name, stage / name)
        copy(PROJECT / "LICENSE", stage / "LICENSE-PC2Coop.txt")
        (stage / "update.json").write_text(json.dumps({"repo": repo}) + "\n", encoding="utf8")
        payload(stage / "payload/PC2CoopProbe")
        for folder in ("probe", "native", "tools", "tests", "docs", "alpha-dist"):
            for file in sorted((PROJECT / folder).rglob("*")):
                if file.is_file() and file.suffix in {".py", ".lua", ".cpp", ".h", ".js", ".html", ".css", ".md", ".json", ".xml", ".ps1", ".cmd", ".txt"} \
                        and "__pycache__" not in file.parts:
                    copy(file, stage / "source" / file.relative_to(PROJECT))
        for name in ("LICENSE", "README.md"):
            copy(PROJECT / name, stage / "source" / name)
        files = [{"path": f.relative_to(stage / "payload").as_posix(), "sha256": sha(f), "bytes": f.stat().st_size}
                 for f in sorted((stage / "payload").rglob("*")) if f.is_file()]
        manifest = {"schema": 1, "version": version, "tested_steam_build": TESTED_BUILD,
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
    digest = sha(out)
    # Uploaded next to the ZIP; UPDATE.cmd refuses a download without it.
    out.with_name(out.name + ".sha256").write_text(f"{digest}  {out.name}\n", encoding="ascii")
    print(json.dumps({"zip": str(out.resolve()), "bytes": out.stat().st_size, "sha256": digest, "version": version,
                      "update_repo": repo or None}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
