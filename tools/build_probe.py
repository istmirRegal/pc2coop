"""Build into this project's build/ folder. Does not install or launch anything."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

project = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cobra-tools', type=Path, required=True)
parser.add_argument('--python', type=Path, required=True, help='A Python 3.11 interpreter with Cobra Tools dependencies')
args = parser.parse_args()
root = args.cobra_tools.resolve()
entry = root / 'ovl_tool_cmd.py'
expected = '69d0b900ed0046fcda6d3eb82d9253b43cd1b26f4c443aee123ba8a2915cb386'
if not entry.is_file() or hashlib.sha256(entry.read_bytes()).hexdigest() != expected:
    raise SystemExit('Cobra Tools entry does not match pinned commit 2dd9d144; inspect/update the toolchain deliberately')
output = project / 'build' / 'PC2CoopProbe'
output.mkdir(parents=True, exist_ok=True)
report_path = output / 'build-report.json'
command = [
    str(args.python.resolve()), str(project / 'tools' / 'cobra_worker.py'),
    '--cobra-tools', str(root),
    '--source', str(project / 'probe' / 'PC2CoopProbe' / 'Main'),
    '--output', str(output / 'Main.ovl'),
    '--report', str(report_path),
]
with (output.parent / 'probe-build.log').open('w', encoding='utf8') as log:
    result = subprocess.run(command, cwd=project, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f'Build failed ({result.returncode}); inspect build/probe-build.log')
shutil.copy2(project / 'probe' / 'PC2CoopProbe' / 'Manifest.xml', output / 'Manifest.xml')
print(json.dumps(json.loads(report_path.read_text(encoding='utf8')), indent=2))
