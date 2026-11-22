"""PC2Coop-Setup.exe on fake game folders (command line only, never the real game).

Needs build/setup/PC2Coop-Setup.exe (tools/build_setup.py); skipped without it.
Every run gets its own LOCALAPPDATA and TEMP, so nothing lands in the real profile.
"""
import hashlib
import http.server
import json
import os
import subprocess
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "build" / "setup" / "PC2Coop-Setup.exe"
FILES = {"Main.ovl": b"ovl-v2", "Manifest.xml": b"<ContentPack/>", "PC2CoopDiagnostic.dll": b"dll-v2"}


def game_running() -> bool:
    """Setup refuses to work while Planet Coaster 2 runs (also the test copy): skip then."""
    if os.name != "nt":
        return False
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq PlanetCoaster2.exe", "/NH"], capture_output=True).stdout
    out = out.decode("ascii", errors="replace")
    return "PlanetCoaster2.exe" in out


READY = SETUP.is_file() and os.name == "nt" and not game_running()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_package(folder: Path, version: str, files=FILES) -> Path:
    mod = folder / "Mod" / "PC2CoopProbe"
    mod.mkdir(parents=True)
    entries = []
    for name, data in files.items():
        (mod / name).write_bytes(data)
        entries.append({"path": f"PC2CoopProbe/{name}", "sha256": sha(data), "bytes": len(data)})
    manifest = {"schema": 2, "version": version, "tested_steam_build": "1", "tested_exe_sha256": "0" * 64, "files": entries}
    (folder / "payload-manifest.json").write_text(json.dumps(manifest), encoding="utf8")
    return folder


def make_game(folder: Path, acse=True) -> Path:
    (folder / "Win64" / "ovldata").mkdir(parents=True)
    (folder / "PlanetCoaster2.exe").write_bytes(b"not the game")   # like Steam: in the main folder
    if acse:
        (folder / "Win64" / "ovldata" / "ACSE").mkdir()
        (folder / "Win64" / "ovldata" / "ACSE" / "Main.ovl").write_bytes(b"acse")
    return folder


@unittest.skipUnless(READY, "PC2Coop-Setup.exe not built, or Planet Coaster 2 is running")
class SetupTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.game = make_game(self.tmp / "game")
        self.mod = self.game / "Win64" / "ovldata" / "PC2CoopProbe"
        (self.tmp / "local").mkdir()
        (self.tmp / "temp").mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def run_setup(self, *args, package=None):
        env = dict(os.environ, LOCALAPPDATA=str(self.tmp / "local"), TEMP=str(self.tmp / "temp"), TMP=str(self.tmp / "temp"))
        command = [str(SETUP), *args, "--game", str(self.game), "--lang", "de"]
        if package:
            command += ["--source", str(package)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf8", env=env, timeout=120)
        return result.returncode, result.stdout

    def test_install_copies_checks_and_writes_journal(self):
        package = make_package(self.tmp / "pkg", "2.1.0")
        code, out = self.run_setup("--install", package=package)
        self.assertEqual(code, 0, out)
        self.assertIn("result=ok action=install changed=3", out)
        for name, data in FILES.items():
            self.assertEqual((self.mod / name).read_bytes(), data)
        journal = json.loads((self.game / "Win64/ovldata/.pc2coop-alpha-install.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(journal["version"], "2.1.0")
        self.assertEqual(sorted(f["path"] for f in journal["files"]), sorted(f"PC2CoopProbe/{n}" for n in FILES))
        code, out = self.run_setup("--install", package=package)
        self.assertIn("changed=0", out)
        code, out = self.run_setup("--status")
        self.assertIn("installed=yes version=2.1.0", out)

    def test_without_acse_nothing_happens(self):
        self.game = make_game(self.tmp / "bare", acse=False)
        code, out = self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        self.assertEqual(code, 3, out)
        self.assertIn("ACSE fehlt", out)
        self.assertFalse((self.game / "Win64/ovldata/PC2CoopProbe").exists())

    def test_replaces_a_hand_copied_older_version_with_backup(self):
        self.mod.mkdir()
        (self.mod / "Main.ovl").write_bytes(b"ovl-v1")
        (self.mod / "pc2coop-diagnostic-1.log").write_bytes(b"log")
        code, out = self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        self.assertEqual(code, 0, out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v2")
        self.assertEqual((self.mod / "pc2coop-diagnostic-1.log").read_bytes(), b"log")
        backups = list((self.game / "Win64/ovldata/.pc2coop-alpha-backups").rglob("Main.ovl"))
        self.assertEqual([b.read_bytes() for b in backups], [b"ovl-v1"])

    def test_takes_over_a_journal_from_the_old_script_installer(self):
        self.mod.mkdir()
        (self.mod / "Main.ovl").write_bytes(b"ovl-v1")
        (self.mod / "Old.txt").write_bytes(b"old")
        journal = {"schema": 1, "package": "PC2Coop", "installed_utc": "x", "files": [
            {"path": "PC2CoopProbe/Main.ovl", "sha256": sha(b"ovl-v1")},
            {"path": "PC2CoopProbe/Old.txt", "sha256": sha(b"old")},
            {"path": "ACSE/Main.ovl", "sha256": sha(b"acse")}]}
        (self.game / "Win64/ovldata/.pc2coop-alpha-install.json").write_text(json.dumps(journal), encoding="utf-8-sig")
        code, out = self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        self.assertEqual(code, 0, out)
        self.assertFalse((self.mod / "Old.txt").exists(), "a file the old version owned and the new one does not have goes")
        self.assertEqual((self.game / "Win64/ovldata/ACSE/Main.ovl").read_bytes(), b"acse")
        paths = [f["path"] for f in json.loads((self.game / "Win64/ovldata/.pc2coop-alpha-install.json").read_text(encoding="utf-8-sig"))["files"]]
        self.assertIn("ACSE/Main.ovl", paths)

    def test_refuses_when_vortex_manages_the_mod(self):
        self.mod.mkdir()
        staging = self.tmp / "staging.ovl"
        staging.write_bytes(b"vortex")
        os.link(staging, self.mod / "Main.ovl")
        code, out = self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        self.assertEqual(code, 4, out)
        self.assertIn("Vortex", out)
        self.assertEqual(staging.read_bytes(), b"vortex")

    def test_damaged_package_changes_nothing(self):
        package = make_package(self.tmp / "pkg", "2.1.0")
        (package / "Mod/PC2CoopProbe/Main.ovl").write_bytes(b"broken")
        code, out = self.run_setup("--install", package=package)
        self.assertEqual(code, 7, out)
        self.assertFalse(self.mod.exists())

    def test_a_package_folder_with_damaged_mod_files_says_unpack_again(self):
        package = make_package(self.tmp / "pkg", "2.1.0")
        (package / "payload-manifest.json").write_text("{}", encoding="utf8")
        code, out = self.run_setup("--install", package=package)
        self.assertNotEqual(code, 0, out)

    def test_uninstall_keeps_logs_and_acse(self):
        self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        (self.mod / "pc2coop-diagnostic-1.log").write_bytes(b"log")
        code, out = self.run_setup("--uninstall")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(p.name for p in self.mod.iterdir()), ["pc2coop-diagnostic-1.log"])
        self.assertTrue((self.game / "Win64/ovldata/ACSE/Main.ovl").exists())
        self.assertFalse((self.game / "Win64/ovldata/.pc2coop-alpha-install.json").exists())

    def test_exe_in_win64_is_accepted_too(self):
        (self.game / "PlanetCoaster2.exe").rename(self.game / "Win64" / "PlanetCoaster2.exe")
        code, out = self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        self.assertEqual(code, 0, out)

    def test_picking_win64_or_ovldata_finds_the_game(self):
        package = make_package(self.tmp / "pkg", "2.1.0")
        for picked in (self.game / "Win64", self.game / "Win64" / "ovldata"):
            env = dict(os.environ, LOCALAPPDATA=str(self.tmp / "local"))
            result = subprocess.run([str(SETUP), "--status", "--game", str(picked)], capture_output=True, text=True,
                                    encoding="utf8", env=env, timeout=120)
            self.assertIn("game=" + str(self.game), result.stdout)

    def test_no_game_folder(self):
        self.game = self.tmp / "empty"
        self.game.mkdir()
        code, out = self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.1.0"))
        self.assertEqual(code, 5, out)


class _Server:
    """GitHub stand-in: /latest (release JSON), /zip, /sha."""

    def __init__(self, zip_bytes: bytes, sha_text: str, version: str):
        files = {"/zip": zip_bytes, "/sha": sha_text.encode("ascii")}

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(handler):
                base = f"http://127.0.0.1:{handler.server.server_port}"
                if handler.path == "/latest":
                    body = json.dumps({"tag_name": "v" + version, "body": "notes", "assets": [
                        {"name": f"PC2Coop-{version}.zip", "browser_download_url": base + "/zip"},
                        {"name": f"PC2Coop-{version}.zip.sha256", "browser_download_url": base + "/sha"}]}).encode()
                else:
                    body = files.get(handler.path)
                if body is None:
                    handler.send_response(404); handler.end_headers(); return
                handler.send_response(200)
                handler.send_header("Content-Length", str(len(body)))
                handler.end_headers()
                handler.wfile.write(body)

            def log_message(handler, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}/latest"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def release_zip(folder: Path, version: str, files, extra=None) -> bytes:
    package = make_package(folder / "stage" / "PC2Coop", version, files)
    out = folder / "release.zip"
    with zipfile.ZipFile(out, "w") as archive:
        for file in sorted(package.rglob("*")):
            if file.is_file():
                archive.write(file, file.relative_to(package.parent).as_posix())
        archive.writestr("PC2Coop/PC2Coop-Setup.exe", b"never run")
        for name, data in (extra or {}).items():
            archive.writestr(name, data)
    return out.read_bytes()


@unittest.skipUnless(READY, "PC2Coop-Setup.exe not built, or Planet Coaster 2 is running")
class UpdateTests(SetupTests.__bases__[0]):
    setUp = SetupTests.setUp
    tearDown = SetupTests.tearDown
    run_setup = SetupTests.run_setup

    def serve(self, version, files, sha_text=None, extra=None):
        data = release_zip(self.tmp / "rel", version, files, extra)
        server = _Server(data, sha_text or f"{sha(data)}  PC2Coop-{version}.zip\n", version)
        self.addCleanup(server.close)
        return server.url

    def installed_v1(self):
        self.run_setup("--install", package=make_package(self.tmp / "pkg", "2.0.0",
                                                         {"Main.ovl": b"ovl-v1", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d1"}))

    def test_setup_alone_installs_the_newest_release(self):
        # 2.2.0: Nexus takes no programs, so Setup is its own download; without a package next
        # to it, it installs the newest release from GitHub (here a stand-in).
        url = self.serve("2.2.0", {"Main.ovl": b"ovl-v3", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d3"})
        code, out = self.run_setup("--install", "--api", url, package=self.tmp / "nothing-here")
        self.assertEqual(code, 0, out)
        self.assertIn("source=github version=2.2.0", out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v3")

    def test_update_downloads_checks_and_installs(self):
        self.installed_v1()
        url = self.serve("2.2.0", {"Main.ovl": b"ovl-v3", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d3"})
        code, out = self.run_setup("--check-update", "--api", url)
        self.assertIn("latest=2.2.0 current=2.0.0 update=yes", out)
        code, out = self.run_setup("--update", "--api", url)
        self.assertEqual(code, 0, out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v3")
        self.assertFalse((self.mod / "PC2Coop-Setup.exe").exists())
        code, out = self.run_setup("--update", "--api", url)
        self.assertEqual(code, 10, out)
        self.assertEqual(list((self.tmp / "temp").iterdir()), [], "download folder is cleaned up")

    def test_wrong_checksum_installs_nothing(self):
        self.installed_v1()
        url = self.serve("2.2.0", {"Main.ovl": b"ovl-v3", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d3"}, sha_text="0" * 64)
        code, out = self.run_setup("--update", "--api", url)
        self.assertEqual(code, 1, out)
        self.assertIn("Prüfsumme", out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v1")

    def test_zip_with_a_path_outside_is_refused(self):
        self.installed_v1()
        url = self.serve("2.2.0", {"Main.ovl": b"ovl-v3", "Manifest.xml": b"m", "PC2CoopDiagnostic.dll": b"d3"},
                         extra={"PC2Coop/../../evil.txt": b"x"})
        code, out = self.run_setup("--update", "--api", url)
        self.assertEqual(code, 1, out)
        self.assertIn("Unerwarteter Eintrag", out)
        self.assertEqual((self.mod / "Main.ovl").read_bytes(), b"ovl-v1")
        self.assertFalse((self.tmp / "evil.txt").exists())


if __name__ == "__main__":
    unittest.main()
