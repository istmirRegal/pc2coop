"""Drive the prepared PC2 test copy: launch it, run fixed QA commands, collect the log.

Example:
    python tools/game_bot.py --game-dir <test copy> new-test-park:park-manager-init introspect:introspect:done
Each step is COMMAND:EXPECTED, where EXPECTED is a log substring that marks completion.
"""
import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

ERRORS = ('qa:task-error:', 'tick-error:', 'qa:rejected:', 'hook-error:')


DISMISS = Path(__file__).with_name('dismiss_driver_dialog.ps1')


def wait_for(log, offset, needle, timeout, process):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not log.is_file() and isinstance(process, subprocess.Popen):
            subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(DISMISS),
                            '-ProcessId', str(process.pid)], capture_output=True, timeout=30)
        if process.poll() is not None:
            raise SystemExit(f'PC2 exited with code {process.returncode:#x} while waiting for {needle!r}')
        if log.is_file():
            tail = log.read_bytes()[offset:].decode('utf8', errors='replace')
            if any(e in tail for e in ERRORS):
                print(tail)
                raise SystemExit('Runtime error reported in log')
            if needle in tail:
                return len(log.read_bytes())
        time.sleep(0.5)
    raise SystemExit(f'Timed out waiting for {needle!r}')


def send(mod_dir, pid, command):
    target = mod_dir / f'pc2coop-inbox-{pid}.txt'
    temporary = target.with_suffix('.tmp')
    temporary.write_bytes(f'{time.time_ns()}|{command}'.encode('ascii'))
    temporary.replace(target)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=240)
    parser.add_argument('--attach', type=int, help='PID of a running test copy to drive')
    parser.add_argument('--stop', action='store_true',
                        help='Force-stop PC2 afterwards; the next start answers the driver dialog itself')
    parser.add_argument('steps', nargs='+')
    args = parser.parse_args(argv)
    exe = args.game_dir / 'PlanetCoaster2.exe'
    mod_dir = args.game_dir / 'Win64' / 'ovldata' / 'PC2CoopProbe'
    if not exe.is_file() or not mod_dir.is_dir():
        parser.error('Expected the prepared test copy with PC2CoopProbe installed')
    steps = []
    for step in args.steps:
        # "COMMAND => EXPECTED" when the command itself contains ':' (vectors in replay batches).
        command, _, expected = step.partition(' => ') if ' => ' in step else step.partition(':')
        # "@A|1|... && B|2|..." sends sync lines (';' belongs to replay batches).
        if command.startswith('@'):
            command = 'sync\n' + '\n'.join(part.strip() for part in command[1:].split('&&'))
        elif not re.fullmatch(r'[a-z-]+', command):
            parser.error(f'Bad step {step!r}')
        if not expected:
            parser.error(f'Bad step {step!r}')
        steps.append((command, expected))
    # Killing PC2 makes its next start stop at a "graphics driver crash" dialog, so the
    # bot never terminates the game; it leaves it running or attaches to a running one.
    if args.attach:
        process = Attached(args.attach)
        offset = len((mod_dir / f'pc2coop-diagnostic-{process.pid}.log').read_bytes())
    else:
        process = subprocess.Popen([str(exe)], cwd=str(args.game_dir))
        offset = None
    log = mod_dir / f'pc2coop-diagnostic-{process.pid}.log'
    print('PID', process.pid, flush=True)
    try:
        if offset is None:
            offset = wait_for(log, 0, 'qa:frontend-ready', args.timeout, process)
        for command, expected in steps:
            time.sleep(3)
            send(mod_dir, process.pid, command)
            print('sent', command.replace(chr(10), ' / '), flush=True)
            offset = wait_for(log, offset, expected, args.timeout, process)
            print('done', expected, flush=True)
    finally:
        print('LOG', log, flush=True)
        if args.stop and process.poll() is None:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/F'], capture_output=True)
    return 0


class Attached:
    """Minimal Popen stand-in for an already running PC2 process."""
    def __init__(self, pid):
        import ctypes
        self.pid, self.returncode = pid, None
        self._kernel = ctypes.windll.kernel32
        self._handle = self._kernel.OpenProcess(0x1000, False, pid)
        if not self._handle:
            raise SystemExit(f'Cannot open process {pid}')

    def poll(self):
        import ctypes
        code = ctypes.c_ulong()
        self._kernel.GetExitCodeProcess(self._handle, ctypes.byref(code))
        if code.value == 259:
            return None
        self.returncode = code.value
        return code.value


if __name__ == '__main__':
    sys.exit(main())
