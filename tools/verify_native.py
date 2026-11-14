"""Execute zero-argument diagnostic exports in a disposable child process."""
import argparse
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

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
header, actual = path.read_bytes().split(b'\n',1)
assert b'no-lua-abi=1' in header
assert actual == all_bytes+b'\n\n'+'Grüße'.encode()+b'\n'+b'x'*4096+b'\n'+b'[diagnostic record rejected]\n'*2
print('Native DLL checks passed: all 256 bytes, UTF-8, NUL, empty, 4096-byte bound, overflow, partial byte; zero results.')
