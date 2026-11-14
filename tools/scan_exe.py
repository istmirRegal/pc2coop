"""Check a PlanetCoaster2.exe for the routine the DLL looks up (same pattern, same rules).

Usage: python tools/scan_exe.py <path to PlanetCoaster2.exe>
Prints every match as an RVA; the DLL accepts exactly one. Reads the file only.
"""
import re
import struct
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / 'native/string_probe.cpp'


def pattern():
    block = re.search(r'routine_pattern\[\] = \{(.*?)\};', SOURCE.read_text(encoding='utf8'), re.S).group(1)
    return [None if t == '-1' else int(t, 16) for t in re.findall(r'-1|0x[0-9a-fA-F]{2}', block)]


def scan(data, wanted):
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    sections, optional = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    table = pe + 24 + optional
    found = []
    for i in range(sections):
        _, vsize, rva, raw_size, raw = struct.unpack_from('<8sIIII', data, table + 40 * i)
        flags = struct.unpack_from('<I', data, table + 40 * i + 36)[0]
        if not flags & 0x20000000:   # IMAGE_SCN_MEM_EXECUTE
            continue
        body = data[raw:raw + min(vsize, raw_size)]
        for offset in range(0, len(body) - len(wanted) + 1, 16):
            if body[offset] == 0x48 and all(w is None or body[offset + j] == w for j, w in enumerate(wanted)):
                found.append(rva + offset)
    return found


if __name__ == '__main__':
    matches = scan(Path(sys.argv[1]).read_bytes(), pattern())
    print('matches:', [hex(m) for m in matches])
    sys.exit(0 if len(matches) == 1 else 1)
