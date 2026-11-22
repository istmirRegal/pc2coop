"""tools/read_report.py turns a problem report into a short summary."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REPORT = """﻿PC2Coop Problembericht
Erstellt: 2026-11-22 14:03 | PC2Coop 2.1.0 | Windows 10.0.22631
P0 = whoever made this report; P1, P2, ... = other players; L1, ... = Steam lobbies.

======== pc2coop-diagnostic-2.log | 2026-11-22 14:02 | newest ========
PC2COOP diagnostic=1 pid=2 thread=1 no-lua-abi=1
system|windows=10.0.22631|ram-gb=32|cpus=16|game=1.12.12.1045899|steam-build=26494896|mods=ACSE,PC2CoopProbe
[PC2CoopSession] session:net-ready|P0|P0
[PC2CoopSession] session:code|CC7UFA
[PC2CoopSession] error|session.net|x1|session.lua:12: boom
[PC2CoopSession] session:snap|role=client|players=2|stage=park
[PC2CoopSession] session:recent|first-error|msg:pres@5:160x5,msg:chat@6:29

======== pc2coop-diagnostic-1.log | 2026-11-22 13:00 | older ========
PC2COOP diagnostic=1 pid=1 thread=1 no-lua-abi=1
"""


class ReadReportTests(unittest.TestCase):
    def test_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.txt"
            path.write_text(REPORT, encoding="utf8")
            out = subprocess.run([sys.executable, str(ROOT / "tools/read_report.py"), str(path)],
                                 capture_output=True, text=True, encoding="utf8", check=True).stdout
        self.assertIn("== pc2coop-diagnostic-2.log | 2026-11-22 14:02 | newest", out)
        self.assertIn("session code(s): CC7UFA", out)
        self.assertIn("steam-build=26494896", out)
        self.assertIn("problems: 1", out)
        self.assertIn("session.lua:12: boom", out)
        self.assertIn("last snapshot: role=client|players=2|stage=park", out)
        self.assertIn("msg:pres@5:160x5", out)
        self.assertIn("== pc2coop-diagnostic-1.log", out)


if __name__ == "__main__":
    unittest.main()
