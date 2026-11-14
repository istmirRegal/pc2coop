from pathlib import Path
import struct
import tempfile
import unittest

from pc2coop.doctor import VDFError, discover, inspect_game, parse_vdf, pe_architecture, sha256


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def fake_game(self):
        game = self.root / "steamapps" / "common" / "Planet Coaster 2"
        win64 = game / "Win64"
        (win64 / "ovldata").mkdir(parents=True)
        header = bytearray(128)
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 0x3C, 64)
        header[64:70] = b"PE\0\0\x64\x86"
        (win64 / "PlanetCoaster2.exe").write_bytes(header)
        return game

    def manifest(self, state="4", install="Planet Coaster 2"):
        steamapps = self.root / "steamapps"
        steamapps.mkdir(exist_ok=True)
        (steamapps / "appmanifest_2688950.acf").write_text(
            f'"AppState" {{ "appid" "2688950" "StateFlags" "{state}" '
            f'"installdir" "{install}" "buildid" "test-build" '
            '"LastOwner" "private-account-identifier" }', encoding="utf8"
        )

    def test_vdf_nested_escaped_windows_path_and_comments(self):
        result = parse_vdf(r'''// a comment
"libraryfolders" { "0" { "path" "C:\\Games\\Steam" "apps" { "2688950" "40" } } }
''')
        self.assertEqual(result["libraryfolders"]["0"]["path"], r"C:\Games\Steam")
        self.assertEqual(result["libraryfolders"]["0"]["apps"]["2688950"], "40")

    def test_quoted_braces_are_values(self):
        self.assertEqual(parse_vdf('"a" "{" "b" "}"'), {"a": "{", "b": "}"})

    def test_malformed_vdf_rejected(self):
        for value in ('"a" {', '"a" "unterminated', '}', '"a" "b" "a" "c"', '"a" }'):
            with self.subTest(value=value), self.assertRaises(VDFError):
                parse_vdf(value)

    def test_download_placeholder_is_not_a_complete_install(self):
        self.manifest("1026")
        report, = discover([self.root])
        self.assertEqual(report["status"], "installation-incomplete")
        self.assertIsNone(report["exe"])
        self.assertNotIn("private-account-identifier", str(report))

    def test_present_exe_during_update_is_not_ready(self):
        self.fake_game()
        self.manifest("1026")
        report, = discover([self.root])
        self.assertEqual(report["status"], "installation-incomplete")

    def test_complete_install_hashes_exe_without_changing_files(self):
        game = self.fake_game()
        self.manifest()
        paths = [file for file in self.root.rglob("*") if file.is_file()]
        before = {str(file): (file.stat().st_mtime_ns, sha256(file)) for file in paths}
        report, = discover([self.root])
        after = {str(file): (file.stat().st_mtime_ns, sha256(file)) for file in paths}
        self.assertEqual(before, after)
        self.assertEqual(report["status"], "ready-for-inspection")
        self.assertEqual(report["exe"]["architecture"], "x64")
        self.assertEqual(report["build_id"], "test-build")
        self.assertEqual(report["exe"]["sha256"], sha256(game / "Win64" / "PlanetCoaster2.exe"))
        self.assertEqual(report["in_game_qa"], "not-run")

    def test_crash_reporter_cannot_stand_in_for_game(self):
        game = self.fake_game()
        exe = game / "Win64" / "PlanetCoaster2.exe"
        exe.rename(exe.with_name("CrashReporter.exe"))
        self.assertEqual(inspect_game(game)["status"], "installation-incomplete")

    def test_manifest_cannot_escape_common_folder(self):
        for install in ("..", "../other", r"..\other", r"C:\other"):
            with self.subTest(install=install):
                self.manifest(install=install)
                with self.assertRaises(VDFError):
                    discover([self.root])

    def test_discovery_in_secondary_library(self):
        steam = self.root / "client"
        (steam / "steamapps").mkdir(parents=True)
        escaped = str(self.root).replace("\\", "\\\\")
        (steam / "steamapps" / "libraryfolders.vdf").write_text(
            '"libraryfolders" { "1" { "path" "' + escaped + '" } }', encoding="utf8"
        )
        self.fake_game()
        self.manifest()
        self.assertEqual(len(discover([steam])), 1)

    def test_package_hash_and_version_are_read(self):
        game = self.fake_game()
        package = game / "Win64" / "ovldata" / "ACSE"
        package.mkdir()
        (package / "Version.txt").write_text("0.729\n", encoding="utf8")
        (package / "Main.ovl").write_bytes(b"synthetic-test-package")
        item, = inspect_game(game)["packages"]
        self.assertEqual(item["version"], "0.729")
        self.assertEqual(item["files"][0]["sha256"], sha256(package / "Main.ovl"))

    def test_invalid_pe_offset_is_bounded(self):
        file = self.root / "invalid.exe"
        data = bytearray(64)
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 0xFFFFFFFF)
        file.write_bytes(data)
        self.assertEqual(pe_architecture(file), "invalid-pe")


if __name__ == "__main__":
    unittest.main()
