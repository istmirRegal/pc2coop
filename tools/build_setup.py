"""Compile PC2Coop-Setup.exe with the C# compiler that ships with Windows (.NET Framework 4.x).

No downloads and nothing to install: csc.exe is part of every Windows 10/11. The version
comes from Session.VERSION, the GitHub repository for updates from release.json.
Writes build/setup/PC2Coop-Setup.exe and build/setup/build-report.json.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "build" / "setup"
SOURCES = [PROJECT / "setup" / "PC2CoopSetup.cs"]
FRAMEWORK = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Microsoft.NET" / "Framework64" / "v4.0.30319"
REFERENCES = ["System.dll", "System.Core.dll", "System.Drawing.dll", "System.Windows.Forms.dll",
              "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll", "System.Web.Extensions.dll"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    session = (PROJECT / "probe/PC2CoopProbe/Main/pc2coop/session.lua").read_text(encoding="utf8")
    version = re.search(r'Session\.VERSION = "(\d+\.\d+\.\d+)"', session).group(1)
    repo = json.loads((PROJECT / "release.json").read_text(encoding="utf8"))["repo"]
    if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+", repo):
        raise SystemExit("release.json: repo must be owner/name")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    info = OUTPUT / "BuildInfo.cs"
    info.write_text(
        "// Written by tools/build_setup.py.\n"
        "static class BuildInfo\n{\n"
        f'    public const string Version = "{version}";\n'
        f'    public const string AssemblyVersion = "{version}.0";\n'
        f'    public const string Repo = "{repo}";\n'
        "}\n", encoding="ascii")
    exe = OUTPUT / "PC2Coop-Setup.exe"
    csc = FRAMEWORK / "csc.exe"
    if not csc.is_file():
        raise SystemExit(f"C# compiler not found: {csc}")
    command = [str(csc), "/nologo", "/target:winexe", "/platform:anycpu", "/optimize+", "/warnaserror+",
               "/codepage:65001", f"/win32manifest:{PROJECT / 'setup' / 'app.manifest'}", f"/out:{exe}"]
    command += [f"/reference:{FRAMEWORK / name}" for name in REFERENCES]
    command += [str(path) for path in SOURCES] + [str(info)]
    result = subprocess.run(command, cwd=OUTPUT, capture_output=True, text=True, encoding="utf8", errors="replace")
    (OUTPUT / "compile.log").write_text(result.stdout + result.stderr, encoding="utf8")
    if result.returncode:
        print(result.stdout + result.stderr)
        return result.returncode
    report = {"exe": exe.name, "sha256": sha(exe), "bytes": exe.stat().st_size, "version": version, "repo": repo,
              "source_sha256": {path.name: sha(path) for path in SOURCES + [PROJECT / "setup" / "app.manifest"]}}
    (OUTPUT / "build-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
