"""session.lua: three Lua runtimes (host + 2 clients) over a simulated Steam lobby."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1]/'probe/PC2CoopProbe/Main/pc2coop/session.lua'

FAKES = r'''
net = {commands = {}, events = {}}
function net.HasNet() return true end
function net.NetCommand(text) net.commands[#net.commands+1] = text end
function net.NetPoll() return table.remove(net.events, 1) end
sync = {ops = {}, controls = {}}
function sync.Receive(text)
    for line in string.gmatch(text, "[^\n]+") do
        if string.match(line, "^%a|%d+|") then sync.ops[#sync.ops+1] = line else sync.controls[#sync.controls+1] = line end
    end
end
function sync.BaselineCount() return 976 end
function sync.LocalPart(gid) return nil end
logs = {}
loads = {}
manager = {}
function manager:SaveParkToFile(path) return true end
function manager:SaveTerrainToFile(path) return true end
function manager:RequestLoadParkFromFile(path, world, creator, name) loads[#loads+1] = path .. "@" .. world; return true end
local nextData = {SetGameMode = function() end, SetParkName = function() end}
api = {world = {GetActive = function() return "temperateworld" end,
    GetWorldAPIs = function() return {park = {GetParkName = function() return "Testpark" end}} end},
    game = {GetEnvironment = function() return {RequireInterface = function() return nextData end} end}}
'''


class Peer:
    def __init__(self, sid, name):
        self.sid, self.name = sid, name
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        loader = self.lua.eval('function(s) return assert(load(s, "session", "t", _G))() end')
        self.session = loader(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().session = self.session
        self.lua.execute('session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')
        self.memory = {}
        self.loaded = 0
        self.event(f'net:ready|{sid}|{name}')

    def event(self, text):
        self.lua.eval('function(t) net.events[#net.events+1] = t end')(text)

    def tick(self):
        self.lua.execute('session.Tick()')

    def commands(self):
        out = list(self.lua.eval('net.commands').values())
        self.lua.execute('net.commands = {}')
        return out

    def ops(self):
        return list(self.lua.eval('sync.ops').values())

    def local_change(self, line):
        self.lua.eval('function(l) session.OnSyncLine(l) end')(line)


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class SessionTests(unittest.TestCase):
    def setUp(self):
        self.peers = {sid: Peer(sid, name) for sid, name in (('100', 'Host'), ('200', 'Alex'), ('300', 'Sam'))}
        host = self.peers['100']
        host.tick()
        host.local_change  # noqa
        self.lobby_enter('100')
        for sid in ('200', '300'):
            self.lobby_enter(sid)
        self.pump()

    def lobby_enter(self, sid):
        self.peers[sid].event('lobby:entered|L1|100|Host')
        if sid != '100':
            self.peers['100'].event(f'member:join|{sid}|{self.peers[sid].name}')
        self.pump()

    def pump(self, rounds=8):
        """Simulated DLL: routes messages and files, keeps kv memory, replays a park load."""
        for _ in range(rounds):
            for peer in self.peers.values():
                peer.tick()
            for sid, peer in self.peers.items():
                for command in peer.commands():
                    verb, _, rest = command.partition('|')
                    if verb == 'send':
                        target, _, payload = rest.partition('|')
                        self.peers[target].event(f'msg|{sid}|{payload}')
                    elif verb == 'file':
                        target, local, remote = rest.split('|')
                        self.peers[target].event(f'file:done|{sid}|{remote}|100')
                    elif verb == 'kv':
                        key, _, value = rest.partition('|')
                        peer.memory[key] = value
                    elif verb == 'status':
                        for key, value in peer.memory.items():
                            peer.event(f'kv|{key}|{value}')
                        peer.event('lobby:entered|L1|100|Host')
                loads = len(peer.lua.eval('loads'))
                if loads > peer.loaded:
                    # The game loaded the host park: module restarts and asks the DLL.
                    peer.loaded = loads
                    peer.lua.execute('session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')

    def test_roster_lists_all_three_players_everywhere(self):
        self.pump(60)
        for peer in self.peers.values():
            view = peer.session.View()
            names = sorted(p['name'] for p in view['players'].values())
            self.assertEqual(names, ['Alex', 'Host', 'Sam'], peer.name)

    def test_client_build_reaches_host_and_other_client(self):
        self.peers['200'].local_change('sync:up|101||0|AQ_Rock_04|1|2|3|0|0|0|1|1')
        self.pump()
        alex_ops = self.peers['200'].ops()
        self.assertTrue(any(op.startswith('M|') and '|101|1' in op for op in alex_ops), alex_ops)
        for sid in ('100', '300'):
            self.assertTrue(any(op.startswith('U|') and 'AQ_Rock_04|1|2|3' in op for op in self.peers[sid].ops()), sid)

    def test_conflicting_edits_one_is_rolled_back(self):
        self.peers['200'].local_change('sync:up|101||0|AQ_Rock_04|1|2|3|0|0|0|1|1')
        self.pump()
        gid = next(op.split('|')[2] for op in self.peers['200'].ops() if op.startswith('M|'))
        self.peers['200'].local_change(f'sync:up|101|{gid}|1|AQ_Rock_04|5|2|3|0|0|0|1|1')
        self.peers['300'].local_change(f'sync:up|7|{gid}|1|AQ_Rock_04|9|2|3|0|0|0|1|1')
        self.pump()
        sam = self.peers['300'].ops()
        self.assertTrue(any(op.startswith('R|') for op in sam), sam)
        self.assertTrue(any(op.startswith('U|') and f'|{gid}|' in op and '|5|2|3|' in op for op in sam[-2:]), sam)

    def test_host_build_and_delete_reach_clients(self):
        self.peers['100'].local_change('sync:up|55||0|NAT_Fern|4|0|4|0|0|0|1|2')
        self.pump()
        gid = next(op.split('|')[2] for op in self.peers['100'].ops() if op.startswith('M|'))
        self.peers['100'].local_change(f'sync:del|55|{gid}|1')
        self.pump()
        for sid in ('200', '300'):
            ops = self.peers[sid].ops()
            self.assertTrue(any(op.startswith('U|') for op in ops) and ops[-1].startswith('D|'), ops)

    def test_late_joiner_gets_snapshot_and_sequences_increase(self):
        self.peers['200'].local_change('sync:up|101||0|AQ_Rock_04|1|2|3|0|0|0|1|1')
        self.pump()
        self.peers['400'] = Peer('400', 'Kim')
        self.lobby_enter('400')
        self.pump()
        kim = self.peers['400'].ops()
        self.assertEqual(len([op for op in kim if op.startswith('U|')]), 1)
        seqs = [int(op.split('|')[1]) for op in self.peers['100'].ops()]
        self.assertEqual(seqs, sorted(seqs))

    def test_presence_reaches_roster(self):
        self.peers['300'].local_change('sync:pres|10|20|30|0.5|-0.2|4|StandardOrbit|baut')
        self.pump(60)
        sam = next(p for p in self.peers['200'].session.View()['players'].values() if p['name'] == 'Sam')
        self.assertEqual((sam['act'], sam['x']), ('baut', 10))

    def test_host_leaving_ends_client_session(self):
        self.peers['200'].event('member:leave|100')
        self.pump()
        self.assertIsNone(self.peers['200'].session.View()['role'])


if __name__ == '__main__':
    unittest.main()


class TransferTests(SessionTests):
    def test_joiner_loaded_host_park_once(self):
        for sid in ('200', '300'):
            self.assertEqual(list(self.peers[sid].lua.eval('loads').values()), ['/run/pc2coop-join.bin@temperateworld'])
            self.assertEqual(self.peers[sid].memory['phase'], 'live')
        self.assertEqual(len(self.peers['100'].lua.eval('loads')), 0)

    def test_change_during_join_is_delivered_after_load(self):
        self.peers['500'] = Peer('500', 'Spaet')
        self.peers['500'].event('lobby:entered|L1|100|Host')
        self.peers['100'].event('member:join|500|Spaet')
        self.peers['500'].tick(); self.peers['100'].tick()
        for sid, peer in list(self.peers.items()):
            for command in peer.commands():
                verb, _, rest = command.partition('|')
                if verb == 'send':
                    target, _, payload = rest.partition('|')
                    self.peers[target].event(f'msg|{sid}|{payload}')
        self.peers['200'].local_change('sync:up|101||0|AQ_Rock_04|1|2|3|0|0|0|1|1')
        self.pump(12)
        late = self.peers['500'].ops()
        self.assertTrue(any(op.startswith('U|') and 'AQ_Rock_04' in op for op in late), late)


class MenuJoinTests(SessionTests):
    def join_state(self, peer):
        state = peer.lua.eval('session.JoinState()')
        return dict(state.items()) if state is not None else None

    def test_invite_accepted_from_menu_reports_phases_until_live(self):
        guest = self.peers['600'] = Peer('600', 'Gast')
        guest.event('invite:accepted|L1|100|Host')
        guest.tick()
        self.assertIn('join|L1', guest.commands())
        self.assertEqual(self.join_state(guest)['phase'], 'joining')
        guest.event('lobby:entered|L1|100|Host')
        self.peers['100'].event('member:join|600|Gast')
        guest.tick()
        state = self.join_state(guest)
        self.assertEqual((state['phase'], state['host']), ('awaiting', 'Host'))
        guest.event('file:progress|pc2coop-join.bin|50|200')
        guest.tick()
        self.assertAlmostEqual(self.join_state(guest)['progress'], 0.25)
        self.pump(12)
        self.assertEqual(self.join_state(guest)['phase'], 'live')
        self.assertEqual(list(guest.lua.eval('loads').values()), ['/run/pc2coop-join.bin@temperateworld'])

    def test_host_has_no_join_state(self):
        self.assertIsNone(self.join_state(self.peers['100']))


class ResyncTests(SessionTests):
    def test_desync_is_reported_and_resync_reloads_host_park(self):
        alex = self.peers['200']
        alex.local_change('sync:desync|7|invalid-placement')
        self.assertEqual(alex.lua.eval('session.Desync()'), 'invalid-placement')
        self.pump(4)
        feed = list(self.peers['100'].lua.eval('session.View().feed').values())
        self.assertIn('Alex ist nicht mehr synchron', feed)
        alex.lua.execute('session.Resync()')
        self.assertIsNone(alex.lua.eval('session.Desync()'))
        self.pump(12)
        self.assertEqual(len(alex.lua.eval('loads')), 2)
        self.assertEqual(alex.memory['phase'], 'live')


class VersionTests(SessionTests):
    def test_session_version_matches_mod_version(self):
        database = (SOURCE.parents[1] / 'database/pc2coopprobeluadatabase.lua').read_text(encoding='utf8')
        self.assertIn(f'local probeVersion = "{self.peers["100"].lua.eval("session.VERSION")}"', database)

    def test_other_mod_version_is_rejected_with_a_hint(self):
        old = self.peers['700'] = Peer('700', 'Alt')
        old.lua.execute('session.VERSION = "0.9.0"')
        old.event('lobby:entered|L1|100|Host')
        self.peers['100'].event('member:join|700|Alt')
        self.pump(6)
        host_feed = list(self.peers['100'].lua.eval('session.View().feed').values())
        self.assertTrue(any('Alt hat PC2Coop 0.9.0' in line for line in host_feed), host_feed)
        names = [p['name'] for p in self.peers['100'].lua.eval('session.View().players').values()]
        self.assertNotIn('Alt', names)
        toasts = [t['text'] for t in old.lua.eval('session.Toasts()').values()]
        self.assertTrue(any('UPDATE.cmd' in t for t in toasts), toasts)
        self.assertIsNone(old.lua.eval('session.View().role'))
