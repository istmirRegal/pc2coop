"""alpha-dist/install-linux.sh on fake game folders, run with Git's bash (never WSL's).

Same cases as PC2Coop-Setup.exe (tests/test_setup_exe.py): local package, ACSE missing, a hand
copy replaced with a backup, an old journal taken over, removing, and installing the newest
release from a stand-in for GitHub with a checked SHA-256.
"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_setup_exe import FILES, _Server, make_game, make_package, release_zip, sha

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "alpha-dist" / "install-linux.sh"


def git_bash():
    try:
        exec_path = subprocess.run(["git", "--exec-path"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if not exec_path:
        return None
    for up in (Path(exec_path).parents[2] / "bin" / "bash.exe", Path(exec_path).parents[1] / "bin" / "bash.exe"):
        if up.is_file():
            return up
    return None


BASH = git_bash() if os.name == "nt" else Path("/bin/bash")


def posix(path: Path) -> str:
    return str(path).replace("\\", "/")


@unittest.skipUnless(BASH and Path(BASH).exists(), "bash not available")
class InstallLinuxTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.game = make_game(self.tmp / "game")
        self.ovl = self.game / "Win64" / "ovldata"
        self.mod = self.ovl / "PC2CoopProbe"

    def tearDown(self):
        self._tmp.cleanup()

    def run_sh(self, *args):
        result = subprocess.run([str(BASH), posix(SCRIPT), *args, "--game-dir", posix(self.game)],
                                capture_output=True, text=True, encoding="utf8", errors="replace", timeout=120)
        return result.returncode, result.stdout + result.stderr

    def journal(self):
        return json.loads((self.ovl / ".pc2coop-alpha-install.json").read_text(encoding="utf-8-sig"))

    def test_installs_the_package_and_writes_the_same_journal_as_setup(self):
        package = make_package(self.tmp / "pkg", "2.3.0")
        code, out = self.run_sh("--source", posix(package))
        self.assertEqual(code, 0, out)
        self.assertIn("result=ok action=install version=2.3.0 changed=3", out)
        for name, data in FILES.items():
            self.assertEqual((self.mod / name).read_bytes(), data)
        journal = self.journal()
        self.assertEqual(journal["version"], "2.3.0")
        self.assertEqual(sorted(f["path"] for f in journal["files"]), sorted(f"PC2CoopProbe/{n}" for n in FILES))
        code, out = self.run_sh("--source", posix(package))
        self.assertIn("changed=0", out)
        code, out = self.run_sh("--status")
        self.assertIn("installed=yes version=2.3.0 acse=yes", out)

    def test_without_acse_nothing_happens(self):
        self.game = make_game(self.tmp / "bare", acse=False)
        code, out = self.run_sh("--source", posix(make_package(self.tmp / "pkg", "2.3.0")))
        self.assertEqual(code, 3, out)
        self.assertFalse((self.game / "Win64/ovldata/PC2CoopProbe").exists())

    def test_replaces_a_hand_copy_with_a_backup_and_keeps_logs(self):
        self.mod.mkdir()
        (self.mod / "Main.ovl").write_bytes(b"ovl-v1")
        (self.mod / "pc2coop-diagnostic-1.log").write_bytes(b"log")
        code, out = self.run_sh("--source", posix(make_package(self.tmp / "pkg", "2.3.0")))
        self.assertEqual(code, 0, out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v2")
        self.assertEqual((self.mod / "pc2coop-diagnostic-1.log").read_bytes(), b"log")
        self.assertEqual([b.read_bytes() for b in (self.ovl / ".pc2coop-alpha-backups").rglob("Main.ovl")], [b"ovl-v1"])

    def test_takes_over_the_journal_of_setup_or_install_ps1(self):
        self.mod.mkdir()
        (self.mod / "Old.txt").write_bytes(b"old")
        journal = {"schema": 1, "package": "PC2Coop", "files": [
            {"path": "PC2CoopProbe/Old.txt", "sha256": sha(b"old")},
            {"path": "ACSE/Main.ovl", "sha256": sha(b"acse")}]}
        (self.ovl / ".pc2coop-alpha-install.json").write_text(json.dumps(journal, indent=4), encoding="utf-8-sig")
        code, out = self.run_sh("--source", posix(make_package(self.tmp / "pkg", "2.3.0")))
        self.assertEqual(code, 0, out)
        self.assertFalse((self.mod / "Old.txt").exists())
        self.assertIn("ACSE/Main.ovl", [f["path"] for f in self.journal()["files"]])
        self.assertEqual((self.ovl / "ACSE/Main.ovl").read_bytes(), b"acse")

    def test_damaged_package_changes_nothing(self):
        package = make_package(self.tmp / "pkg", "2.3.0")
        (package / "Mod/PC2CoopProbe/Main.ovl").write_bytes(b"broken")
        code, out = self.run_sh("--source", posix(package))
        self.assertEqual(code, 7, out)
        self.assertFalse(self.mod.exists())

    def test_uninstall_keeps_logs_and_acse(self):
        self.run_sh("--source", posix(make_package(self.tmp / "pkg", "2.3.0")))
        (self.mod / "pc2coop-diagnostic-1.log").write_bytes(b"log")
        code, out = self.run_sh("--uninstall")
        self.assertEqual(code, 0, out)
        self.assertEqual([p.name for p in self.mod.iterdir()], ["pc2coop-diagnostic-1.log"])
        self.assertTrue((self.ovl / "ACSE/Main.ovl").exists())
        self.assertFalse((self.ovl / ".pc2coop-alpha-install.json").exists())

    def serve(self, version, files, sha_text=None, extra=None):
        data = release_zip(self.tmp / ("rel-" + version), version, files, extra)
        server = _Server(data, sha_text or f"{sha(data)}  PC2Coop-{version}.zip\n", version)
        self.addCleanup(server.close)
        return server.url

    def test_without_a_package_it_installs_the_newest_release(self):
        url = self.serve("2.4.0", {"Main.ovl": b"ovl-v4", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d4"})
        code, out = self.run_sh("--api", url)
        self.assertEqual(code, 0, out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v4")
        self.assertFalse((self.mod / "PC2Coop-Setup.exe").exists())
        code, out = self.run_sh("--api", url)
        self.assertEqual(code, 10, out)

    def test_wrong_checksum_and_paths_outside_are_refused(self):
        url = self.serve("2.4.0", {"Main.ovl": b"ovl-v4", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d4"}, sha_text="0" * 64)
        code, out = self.run_sh("--api", url)
        self.assertEqual(code, 1, out)
        self.assertIn("Prüfsumme", out)
        self.assertFalse(self.mod.exists())
        url = self.serve("2.5.0", {"Main.ovl": b"x", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d"},
                         extra={"PC2Coop/../../evil.txt": b"x"})
        code, out = self.run_sh("--api", url)
        self.assertEqual(code, 1, out)
        self.assertIn("Unerwarteter Eintrag", out)


if __name__ == "__main__":
    unittest.main()
