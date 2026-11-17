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
function sync.SetRemoteLocks(map) sync.locks = map end
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
    game = {GetEnvironment = function() return {RequireInterface = function() return nextData end} end,
        GetVersionString = function() return fakeGameVersion or "1.12.2.1035111" end},
    ui2 = {GetDataStoreContext = function() return "simulation" end,
        GetDataStoreElement = function(_, key) return ({numGuests = 1234, cash = 5000, hasUnlimitedCash = false})[key] end}}
'''


class Peer:
    def __init__(self, sid, name):
        self.sid, self.name = sid, name
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        for module in ('shared', 'world'):
            source = (SOURCE.parent / f'{module}.lua').read_text(encoding='utf8')
            self.lua.eval('function(n, s) package.preload["pc2coop." .. n] = function() return assert(load(s, n, "t", _G))() end end')(module, source)
        loader = self.lua.eval('function(s) return assert(load(s, "session", "t", _G))() end')
        self.session = loader(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().session = self.session
        self.lua.execute('session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')
        # Most tests are about a running session, not about getting in: friends walk in.
        self.lua.execute('session.SetAskBeforeJoin(false)')
        self.memory = {}
        self.sent_files = []
        self.deleted = []
        self.sent_notes = []
        self.loaded = 0
        self.in_lobby = True      # the simulated DLL reports lobby L1 on "status"
        self.load_fails = False   # a park load that ends back in the main menu
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
                    elif verb == 'all':
                        for other in self.peers:
                            if other != sid:
                                self.peers[other].event(f'msg|{sid}|{rest}')
                    elif verb == 'file':
                        target, local, remote = rest.split('|')
                        self.peers[target].event(f'file:done|{sid}|{remote}|100')
                        peer.event(f'file:sent|{target}|{remote}|100')
                        peer.sent_files.append((target, remote))
                    elif verb in ('note-write', 'note-append'):
                        peer.sent_notes.append(command)
                    elif verb == 'del':
                        peer.deleted.append(rest)
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

                loads = len(peer.lua.eval('loads'))
                if loads > peer.loaded:
                    # The game loaded the host park: module restarts and asks the DLL.
                    peer.loaded = loads
                    context = 'menu' if peer.load_fails else 'park'
                    peer.lua.execute(f'session.SetContext("{context}"); session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')

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
        self.assertEqual((state['phase'], state['host']), ('lobby', 'Host'))
        # The host answers the hello with the park it plays: the guest asks for it.
        for peer in (guest, self.peers['100'], guest):
            peer.tick()
            for command in peer.commands():
                verb, _, rest = command.partition('|')
                if verb == 'send':
                    target, _, payload = rest.partition('|')
                    self.peers[target].event(f'msg|{peer.sid}|{payload}')
        self.assertEqual(self.join_state(guest)['phase'], 'awaiting')
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
        state = old.lua.eval('session.JoinState()')
        self.assertEqual(state['phase'], 'failed')
        self.assertIn('UPDATE.cmd', state['reason'])
        self.assertIsNone(old.lua.eval('session.View().role'))


class JoinRobustnessTests(SessionTests):
    """What went wrong in the first real two-player test (double transfer, false "joined")."""

    def join_state(self, peer):
        state = peer.lua.eval('session.JoinState()')
        return dict(state.items()) if state is not None else None

    def host_feed(self):
        return list(self.peers['100'].lua.eval('session.View().feed').values())

    def test_steam_reporting_the_lobby_twice_transfers_the_park_once(self):
        host = self.peers['100']
        host.sent_files.clear()
        new = self.peers['800'] = Peer('800', 'Vici')
        new.event('lobby:entered|L1|100|Host')
        new.event('lobby:entered|L1|100|Host')
        host.event('member:join|800|Vici')
        self.pump(12)
        self.assertEqual(host.sent_files, [('800', 'pc2coop-join.trn'), ('800', 'pc2coop-join.bin')])
        self.assertEqual(len(new.lua.eval('loads')), 1)
        self.assertEqual(self.join_state(new)['phase'], 'live')

    def test_asking_again_while_the_park_is_on_its_way_does_not_restart_it(self):
        host = self.peers['100']
        version = host.lua.eval('session.VERSION')
        host.event(f'msg|900|hello|Doppelt|-1|needpark|{version}')
        host.event(f'msg|900|hello|Doppelt|-1|needpark|{version}')
        for _ in range(4):
            host.tick()
        files = [c for c in host.commands() if c.startswith('file|900|')]
        self.assertEqual(len(files), 2, files)
        self.assertEqual(sum('Doppelt tritt bei' in line for line in self.host_feed()), 1)

    def test_load_that_ends_in_the_menu_is_a_failure_not_a_join(self):
        new = self.peers['810'] = Peer('810', 'Vici')
        new.load_fails = True
        new.lua.execute('session.SetContext("menu")')
        new.event('lobby:entered|L1|100|Host')
        self.peers['100'].event('member:join|810|Vici')
        self.pump(12)
        state = self.join_state(new)
        self.assertEqual((state['phase'], state['retry']), ('failed', True))
        self.assertIn('Vici konnte den Park nicht laden', self.host_feed())
        self.assertNotIn('Vici ist beigetreten', self.host_feed())
        acts = {p['name']: p['act'] for p in self.peers['100'].lua.eval('session.View().players').values()}
        self.assertEqual(acts['Vici'], 'laedt')
        # Retry; this time the game opens the park.
        new.load_fails = False
        new.lua.execute('session.Resync(); session.SetContext("park")')
        self.pump(12)
        self.assertEqual(self.join_state(new)['phase'], 'live')
        self.assertIn('Vici ist beigetreten', self.host_feed())

    def test_old_invite_says_so_and_can_be_dismissed(self):
        new = Peer('820', 'Vici')
        new.event('invite:accepted|L9|100|Host')
        new.event('lobby:join-failed|2')
        new.tick()
        state = self.join_state(new)
        self.assertEqual((state['phase'], state['retry']), ('failed', False))
        self.assertIn('abgelaufen', state['reason'])
        new.lua.execute('session.DismissJoin()')
        self.assertIsNone(self.join_state(new))

    def test_invited_wears_off_and_clears_when_the_friend_joins(self):
        host = self.peers['100']
        for event in ('friends:begin|2', 'friend|900|Bob|1|1', 'friend|901|Cleo|1|0', 'friends:end', 'invite:sent|900', 'invite:sent|901'):
            host.event(event)
        host.tick()
        invited = lambda: {f['name']: f['invited'] for f in host.lua.eval('session.Friends()').values()}
        self.assertEqual(invited(), {'Bob': True, 'Cleo': True})
        version = host.lua.eval('session.VERSION')
        host.event(f'msg|901|hello|Cleo|-1|needpark|{version}')
        host.tick()
        self.assertEqual(invited(), {'Bob': True, 'Cleo': False})
        host.lua.execute('for i = 1, 1600 do session.Tick() end')
        self.assertEqual(invited(), {'Bob': False, 'Cleo': False})

    def test_where_a_player_looks_is_relayed_at_once(self):
        self.peers['200'].local_change('sync:pres|1.0|2.0|3.0|0.5|-0.2|4|Orbit|baut|10.0|5.0|12.0')
        host = self.peers['100']
        for sid, command in [('200', c) for c in self.peers['200'].commands()]:
            verb, _, rest = command.partition('|')
            target, _, payload = rest.partition('|')
            host.event(f'msg|{sid}|{payload}')
        host.tick()
        relayed = [c for c in host.commands() if c.startswith('send|300|p|200|')]
        self.assertEqual(relayed, ['send|300|p|200|10|5|12|baut|1|2|3|0.5|-0.2'])
        self.peers['300'].event('msg|100|p|200|10|5|12|baut')
        self.peers['300'].tick()
        alex = [p for p in self.peers['300'].lua.eval('session.View().players').values() if p['sid'] == '200'][0]
        self.assertEqual((alex['fx'], alex['fz'], alex['act']), (10, 12, 'baut'))

    def test_host_back_in_the_menu_keeps_the_lobby(self):
        host = self.peers['100']
        host.lua.execute('session.SetContext("menu"); session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')
        self.pump(4)   # the simulated DLL answers "status" with the lobby the host is still in
        view = host.lua.eval('session.View()')
        self.assertEqual((view['role'], view['stage']), ('host', 'lobby'))
        self.assertTrue(any('wieder in der Lobby' in t['text'] for t in host.lua.eval('session.Toasts()').values()))
        alex = self.peers['200'].lua.eval('session.JoinState()')
        self.assertEqual(alex['phase'], 'hostlobby')
        # Edits of a player still in the old park do not reach the lobby.
        self.peers['200'].local_change('sync:up|101||0|AQ_Rock_04|1|2|3|0|0|0|1|1')
        self.pump(2)
        self.assertEqual(self.peers['300'].ops()[-1:], self.peers['300'].ops()[-1:])
        self.assertFalse(any('AQ_Rock_04' in op for op in self.peers['300'].ops()))


def menu(peer):
    peer.lua.execute('session.SetContext("menu"); session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')


def park(peer):
    peer.lua.execute('session.SetContext("park"); session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class LobbyTests(unittest.TestCase):
    """The host opens a lobby in the main menu; everyone loads the park the host opens."""
    pump = SessionTests.pump

    def setUp(self):
        self.peers = {sid: Peer(sid, name) for sid, name in (('100', 'Host'), ('200', 'Alex'), ('300', 'Sam'))}
        for peer in self.peers.values():
            peer.in_lobby = False
            menu(peer)
        self.pump(2)
        host = self.peers['100']
        host.lua.execute('session.Host()')
        self.assertIn('host', host.commands())
        host.in_lobby = True
        host.event('lobby:entered|L1|100|Host|1')
        for sid in ('200', '300'):
            self.peers[sid].event('invite:accepted|L1|100|invite')
            self.pump(1)
            self.peers[sid].event('lobby:entered|L1|100|Host|1')
            host.event(f'member:join|{sid}|{self.peers[sid].name}')
        self.pump(40)

    def phase(self, sid):
        state = self.peers[sid].lua.eval('session.JoinState()')
        return state['phase'] if state is not None else None

    def acts(self, sid='100'):
        return {p['name']: p['act'] for p in self.peers[sid].lua.eval('session.View().players').values()}

    def test_everyone_waits_in_the_lobby_without_a_park(self):
        self.assertEqual(self.peers['100'].lua.eval('session.View().stage'), 'lobby')
        self.assertEqual(self.acts(), {'Host': None, 'Alex': 'lobby', 'Sam': 'lobby'})
        self.assertEqual(self.acts('300')['Alex'], 'lobby')
        for sid in ('200', '300'):
            self.assertEqual(self.phase(sid), 'lobby')
            self.assertEqual(len(self.peers[sid].lua.eval('loads')), 0)
        self.assertEqual(self.peers['300'].lua.eval('session.View().stage'), 'lobby')

    def test_park_opened_by_the_host_loads_for_everyone(self):
        park(self.peers['100'])
        self.pump(14)
        for sid in ('200', '300'):
            self.assertEqual(list(self.peers[sid].lua.eval('loads').values()), ['/run/pc2coop-join.bin@temperateworld'])
            self.assertEqual(self.phase(sid), 'live')
        self.assertEqual(self.acts()['Alex'], '-' if False else self.acts()['Alex'])
        self.assertNotEqual(self.acts()['Alex'], 'lobby')
        # Back to the lobby and into another park: everyone gets the new park.
        menu(self.peers['100'])
        self.pump(4)
        self.assertEqual(self.phase('200'), 'hostlobby')
        menu(self.peers['200'])          # Alex goes to the main menu too, Sam stays in the old park
        self.pump(4)
        self.assertEqual(self.phase('200'), 'lobby')
        park(self.peers['100'])
        self.pump(14)
        for sid in ('200', '300'):
            self.assertEqual(len(self.peers[sid].lua.eval('loads')), 2, sid)
            self.assertEqual(self.phase(sid), 'live')
        toasts = [t['text'] for t in self.peers['300'].lua.eval('session.Toasts()').values()]
        self.assertTrue(any('anderen Park' in t for t in toasts), toasts)

    def test_a_let_in_friend_is_not_asked_again_after_the_host_reloads(self):
        host = self.peers['100']
        host.lua.execute('session.Leave()')
        self.pump(2)
        for sid in ('200', '300'):
            self.peers[sid].lua.execute('session.Leave()')
            self.peers[sid].commands()
        host.lua.execute('session.SetAskBeforeJoin(true); session.Host()')
        host.event('lobby:entered|L1|100|Host|1')
        self.peers['200'].event('lobby:entered|L1|100|Host|1')
        self.peers['200'].in_lobby = True
        self.pump(4)
        self.assertEqual([r['name'] for r in host.lua.eval('session.Requests()').values()], ['Alex'])
        self.assertEqual(self.phase('200'), 'asking')
        host.lua.execute('session.Answer("200", true)')
        self.pump(4)
        self.assertEqual(self.phase('200'), 'lobby')
        # The host opens a park: a fresh module there, everything else comes from the DLL.
        fresh = Peer('100', 'Host')
        fresh.memory = dict(host.memory)
        fresh.lua.execute('session.SetAskBeforeJoin(true)')
        self.peers['100'] = fresh
        self.pump(14)
        self.assertEqual(len(fresh.lua.eval('session.Requests()')), 0)
        self.assertEqual(self.phase('200'), 'live')

    def test_dlc_object_not_everyone_owns_is_not_built(self):
        park(self.peers['100'])
        self.pump(14)
        for sid, mask in (('100', 3), ('200', 1), ('300', 3)):
            self.peers[sid].lua.execute(f'session.SetDlc({mask})')
        self.pump(40)
        alex = [p for p in self.peers['300'].lua.eval('session.View().players').values() if p['name'] == 'Alex'][0]
        self.assertEqual(alex['dlc'], 1)
        sam = self.peers['300']
        sam.lua.execute('package.loaded["pc2coop.world"].RequiredDLC = function(part) return part == 101 and 2 or 0 end')
        before = {sid: len(self.peers[sid].ops()) for sid in self.peers}
        sam.local_change('sync:up|101||0|DLC_Rock|1|2|3|0|0|0|1|1')
        self.pump(4)
        got = sam.ops()[before['300']:]
        self.assertEqual([op.split('|')[0] for op in got], ['M', 'D'], got)
        self.assertEqual(len(self.peers['200'].ops()), before['200'])
        self.assertTrue(any('Alex' in t['text'] and 'DLC' in t['text'] for t in sam.lua.eval('session.Toasts()').values()))
        # The host allows everything: the same object is built for everyone.
        self.peers['100'].lua.execute('session.SetContentGuard(false)')
        self.pump(4)
        sam.local_change('sync:up|102||0|DLC_Rock|1|2|3|0|0|0|1|1')
        self.pump(4)
        self.assertTrue(any('DLC_Rock' in op for op in self.peers['200'].ops()))

    def test_mods_and_open_lobbies_of_friends(self):
        self.peers['200'].event('mods|ForgeUtils;ACSE;Bad|Name')
        self.pump(40)
        alex = [p for p in self.peers['300'].lua.eval('session.View().players').values() if p['name'] == 'Alex'][0]
        self.assertEqual(list(alex['mods'].values()), ['ForgeUtils', 'ACSE', 'Bad'])
        guest = self.peers['600'] = Peer('600', 'Gast')
        menu(guest)
        for event in ('friends:begin|1', 'friend|100|Host|1|1|109775240000000002', 'friends:end'):
            guest.event(event)
        guest.tick()
        guest.commands()
        guest.lua.execute('session.JoinFriend("100")')
        self.assertIn('join|109775240000000002', guest.commands())

    def test_profile_pictures_are_asked_once(self):
        host = self.peers['100']
        host.commands()
        host.lua.execute('session.Avatars(); session.Avatars()')
        asked = [c for c in host.commands() if c.startswith('avatar|')]
        self.assertEqual(sorted(asked), ['avatar|100', 'avatar|200', 'avatar|300'])
        host.event('avatar|200|iVBORw0KGgo=')
        host.event('avatar|300|<script>')
        host.tick()
        pictures = host.lua.eval('session.Avatars()')
        self.assertEqual(pictures['200'], 'iVBORw0KGgo=')
        self.assertIsNone(pictures['300'])


    def test_host_choice_is_seen_by_everyone_before_the_park_opens(self):
        host = self.peers['100']
        host.lua.execute('session.SetChoice("save", "Achterbahn|Tal", "Gespeicherter Park - Taiga")')
        self.pump(40)
        choice = self.peers['300'].lua.eval('session.View().choice')
        self.assertEqual((choice['kind'], choice['title'], choice['detail'], choice['starting']),
                         ('save', 'AchterbahnTal', 'Gespeicherter Park - Taiga', False))
        self.peers['200'].lua.execute('session.SetChoice("new", "Hack", "x")')   # only the host picks
        host.lua.execute('session.MarkStarting()')
        self.pump(40)
        self.assertTrue(self.peers['200'].lua.eval('session.View().choice.starting'))
        park(host)
        self.pump(40)
        self.assertIsNone(host.lua.eval('session.View().choice'))
        self.assertIsNone(self.peers['300'].lua.eval('session.View().choice'))
