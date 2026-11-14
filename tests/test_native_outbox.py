"""Builds tests/native/test_outbox.cpp (real steam_net.cpp + fake Steam) and runs it.

Skipped unless MSVC is configured: set PC2COOP_MSVC (MSVC version root), PC2COOP_SDK
(Windows Kits/10 root) and PC2COOP_SDK_VERSION, the same values tools/build_native.py takes.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MSVC, SDK, SDK_VERSION = (os.environ.get(k) for k in ('PC2COOP_MSVC', 'PC2COOP_SDK', 'PC2COOP_SDK_VERSION'))


@unittest.skipUnless(MSVC and SDK and SDK_VERSION, 'MSVC not configured (PC2COOP_MSVC, PC2COOP_SDK, PC2COOP_SDK_VERSION)')
class NativeOutboxTests(unittest.TestCase):
    def test_file_and_messages_survive_a_full_send_buffer(self):
        msvc, include, lib = Path(MSVC), Path(SDK) / 'Include' / SDK_VERSION, Path(SDK) / 'Lib' / SDK_VERSION
        with tempfile.TemporaryDirectory() as out:
            exe = Path(out) / 'test_outbox.exe'
            command = [str(msvc / 'bin/Hostx64/x64/cl.exe'), '/nologo', '/MT', '/O2', '/W4', '/std:c++17', '/EHsc', '/utf-8',
                       '/I' + str(msvc / 'include')] + ['/I' + str(include / p) for p in ('ucrt', 'shared', 'um')] + [
                       str(ROOT / 'tests/native/test_outbox.cpp'), '/Fo' + out + '\\', '/Fe' + str(exe), '/link',
                       '/LIBPATH:' + str(msvc / 'lib/x64')] + ['/LIBPATH:' + str(lib / p / 'x64') for p in ('ucrt', 'um')] + [
                       'kernel32.lib', 'user32.lib']
            build = subprocess.run(command, cwd=out, capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(exe)], cwd=out, capture_output=True, text=True, timeout=120)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('PASS', run.stdout)


if __name__ == '__main__':
    unittest.main()
