"""Execute zero-argument diagnostic exports in a disposable child process."""
import argparse
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('dll', type=Path)
parser.add_argument('--child', action='store_true')
args = parser.parse_args()
if not args.child:
    with tempfile.TemporaryDirectory(prefix='pc2coop-native-') as temp:
        target = Path(temp) / args.dll.name
        shutil.copy2(args.dll, target)
        subprocess.run([sys.executable, __file__, str(target), '--child'], check=True)
    raise SystemExit()

# Developer marker first: the DLL reads it once (the report may then choose its folder).
(args.dll.parent / 'pc2coop-dev.flag').write_text('test', encoding='ascii')
dll = ctypes.CDLL(str(args.dll.resolve()))
def callback(name):
    fn = getattr(dll, name)
    fn.argtypes = [ctypes.c_void_p]
    fn.restype = ctypes.c_int
    return fn
bootstrap = callback('pc2_bootstrap')
for name in ('pc2_probe_greeting', 'pc2_probe_empty', 'pc2_probe_binary'):
    # This is Python, so the EXE identity guard must reject before reading state.
    assert callback(name)(None) == 0
    assert callback(name)(1) == 0
begin = callback('pc2_log_begin')
end = callback('pc2_log_end')
nibbles = [callback('pc2_nibble_' + format(i,'x')) for i in range(16)]
assert bootstrap(None) == 0
path = args.dll.parent / ('pc2coop-diagnostic-%d.log' % os.getpid())
def send(data):
    assert begin(None) == 0
    for byte in data:
        assert nibbles[byte >> 4](None) == 0
        assert nibbles[byte & 15](None) == 0
    assert end(None) == 0

all_bytes = bytes(range(256))
send(all_bytes)
send(b'')
send('Grüße'.encode())
send(b'x' * 4096)
send(b'y' * 4097)
begin(None); nibbles[1](None); end(None)
header, system, pinned, actual = path.read_bytes().split(b'\n',3)
assert b'no-lua-abi=1' in header
assert system.startswith(b'system|windows=') and b'|ram-gb=' in system and b'|mods=' in system, system
assert pinned == b'dll:pinned', pinned
# Lua frees the DLL when the game closes its Lua states; pinned, it must stay loaded.
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
kernel32.GetModuleHandleW.restype = ctypes.c_void_p
kernel32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
kernel32.FreeLibrary.argtypes = [ctypes.c_void_p]
for _ in range(3):
    kernel32.FreeLibrary(dll._handle)
assert kernel32.GetModuleHandleW(str(args.dll.resolve())), 'DLL was unloaded although pinned'
assert actual == all_bytes+b'\n\n'+'Grüße'.encode()+b'\n'+b'x'*4096+b'\n'+b'[diagnostic record rejected]\n'*2

# Problem report (FEAT-223): the newest logs in one file; ids, names and the user folder replaced.
older = args.dll.parent / 'pc2coop-diagnostic-1.log'
older.write_text('[S] 76561190000000001 joined|Vici says hi|C:\\Users\\Someone\\park\n'
                 '[S] error|session.tick|x1|boom\n[S] lobby 109775240000000002\n', encoding='utf8')
os.utime(older, (time.time() - 60, time.time() - 60))
reports = args.dll.parent / 'reports'
reports.mkdir()
net_end = callback('pc2_net_end')
assert begin(None) == 0
for byte in b'report|de|' + str(reports).encode() + b'|2.1.0|76561190000000002=Hostname|76561190000000001=Vici':
    nibbles[byte >> 4](None)
    nibbles[byte & 15](None)
assert net_end(None) == 0
written = list(reports.glob('PC2Coop-Bericht-*.txt'))
assert len(written) == 1, written
report = written[0].read_bytes().decode('utf-8-sig', errors='replace')   # this run's log holds all 256 bytes
for secret in ('76561190000000001', '109775240000000002', 'Vici', 'Someone'):
    assert secret not in report, secret
assert 'P1 joined|P1 says hi|C:\\Users\\<user>\\park' in report, report[:3000]
assert 'L1' in report and 'PC2Coop 2.1.0' in report
assert 'error|session.tick|x1|boom' in report.split('Auffällige Zeilen:')[1].split('========')[0]
assert report.index('pc2coop-diagnostic-%d.log' % os.getpid()) < report.index('pc2coop-diagnostic-1.log')
print('Native DLL checks passed: all 256 bytes, UTF-8, NUL, empty, 4096-byte bound, overflow, partial byte; zero results;'
      ' system line; problem report anonymised.')
