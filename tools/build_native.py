"""Compile the original diagnostic DLL with an existing x64 MSVC/Windows SDK."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--msvc', type=Path, required=True, help='MSVC version root')
parser.add_argument('--sdk', type=Path, required=True, help='Windows Kits/10 root')
parser.add_argument('--sdk-version', required=True)
args = parser.parse_args()
project = Path(__file__).resolve().parents[1]
output = project / 'build' / 'native'
output.mkdir(parents=True, exist_ok=True)
compiler = args.msvc / 'bin' / 'Hostx64' / 'x64' / 'cl.exe'
include = args.sdk / 'Include' / args.sdk_version
library = args.sdk / 'Lib' / args.sdk_version
command = [str(compiler), '/nologo', '/LD', '/MT', '/O2', '/W4', '/WX',
           '/std:c++17', '/EHsc', '/guard:cf', '/utf-8',
           '/I' + str(args.msvc / 'include')]
command += ['/I' + str(include / p) for p in ('ucrt', 'shared', 'um')]
command += [str(project / 'native' / 'diagnostic.cpp'), str(project / 'native' / 'string_probe.cpp'),
            str(project / 'native' / 'steam_net.cpp'),
            '/Fo' + str(output) + '\\', '/link', '/DYNAMICBASE',
            '/NXCOMPAT', '/MACHINE:X64', '/OUT:' + str(output / 'PC2CoopDiagnostic.dll'),
            '/LIBPATH:' + str(args.msvc / 'lib' / 'x64')]
command += ['/LIBPATH:' + str(library / p / 'x64') for p in ('ucrt', 'um')]
command += ['kernel32.lib', 'bcrypt.lib', 'user32.lib']
result = subprocess.run(command, cwd=output, text=True, capture_output=True)
(output / 'compile.log').write_text(result.stdout + result.stderr, encoding='utf8')
if result.returncode:
    raise SystemExit(result.stdout + result.stderr)
dll = output / 'PC2CoopDiagnostic.dll'
report = {'schema': 1, 'architecture': 'x64', 'lua_abi_access': 'guarded-read-only; game-string-api',
          'bytes': dll.stat().st_size, 'sha256': hashlib.sha256(dll.read_bytes()).hexdigest(),
          'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((project/'native').glob('*.cpp'))},
          'runtime_tested': False}
(output / 'build-report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf8')
print(json.dumps(report, indent=2))
