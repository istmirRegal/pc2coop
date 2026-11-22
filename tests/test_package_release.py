"""The one player ZIP (ADR-023): layout, no scripts, Vortex puts exactly the mod into ovldata,
and Setup installs from the unpacked ZIP. Needs the build outputs; skipped without them."""
import json
import ntpath
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import package_release  # noqa: E402

BUILT = all((ROOT / p).is_file() for p in ("build/setup/PC2Coop-Setup.exe", "build/PC2CoopProbe/Main.ovl",
                                            "build/native/PC2CoopDiagnostic.dll", "build/PC2CoopProbe/build-report.json"))

# Vortex's Planet Coaster 2 extension (game-planetcoaster2, index.js): installers by priority.
ROOT_FOLDERS = ["Win64", "Blueprints", "TerrainSkirts", "ProvidedCustomTextures", "Parks", "Movies"]


def vortex_install(entries):
    """Which installer of the PC2 extension takes the archive, and where each file goes."""
    files = []
    for name in entries:
        parts = name.split("/")
        for i in range(1, len(parts)):
            files.append("\\".join(parts[:i]) + "\\")
        files.append(name.replace("/", "\\"))
    files = list(dict.fromkeys(files))
    base = lambda f: ntpath.basename(f.rstrip("\\"))
    has_fomod = any(base(f).lower() == "moduleconfig.xml" and base(ntpath.dirname(f)).lower() == "fomod" for f in files)
    if any(base(f) == "ACSE" for f in files):
        return "acse", None
    if any(base(f) in ROOT_FOLDERS for f in files) and not has_fomod:
        return "root", None
    mod_file = next((f for f in files if base(f).lower() == "main.ovl"), None)
    if mod_file is None:
        return "other", None
    root_path = ntpath.dirname(mod_file)
    if base(root_path) != ".":
        mod_file, root_path = root_path, ntpath.dirname(root_path)
    idx = mod_file.rfind(base(mod_file))
    prefix = "" if root_path == "." else root_path + "\\"
    chosen = [f for f in files if not f.endswith("\\") and f.startswith(prefix)]
    return "acse-mod", sorted(f[idx:] for f in chosen)  # relative to Win64\ovldata


class CheckRuleTests(unittest.TestCase):
    good = ["PC2Coop/LIES MICH - READ ME.txt", "PC2Coop/payload-manifest.json",
            "PC2Coop/Mod/PC2CoopProbe/Main.ovl", "PC2Coop/Mod/PC2CoopProbe/PC2CoopDiagnostic.dll"]

    def test_good_layout_passes(self):
        package_release.check(self.good)

    def test_scripts_acse_and_stray_paths_are_refused(self):
        # 2.2.0: no .exe at all in the ZIP (Nexus takes no programs, ADR-024).
        for extra in ("PC2Coop/INSTALL.cmd", "PC2Coop/install.ps1", "PC2Coop/Mod/ACSE/Main.ovl", "Other/file.txt",
                      "PC2Coop/tool.exe", "PC2Coop/PC2Coop-Setup.exe", "PC2Coop/../x.txt"):
            with self.assertRaises(RuntimeError, msg=extra):
                package_release.check(self.good + [extra])

    def test_vortex_takes_only_the_mod_folder(self):
        kind, targets = vortex_install(self.good)
        self.assertEqual(kind, "acse-mod")
        self.assertEqual(targets, ["PC2CoopProbe\\Main.ovl", "PC2CoopProbe\\PC2CoopDiagnostic.dll"])

    def test_the_old_layout_would_have_spilled_into_the_game_folder(self):
        kind, _ = vortex_install(["PC2Coop/PC2Coop-Setup.exe", "PC2Coop/Win64/ovldata/PC2CoopProbe/Main.ovl"])
        self.assertEqual(kind, "root")


@unittest.skipUnless(BUILT and os.name == "nt", "build outputs missing")
class BuiltZipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.tmp = Path(cls._tmp.name)
        cls.zip = cls.tmp / "PC2Coop-test.zip"
        version = json.loads((ROOT / "build/PC2CoopProbe/build-report.json").read_text(encoding="utf8"))["probe_version"]
        cls.manifest = package_release.build(cls.zip, version)
        with zipfile.ZipFile(cls.zip) as archive:
            cls.names = archive.namelist()
            archive.extractall(cls.tmp / "unpacked")

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_layout(self):
        self.assertEqual(sorted(self.names), sorted([
            "PC2Coop/LICENSE.txt", "PC2Coop/LIES MICH - READ ME.txt",
            "PC2Coop/payload-manifest.json", "PC2Coop/Mod/PC2CoopProbe/Main.ovl",
            "PC2Coop/Mod/PC2CoopProbe/Manifest.xml", "PC2Coop/Mod/PC2CoopProbe/PC2CoopDiagnostic.dll"]))
        readme = (self.tmp / "unpacked/PC2Coop/LIES MICH - READ ME.txt").read_text(encoding="utf-8-sig")
        self.assertIn("PC2Coop " + self.manifest["version"], readme)
        self.assertNotIn("{version}", readme)

    def test_vortex(self):
        kind, targets = vortex_install(self.names)
        self.assertEqual(kind, "acse-mod")
        self.assertEqual(targets, ["PC2CoopProbe\\Main.ovl", "PC2CoopProbe\\Manifest.xml", "PC2CoopProbe\\PC2CoopDiagnostic.dll"])

    def test_setup_installs_from_the_unpacked_zip(self):
        from test_setup_exe import game_running
        if game_running():
            self.skipTest("Setup refuses while Planet Coaster 2 runs")
        game = self.tmp / "game"
        (game / "Win64/ovldata/ACSE").mkdir(parents=True)
        (game / "PlanetCoaster2.exe").write_bytes(b"x")
        (game / "Win64/ovldata/ACSE/Main.ovl").write_bytes(b"acse")
        (self.tmp / "local").mkdir(exist_ok=True)
        env = dict(os.environ, LOCALAPPDATA=str(self.tmp / "local"))
        result = subprocess.run([str(ROOT / "build/setup/PC2Coop-Setup.exe"), "--install", "--game", str(game),
                                 "--source", str(self.tmp / "unpacked/PC2Coop")],
                                capture_output=True, text=True, encoding="utf8", env=env, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout)
        for entry in self.manifest["files"]:
            installed = game / "Win64/ovldata" / entry["path"]
            self.assertEqual(package_release.sha(installed), entry["sha256"])


if __name__ == "__main__":
    unittest.main()
