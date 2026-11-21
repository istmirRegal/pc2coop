"""Fuzzing the session over a bad network (method of coop-anything's tools/fuzz and tools/chaos).

Three Lua runtimes (host + two players, see test_session_lua.Peer) play seeded random sessions:
chat, board entries and changes, votes, rules, marks, emotes, test ride invitations, resyncs.
The link between them is impaired like coop-anything's chaos profiles allow for Steam's
reliable messages: delay and jitter (the order per pair stays, as Steam keeps it), and outages
in which a player's messages are lost and the DLL reports the peer as stalled. After the last
action the link heals, everything settles, and the oracles must hold:

  * no Lua error anywhere (a crash of the session is a crash of the game's session),
  * converge: every player shows the host's board, rules and roster,
  * nothing twice: no board id or chat line twice, chat in the host's order,
  * quiet means quiet: after settling no messages are still being sent.

A failing seed prints its number; the same seed replays the same session exactly.
"""
from collections import deque
import random
import unittest

try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is not None:
    from test_session_lua import Peer

# Ticks of delay per message (one tick = every peer runs session.Tick once).
PROFILES = {
    'lan': {'delay': 0, 'jitter': 1, 'outage': 0.0},
    'bad_wifi': {'delay': 2, 'jitter': 6, 'outage': 0.004},
    'hell': {'delay': 6, 'jitter': 20, 'outage': 0.012},
}
EMOTES = ('wave', 'cheer', 'laugh', 'sick', 'up', 'down')
RULES = {'speed': ('all', 'host'), 'visitors': ('1', '0'), 'foreign': ('free', 'ask')}


class ChaosSession:
    """The simulated DLL of test_session_lua.SessionTests.pump, with an impaired link."""

    def __init__(self, seed, profile):
        self.rng = random.Random(seed)
        self.profile = PROFILES[profile]
        self.peers = {sid: Peer(sid, name) for sid, name in (('100', 'Host'), ('200', 'Alex'), ('300', 'Sam'))}
        self.now = 0
        self.wire = deque()               # (due, target, event)
        self.last_due = {}                # (from, to) -> due of the last message: order per pair
        self.down = {}                    # sid -> tick until which its link is cut
        self.healed = False
        self.counts = {'sent': 0, 'lost': 0, 'outages': 0}
        self.peers['100'].tick()
        for sid in ('100', '200', '300'):
            self.peers[sid].event('lobby:entered|L1|100|Host')
            if sid != '100':
                self.peers['100'].event(f'member:join|{sid}|{self.peers[sid].name}')
            self.settle()

    def cut(self, a, b):
        return not self.healed and (self.down.get(a, -1) > self.now or self.down.get(b, -1) > self.now)

    def post(self, source, target, event):
        if self.cut(source, target):
            self.counts['lost'] += 1
            return
        p = self.profile
        due = self.now + p['delay'] + (self.rng.randint(0, p['jitter']) if not self.healed else 0)
        due = max(due, self.last_due.get((source, target), 0))
        self.last_due[(source, target)] = due
        self.wire.append((due, target, event))
        self.counts['sent'] += 1

    def step(self):
        """One tick: deliver what is due, tick everyone, route what they sent."""
        self.now += 1
        if not self.healed and self.rng.random() < self.profile['outage']:
            sid = self.rng.choice(('200', '300'))
            if self.down.get(sid, -1) <= self.now:
                self.down[sid] = self.now + self.rng.randint(5, 40)
                self.counts['outages'] += 1
                # As the DLL does once Steam took nothing for a minute: the data is gone.
                self.peers['100'].event(f'net:peer-stalled|{sid}|25|3')
                self.peers[sid].event('net:peer-stalled|100|25|3')
        due_now = [m for m in self.wire if m[0] <= self.now]
        self.wire = deque(m for m in self.wire if m[0] > self.now)
        for _, target, event in due_now:
            self.peers[target].event(event)
        for peer in self.peers.values():
            peer.tick()
        for sid, peer in self.peers.items():
            for command in peer.commands():
                self.route(sid, peer, command)
            if len(peer.lua.eval('loads')) > 0:
                self.restart(sid, peer)

    def restart(self, sid, old):
        """The game loaded a park: as in the game, every Lua module starts anew (new runtime);
        only the DLL's memory, its lobby and its queued events stay."""
        fresh = Peer(sid, old.name)
        fresh.memory, fresh.in_lobby = dict(old.memory), old.in_lobby
        fresh.lua.execute('net.commands = {}')
        for event in list(old.lua.eval('net.events').values()):     # the DLL keeps what it queued
            fresh.event(event)
        fresh.lua.execute('session.SetContext("park"); session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')
        fresh.lua.execute('session.SetAskBeforeJoin(false)')
        fresh.earlier_logs = getattr(old, 'earlier_logs', []) + list(old.lua.eval('logs').values())
        self.peers[sid] = fresh

    def route(self, sid, peer, command):
        verb, _, rest = command.partition('|')
        if verb == 'send':
            target, _, payload = rest.partition('|')
            if target in self.peers:
                self.post(sid, target, f'msg|{sid}|{payload}')
        elif verb == 'all':
            for other in self.peers:
                if other != sid:
                    self.post(sid, other, f'msg|{sid}|{rest}')
        elif verb == 'file':
            target, local, remote = rest.split('|')
            self.post(sid, target, f'file:done|{sid}|{remote}|100')
            peer.event(f'file:sent|{target}|{remote}|100')
        elif verb == 'kv':
            key, _, value = rest.partition('|')
            peer.memory[key] = value
        elif verb == 'status':
            for key, value in peer.memory.items():
                peer.event(f'kv|{key}|{value}')
            if peer.in_lobby:
                peer.event('lobby:entered|L1|100|Host')
        elif verb in ('leave', 'host', 'join'):
            peer.in_lobby = verb != 'leave'

    # The host's roster goes out every half second whatever happens: it is not "still busy".
    PERIODIC = ('|roster|',)

    def busy(self):
        if any(not any(p in event for p in self.PERIODIC) for _, _, event in self.wire):
            return True
        # A player still waiting for or loading the park is not settled, even when nothing
        # is on the wire (it asks again after PARK_RETRY_FRAMES).
        for sid in ('200', '300'):
            state = self.peers[sid].lua.eval('session.JoinState()')
            if state and state['phase'] not in ('live', 'failed'):
                return True
        return False

    def settle(self, limit=6000, quiet=90):
        calm = 0
        for _ in range(limit):
            self.step()
            calm = 0 if self.busy() else calm + 1
            if calm >= quiet:
                return True
        return False

    # Random player actions ----------------------------------------------------------------
    def board_ids(self):
        return [i['id'] for i in self.peers['100'].lua.eval('session.View().board').values()]

    def act(self, n):
        rng = self.rng
        sid = rng.choice(('100', '200', '300'))
        lua = self.peers[sid].lua
        roll = rng.random()
        ids = self.board_ids()
        if roll < 0.20:
            lua.eval('function(t) session.SendChat(t) end')(f'{sid}-{n}')
        elif roll < 0.35:
            kind = rng.choice(('comment', 'task', 'proposal', 'meet', 'area'))
            lua.eval('function(k, t) session.BoardAdd(k, 10, 2, 10, 15, t, "", "") end')(kind, f'b{n}')
        elif roll < 0.47 and ids:
            field, value = rng.choice((('done', '1'), ('done', '0'), ('text', f'x{n}'), ('title', f't{n}'), ('vote', '1'), ('vote', '0')))
            lua.eval('function(i, f, v) session.BoardSet(i, f, v) end')(rng.choice(ids), field, value)
        elif roll < 0.52 and ids:
            lua.eval('function(i) session.BoardRemove(i) end')(rng.choice(ids))
        elif roll < 0.60:
            name = rng.choice(list(RULES))
            self.peers['100'].lua.eval('function(n, v) session.SetRule(n, v) end')(name, rng.choice(RULES[name]))
        elif roll < 0.70:
            lua.eval('function(k) session.Emote(k) end')(rng.choice(EMOTES))
        elif roll < 0.78:
            lua.eval('function(n) session.InviteRide("F1_2_3", n) end')(f'Bahn{n}')
        elif roll < 0.86 and sid != '100':
            x, z = rng.uniform(-50, 50), rng.uniform(-50, 50)
            lua.execute(f'net.NetCommand("send|100|ping|{x:.2f}|0|{z:.2f}|")')
        elif roll < 0.90 and sid != '100':
            lua.execute('session.Resync()')
        elif roll < 0.95:
            stars = rng.randint(1, 5)
            lua.eval('function(s, t) session.Rate("F1_2_3", s, "Bahn", t) end')(stars, f'r{n}')
        else:
            lua.eval('function(m) net.NetCommand(m) end')(f'send|100|time|{rng.choice("01")}|{rng.randint(1, 3)}')

    # Oracles --------------------------------------------------------------------------------
    def board(self, sid):
        out = []
        for item in self.peers[sid].lua.eval('session.View().board').values():
            votes = sorted((k, v) for k, v in item['votes'].items()) if item['votes'] else []
            out.append((item['id'], item['kind'], item['title'], item['text'], bool(item['done']), tuple(votes)))
        return sorted(out)

    def check(self, seed):
        host = self.peers['100']
        board = self.board('100')
        ids = [b[0] for b in board]
        problems = []
        if len(ids) != len(set(ids)):
            problems.append('board id twice on the host')
        rules = dict(host.lua.eval('session.View().rules').items())
        roster = sorted(p['sid'] for p in host.lua.eval('session.View().players').values())
        host_chat = [c['text'] for c in host.lua.eval('session.Chat()').values()]
        for sid in ('200', '300'):
            peer = self.peers[sid]
            if self.board(sid) != board:
                problems.append(f'board differs on {sid}')
            if dict(peer.lua.eval('session.View().rules').items()) != rules:
                problems.append(f'rules differ on {sid}')
            if sorted(p['sid'] for p in peer.lua.eval('session.View().players').values()) != roster:
                problems.append(f'roster differs on {sid}')
            chat = [c['text'] for c in peer.lua.eval('session.Chat()').values()]
            if len(chat) != len(set(chat)):
                problems.append(f'chat line twice on {sid}')
            # In the host's order; lost lines (outage) may be missing, nothing else may differ.
            it = iter(host_chat)
            if not all(line in it for line in chat if line in host_chat):
                problems.append(f'chat order differs on {sid}')
        for peer in self.peers.values():
            logs = getattr(peer, 'earlier_logs', []) + list(peer.lua.eval('logs').values())
            errors = [m for m in logs if 'error' in m and 'net:error' not in m]
            if errors:
                problems.append(f'{peer.name}: {errors[0]}')
        return [f'seed {seed}: {p}' for p in problems]


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class SessionFuzzTests(unittest.TestCase):
    def run_seeds(self, profile, seeds, actions):
        found, totals = [], {'sent': 0, 'lost': 0, 'outages': 0}
        for seed in seeds:
            game = ChaosSession(seed, profile)
            for n in range(actions):
                game.act(n)
                for _ in range(game.rng.randint(0, 2)):
                    game.step()
            game.healed = True
            game.down.clear()
            settled = game.settle()
            # A player whose data was lost fetches the park again; give it time and settle once more.
            settled = game.settle() and settled
            if not settled:
                found.append(f'seed {seed}: still sending after the link healed')
            found += game.check(seed)
            for key in totals:
                totals[key] += game.counts[key]
        return found, totals

    def test_good_network_converges(self):
        found, totals = self.run_seeds('lan', range(1, 13), 60)
        self.assertEqual(found, [])
        self.assertGreater(totals['sent'], 1000)

    def test_bad_wifi_converges(self):
        found, totals = self.run_seeds('bad_wifi', range(100, 112), 80)
        self.assertEqual(found, [])

    def test_hell_with_outages_converges(self):
        found, totals = self.run_seeds('hell', range(200, 212), 80)
        self.assertEqual(found, [])
        self.assertGreater(totals['outages'], 0, 'the outage path was never taken')
        self.assertGreater(totals['lost'], 0)


HOST_KINDS = ('hello', 'chat', 'info', 'look', 'up', 'del', 'pres', 'ping', 'who', 'hold', 'time', 'board',
              'comp-rate', 'take-ask', 'ride-invite', 'vote-answer', 'buy', 'emote', 'rate', 'desync',
              'loadfailed', 'ride', 'tool', 'ctx')
CLIENT_KINDS = ('ops', 'roster', 'h', 'deny', 'time', 'note', 'p', 'em', 'sold', 'bd', 'bd-', 'rules', 'cp', 'tk',
                'iv', 'since', 'ruledeny', 'vote', 'pg', 'who', 'park', 'welcome', 'wait', 'reject', 'resync',
                'rt', 'stage', 'tag', 'ride', 'denied')
NASTY = ('', '0', '-1', '1', '3', '1e999', '-1e999', 'nan', 'inf', '-inf', '99999999999999999999', '0x10',
         'A' * 3000, 'Ü€😀', '../../x', '..\\..\\x', 'C:\\Windows', 'pc2coop-dev.flag', 'pc2coop-inbox-1.txt',
         'P5', 'F1_2_3', 'S0_0_0', 'b1', 'b99999', '%s%n%d', '\x00', ';', ',', ':', '\n', 'host', '100', '200',
         'pc2coop-ride-200-1.blueprint', 'pc2coop-join.bin', 'lobby', 'park', 'needpark', 'loaded',
         '[STRING_LITERAL:Value=|x|]', '<script>alert(1)</script>', 'comment', 'proposal', 'area', 'all', 'ask')
SAFE_FILE = r'^pc2coop-[A-Za-z0-9_.-]{1,56}$'


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class HostileMessageTests(unittest.TestCase):
    """A player (or a host) sends anything at all: no Lua error, no file outside the mod's own
    names, the host's state stays within its limits (security review 2026-11-21)."""

    def test_garbage_from_players_and_host_breaks_nothing(self):
        import re
        game = ChaosSession(7, 'lan')
        rng = random.Random(7)
        seen_commands = []
        original = game.route

        def route(sid, peer, command):
            seen_commands.append(command)
            original(sid, peer, command)
        game.route = route

        def payload(kinds):
            fields = [rng.choice(kinds)] + [rng.choice(NASTY) for _ in range(rng.randint(0, 14))]
            return '|'.join(fields)
        for round_ in range(150):
            for _ in range(12):
                game.peers['100'].event('msg|' + rng.choice(('200', '300', '999')) + '|' + payload(HOST_KINDS))
                game.peers[rng.choice(('200', '300'))].event('msg|100|' + payload(CLIENT_KINDS))
                game.peers['100'].event('msg|200|' + rng.choice(NASTY))
            game.step()
        game.healed = True
        game.settle(limit=3000)
        for command in seen_commands:
            verb, _, rest = command.partition('|')
            if verb == 'file':
                _, local, remote = rest.split('|')
                self.assertRegex(local, SAFE_FILE, command)
                self.assertRegex(remote, SAFE_FILE, command)
            elif verb in ('note-write', 'note-append', 'note-read'):
                self.assertRegex(rest.split('|')[0], SAFE_FILE, command[:80])
            elif verb == 'del':
                self.assertRegex(rest, SAFE_FILE, command)
            if verb in ('file', 'del', 'note-write', 'note-append'):
                self.assertNotIn('pc2coop-dev.flag', command)      # the QA switch must never come
                self.assertNotIn('pc2coop-inbox', command)         # from the network
        host = game.peers['100']
        self.assertLessEqual(len(host.lua.eval('session.View().board')), 200)
        for peer in game.peers.values():
            for item in peer.lua.eval('session.Chat()').values():
                self.assertLessEqual(len(item['text']), 200)
                self.assertNotIn('\n', item['text'])
            for p in peer.lua.eval('session.View().players').values():
                self.assertLessEqual(len(p['name']), 32)
                for key in ('x', 'y', 'z'):
                    value = p[key]
                    self.assertTrue(value is None or abs(value) <= 1e6, (key, value))


if __name__ == '__main__':
    unittest.main()
