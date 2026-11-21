"""The installer's hint about the tested game build comes from the package manifest."""
import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "alpha-dist" / "install.ps1"
POWERSHELL = shutil.which("powershell") or shutil.which("pwsh")


@unittest.skipUnless(POWERSHELL, "PowerShell not available")
class TestedBuildHintTests(unittest.TestCase):
    def run_install(self, manifest_extra):
        with tempfile.TemporaryDirectory() as tmp:
            game, package = Path(tmp) / "game", Path(tmp) / "package"
            (game / "Win64" / "ovldata").mkdir(parents=True)
            package.mkdir()
            exe = game / "Win64" / "PlanetCoaster2.exe"
            exe.write_bytes(b"not the real game")
            manifest = {"schema": 1, "version": "0.0.0", "files": []}
            manifest.update(manifest_extra(hashlib.sha256(exe.read_bytes()).hexdigest()))
            (package / "payload-manifest.json").write_text(json.dumps(manifest), encoding="ascii")
            script = (f". '{INSTALL}' -LibraryOnly; "
                      f"try {{ Install-IntoGame '{game}' '{package}' 'old-hash' }} catch {{ Write-Host $_ }}")
            result = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-Command", script],
                                    capture_output=True, text=True, timeout=60)
            return result.stdout + result.stderr

    def test_hint_names_the_build_from_the_manifest(self):
        out = self.run_install(lambda real: {"tested_steam_build": "99999999", "tested_exe_sha256": "0" * 64})
        self.assertIn("getestet: Build 99999999", out)
        self.assertNotIn("26255360", out)

    def test_no_hint_when_the_game_is_the_tested_build(self):
        out = self.run_install(lambda real: {"tested_steam_build": "99999999", "tested_exe_sha256": real})
        self.assertNotIn("noch nicht getestet", out)


if __name__ == "__main__":
    unittest.main()
