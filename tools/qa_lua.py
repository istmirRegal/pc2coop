"""Dev research: run a small Lua script in the prepared test copy (needs the dev flag).

Example: python tools/qa_lua.py --mod-dir <test copy>/Win64/ovldata/PC2CoopProbe --pid 123 probe.lua
The script runs as a coroutine with emit(text), waitFor(fn, stage), testWorld(), yield()
and a table `state` that is kept between scripts. Prints the QA log lines it produced.
"""
import argparse, os, time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mod-dir', type=Path, required=True)
parser.add_argument('--pid', type=int, required=True)
parser.add_argument('--timeout', type=float, default=120)
parser.add_argument('script', type=Path)
args = parser.parse_args()
directory = args.mod_dir.resolve(strict=True)
if directory.name != 'PC2CoopProbe' or args.pid <= 0:
    parser.error('Expected the PC2CoopProbe test directory and a positive PID')
log = directory / f'pc2coop-diagnostic-{args.pid}.log'
if not log.is_file():
    parser.error('No diagnostic log for this process in this directory')
code = args.script.read_text(encoding='utf8')
if len(code) > 4000:
    parser.error('Script longer than 4000 characters')
ident = str(time.time_ns())
offset = log.stat().st_size
target = directory / f'pc2coop-inbox-{args.pid}.txt'
temporary = target.with_suffix('.tmp')
temporary.write_bytes(f'{ident}|lua\n{code}'.encode('utf8'))
os.replace(temporary, target)
deadline = time.monotonic() + args.timeout
seen = 0
while time.monotonic() < deadline:
    time.sleep(0.5)
    text = log.read_bytes()[offset:].decode('utf8', errors='replace')
    lines = [l for l in text.splitlines() if 'qa:' in l or 'error' in l.lower()]
    for line in lines[seen:]:
        print(line[:600])
    seen = len(lines)
    if f'qa:lua:done:{ident}' in text or 'qa:lua:error' in text or 'qa:task-error' in text:
        break
else:
    print('Timed out')
