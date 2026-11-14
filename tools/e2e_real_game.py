"""End-to-end: one real PC2 test copy plus two simulated players on a real TCP host.

Runs the full chain: sync.lua <-> GameLink <-> Client <-> HostServer <-> Client <-> FakeGame.
The real game is started, a fresh test park is created by QA command, then:
  1. both simulated players build; the real game must apply both objects,
  2. the real game builds (QA bot); both simulated players must receive it,
  3. a simulated player moves, another deletes the real game's object; PC2 must follow,
  4. two players edit the same object at once; the stale edit must be rolled back,
  5. the real game's camera presence must reach the host.
"""
import argparse
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from pc2coop.coop import Authority, Client, GameLink, HostServer  # noqa: E402
from test_coop import FakeGame  # noqa: E402

DISMISS = Path(__file__).with_name('dismiss_driver_dialog.ps1')


def wait(predicate, what, timeout=120):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            print('OK  ', what, flush=True)
            return
        time.sleep(0.25)
    raise SystemExit('FAIL ' + what)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir', type=Path, required=True)
    args = parser.parse_args()
    mod = args.game_dir / 'Win64' / 'ovldata' / 'PC2CoopProbe'
    game = subprocess.Popen([str(args.game_dir / 'PlanetCoaster2.exe')], cwd=str(args.game_dir))
    log = mod / f'pc2coop-diagnostic-{game.pid}.log'
    text = lambda: log.read_bytes().decode('utf-8', 'replace') if log.is_file() else ''

    def qa(command, done):
        offset = len(text())
        inbox = mod / f'pc2coop-inbox-{game.pid}.txt'
        inbox.with_suffix('.tmp').write_bytes(f'{time.time_ns()}|{command}'.encode('ascii'))
        inbox.with_suffix('.tmp').replace(inbox)
        wait(lambda: done in text()[offset:], f'game: {command}')

    def booted():
        if not log.is_file():
            subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(DISMISS),
                            '-ProcessId', str(game.pid)], capture_output=True, timeout=30)
        return 'qa:frontend-ready' in text()

    print('PID', game.pid, flush=True)
    host = None
    try:
        wait(booted, 'PC2 main menu', 300)
        time.sleep(3)
        qa('new-test-park', '[PC2CoopSync] sync:ready')
        host = HostServer(Authority(), port=0, bind='127.0.0.1')
        real_link = GameLink(args.game_dir, lambda e: real.game_event(e))
        real = Client('127.0.0.1', host.port, host.key, 'Echt', real_link)
        wait(lambda: real_link.pid == game.pid, 'GameLink attached')
        real_link.send_control('S|Echt')
        wait(lambda: 'sync:started|Echt' in text(), 'sync started in game')
        fakes = []
        for name in ('Alex', 'Sam'):
            fake = FakeGame()
            fake.client = Client('127.0.0.1', host.port, host.key, name, fake)
            fakes.append(fake)
        alex, sam = fakes
        a = host.authority

        alex.build(30)
        sam.build(40)
        wait(lambda: 'sync:applied|2' in text() and len(a.objects) == 2, 'real game applied 2 remote objects')
        wait(lambda: not real_link.ops, 'inbox drained')

        qa('create-test-rock', 'qa:verify:position-passed')
        wait(lambda: any(s['res'] == 'AQ_Rock_04' and s['last'] == 'Echt' for s in a.objects.values()),
             'host received the real build')
        rock = next(g for g, s in a.objects.items() if s['last'] == 'Echt')
        wait(lambda: all(rock in dict(f.view()) for f in fakes), 'simulated players got the real build')
        wait(lambda: 'sync:applied|3' in text(), 'real game acknowledged its own build (M)')

        sam.move(rock, 25)
        wait(lambda: 'sync:applied|4' in text(), 'real game applied a remote move of its own rock')
        wait(lambda: a.objects[rock]['p'][0] == 25, 'host state moved')

        before = a.conflicts
        alex.move(rock, 70)      # stale: Alex never saw Sam's revision yet? (it did) -> accepted
        sam_rev = sam.rev[rock]
        sam.client.game_event({'t': 'up', 'part': sam.g2l[rock], 'gid': rock, 'rev': sam_rev - 1, 'res': 'AQ_Rock_04',
                               'p': [80, 0, 0], 'q': [0, 0, 0, 1], 's': 1})
        wait(lambda: a.conflicts == before + 1, 'stale concurrent edit rejected')
        wait(lambda: all(dict(f.view()).get(rock) == 70.0 for f in fakes), 'everyone converged on the winning edit')
        wait(lambda: text().count('sync:applied|') >= 5, 'real game applied the winning edit')

        alex.remove(rock)
        wait(lambda: rock not in a.objects, 'host deleted the real rock')
        wait(lambda: text().count('sync:applied|') >= 6, 'real game applied the remote delete')

        wait(lambda: any(p['name'] == 'Echt' and p['pres'] for p in a.players.values()), 'real presence at host')
        errors = [l for l in text().splitlines() if 'apply-error' in l or 'tick-error' in l]
        if errors:
            raise SystemExit('FAIL game reported errors:\n' + '\n'.join(errors))
        print('PASSED: 3 players (1 real PC2, 2 simulated), create/move/delete both ways, conflict resolved', flush=True)
    finally:
        print('LOG', log, flush=True)
        if host:
            host.close()
        subprocess.run(['taskkill', '/PID', str(game.pid), '/F'], capture_output=True)


if __name__ == '__main__':
    main()
