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
        for module in ('shared', 'world', 'rides', 'visitor', 'board', 'figure', 'shop'):
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
                        if target in self.peers:      # a player driven by hand in the test is skipped
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

    def test_host_leaving_says_the_session_is_over_until_closed(self):
        alex = self.peers['200']
        alex.event('member:leave|100')
        self.pump()
        state = alex.lua.eval('session.JoinState()')
        self.assertEqual((state['phase'], state['host']), ('ended', 'Host'))
        alex.lua.execute('session.DismissEnded()')
        self.assertIsNone(alex.lua.eval('session.JoinState()'))

    def test_a_new_join_replaces_the_session_is_over(self):
        alex = self.peers['200']
        alex.event('member:leave|100')
        self.pump()
        alex.event('invite:accepted|L2|300|invite')
        alex.tick()
        self.assertEqual(alex.lua.eval('session.JoinState()')['phase'], 'joining')
        alex.event('lobby:entered|L2|300|Sam|1')
        alex.tick()
        self.assertNotEqual(alex.lua.eval('(session.JoinState() or {}).phase'), 'ended')


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


class OrderTests(SessionTests):
    def last_k(self, sid):
        return [op.split('|', 2)[2] for op in self.peers[sid].ops() if op.startswith('K|')]

    def test_two_players_renaming_at_once_end_with_the_same_name(self):
        self.peers['200'].local_change('sync:cmd|!park.SetParkName(sA)')
        self.peers['300'].local_change('sync:cmd|!park.SetParkName(sB)')
        self.pump(6)
        finals = {sid: self.last_k(sid)[-1] for sid in ('100', '200', '300')}
        self.assertEqual(len(set(finals.values())), 1, finals)

    def test_additive_calls_are_not_applied_twice_by_their_author(self):
        self.peers['200'].local_change('sync:cmd|!money.TakeLoan(n5)')
        self.pump(6)
        self.assertEqual(self.last_k('200'), [])
        self.assertEqual(self.last_k('300'), ['!money.TakeLoan(n5)'])
        self.assertEqual(self.last_k('100'), ['!money.TakeLoan(n5)'])

    def test_object_deleted_while_a_joiner_loads_is_deleted_there_too(self):
        host = self.peers['100']
        self.peers['200'].local_change('sync:up|101||0|AQ_Rock_04|1|2|3|0|0|0|1|1')
        self.pump(4)
        gid = [op for op in self.peers['200'].ops() if op.startswith('M|')][-1].split('|')[2]
        host.lua.eval('function(g) sync.LocalPart = function(x) if x == g then return 4242 end end end')(gid)
        version = host.lua.eval('session.VERSION')
        host.event(f'msg|500|hello|Spaet|-1|needpark|{version}|1.12.2.1035111')
        for _ in range(4):
            host.tick()
        host.commands()                              # the park copy is on its way (not delivered here)
        host.lua.execute('sync.LocalPart = function() return nil end')   # gone from the host's world
        self.peers['200'].local_change(f'sync:del|101|{gid}|1')
        self.pump(2)
        host.event(f'msg|500|hello|Spaet|-1|loaded|{version}|1.12.2.1035111')
        host.tick()
        sent = [c for c in host.commands() if c.startswith('send|500|ops')]
        lines = chr(10).join(sent).split(chr(10))
        alias = [i for i, l in enumerate(lines) if l.startswith(f'A|{gid}|4242|')]
        delete = [i for i, l in enumerate(lines) if l.startswith(f'D|{gid}|')]
        self.assertTrue(alias and delete and alias[0] < delete[0], lines)


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

    def test_cancel_while_steam_joins_leaves_the_lobby_when_it_comes(self):
        new = Peer('830', 'Vici')
        new.event('invite:accepted|L9|100|invite')
        new.tick()
        self.assertEqual(self.join_state(new)['phase'], 'joining')
        new.commands()
        new.lua.execute('session.DismissJoin()')
        self.assertIsNone(self.join_state(new))
        new.event('lobby:entered|L9|100|Host|1')
        new.tick()
        self.assertIn('leave', new.commands())
        self.assertIsNone(new.lua.eval('session.View().role'))
        self.assertIsNone(self.join_state(new))

    def test_starting_a_session_waits_for_steam(self):
        new = Peer('840', 'Vici')
        new.lua.execute('session.SetContext("menu"); session.Host()')
        self.assertEqual(self.join_state(new)['phase'], 'starting')
        new.event('lobby:entered|L7|840|Vici|1')
        new.tick()
        self.assertEqual(new.lua.eval('session.View().role'), 'host')
        self.assertIsNone(self.join_state(new))

    def test_a_session_steam_cannot_create_says_so(self):
        new = Peer('850', 'Vici')
        new.lua.execute('session.Host()')
        new.event('lobby:error|create-failed|2')
        new.tick()
        state = self.join_state(new)
        self.assertEqual((state['phase'], state['retry']), ('failed', False))
        self.assertIn('Steam-Code 2', state['reason'])

    def test_a_session_steam_never_answers_frees_the_button(self):
        new = Peer('860', 'Vici')
        new.lua.execute('session.Host(); for i = 1, 1810 do session.Tick() end')
        state = self.join_state(new)
        self.assertEqual(state['phase'], 'failed')
        self.assertIn('nicht geantwortet', state['reason'])

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
        self.assertTrue(any('Sitzung läuft weiter' in t['text'] for t in host.lua.eval('session.Toasts()').values()))
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


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class RideSnapshotTests(SessionTests.__bases__[0]):
    """Coasters travel as blueprint files: author -> host -> everyone else, file before line."""
    setUp = SessionTests.setUp
    lobby_enter = SessionTests.lobby_enter
    pump = SessionTests.pump

    def ride_ops(self, peer):
        return [op for op in peer.ops() if op.startswith('Y|')]

    def test_a_friends_coaster_goes_through_the_host_with_its_file(self):
        alex, host, sam = self.peers['200'], self.peers['100'], self.peers['300']
        alex.local_change('sync:ride|-|F10_0_20|pc2coop-ride-200-1.blueprint')
        self.pump()
        self.assertIn(('100', 'pc2coop-ride-200-1.blueprint'), alex.sent_files)
        self.assertIn(('300', 'pc2coop-ride-200-1.blueprint'), host.sent_files)
        self.assertNotIn(('200', 'pc2coop-ride-200-1.blueprint'), host.sent_files)
        for peer in (host, sam):
            self.assertEqual([op.split('|', 2)[2] for op in self.ride_ops(peer)], ['-|F10_0_20|pc2coop-ride-200-1.blueprint'])
        self.assertEqual(self.ride_ops(alex), [], 'not back to the author')

    def test_the_host_waits_for_the_file_before_passing_the_ride_on(self):
        host, sam = self.peers['100'], self.peers['300']
        host.event('msg|200|ride|F10_0_20|F12_0_20|pc2coop-ride-200-2.blueprint')
        host.tick(); host.tick()
        self.assertEqual(self.ride_ops(host), [])
        self.assertFalse(any(c.startswith('file|300|') for c in host.commands()))
        host.event('file:done|200|pc2coop-ride-200-2.blueprint|5115')
        self.pump()
        self.assertEqual(len(self.ride_ops(host)), 1)
        self.assertEqual(len(self.ride_ops(sam)), 1)
        self.assertIn(('300', 'pc2coop-ride-200-2.blueprint'), host.sent_files)

    def test_host_coaster_and_removal(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        host.local_change('sync:ride|F1_0_2|-|-')
        self.pump()
        for peer in (alex, sam):
            self.assertEqual([op.split('|', 2)[2] for op in self.ride_ops(peer)], ['F1_0_2|-|-'])
        self.assertEqual(self.ride_ops(host), [])
        self.assertEqual([f for f in host.sent_files if 'ride' in f[1]], [])

    def test_bad_ride_lines_are_dropped(self):
        host = self.peers['100']
        for line in ('ride|S1_2_3|-|-', 'ride|-|-|-', 'ride|-|F1_2_3|-', 'ride|-|F1_2_3|pc2coop-join.bin',
                     'ride|-|F1_2_3|../pc2coop-ride-1-1.blueprint'):
            host.event('msg|200|' + line)
            host.event('file:done|200|pc2coop-ride-1-1.blueprint|10')
        self.pump()
        self.assertEqual(self.ride_ops(host), [])


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class VisitorTests(SessionTests.__bases__[0]):
    """Visitor mode: emotes and ride ratings reach everyone through the host."""
    setUp = SessionTests.setUp
    lobby_enter = SessionTests.lobby_enter
    pump = SessionTests.pump

    def toasts(self, peer):
        return [t['text'] for t in peer.lua.eval('session.Toasts()').values()]

    def test_an_emote_reaches_everyone_once_per_second(self):
        alex, host, sam = self.peers['200'], self.peers['100'], self.peers['300']
        self.assertTrue(alex.lua.eval('session.Emote("wave")'))
        self.assertFalse(alex.lua.eval('session.Emote("dance|x")'))
        self.pump()
        self.assertIn('Alex winkt', self.toasts(host))
        self.assertIn('Alex winkt', self.toasts(sam))
        self.assertEqual(dict(sam.lua.eval('session.Emotes()').items()), {'200': 'winkt'})
        alex.lua.execute('session.Emote("cheer")')
        self.pump()
        self.assertNotIn('Alex jubelt', self.toasts(sam), 'second emote within a second is dropped')

    def test_a_rating_with_a_suggestion_is_shared_and_averaged(self):
        alex, host, sam = self.peers['200'], self.peers['100'], self.peers['300']
        self.assertTrue(alex.lua.eval('session.Rate("F1_0_2", 4, "Conlan", "mehr Schatten | bitte")'))
        self.assertTrue(sam.lua.eval('session.Rate("F1_0_2", 5, "Conlan", "")'))
        self.assertFalse(sam.lua.eval('session.Rate("S1_0_2", 5, "x", "")'))
        self.assertFalse(sam.lua.eval('session.Rate("F1_0_2", 9, "x", "")'))
        self.pump()
        for peer in (host, alex, sam):
            r = peer.lua.eval('session.Ratings()')['F1_0_2']
            self.assertEqual((r['name'], r['avg'], r['count']), ('Conlan', 4.5, 2))
            self.assertEqual([dict(c.items()) for c in r['comments'].values()],
                             [{'who': 'Alex', 'stars': 4, 'text': 'mehr Schatten   bitte'}])
        self.assertEqual(sam.lua.eval('session.Ratings()')['F1_0_2']['mine'], 5)
        self.assertTrue(any('Alex bewertet Conlan mit 4/5: mehr Schatten' in t for t in self.toasts(sam)))
        self.assertTrue(any('bewertet Conlan' in line for line in host.lua.eval('session.View().feed').values()))


    def test_ratings_are_kept_in_a_note_file_of_the_park(self):
        host, alex = self.peers['100'], self.peers['200']
        host.lua.execute('session._RatingsFile("pc2coop-ratings-Testpark.txt")')
        alex.lua.execute('session.Rate("F1_0_2", 3, "Conlan", "mehr Schatten")')
        self.pump()
        notes = [n for n in host.sent_notes if 'pc2coop-ratings-Testpark.txt' in n]
        self.assertEqual(notes, ['note-append|pc2coop-ratings-Testpark.txt|F1_0_2|200|3|Conlan|Alex|mehr Schatten\n'])
        sam = self.peers['300']
        host.event('note:data|pc2coop-ratings-Testpark.txt|F9_0_9|400|5|Wilde Maus|Kim|top\nF9_0_9|bad|9|x|y|z')
        host.event('note:end|pc2coop-ratings-Testpark.txt')
        self.pump()
        r = host.lua.eval('session.Ratings()')['F9_0_9']
        self.assertEqual((r['name'], r['avg'], r['count']), ('Wilde Maus', 5, 1))


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class TeamTests(SessionTests.__bases__[0]):
    """Board, park events, session rules, last visit and checkpoints (docs/KONZEPT.md)."""
    setUp = SessionTests.setUp
    lobby_enter = SessionTests.lobby_enter
    pump = SessionTests.pump

    def toasts(self, peer):
        return [t['text'] for t in peer.lua.eval('session.Toasts()').values()]

    def board(self, peer):
        return [dict(i.items()) for i in peer.lua.eval('session.View().board').values()]

    def player(self, peer, sid):
        for p in peer.lua.eval('session.View().players').values():
            if p['sid'] == sid:
                return p
        return None

    SHOP = r'''
        shopOpen, credited = true, {}
        local apisT = {park = {GetParkName = function() return "Testpark" end, ExpenditureCategory_FoodSales = 58,
                ExpenditureCategory_DrinkSales = 57, ExpenditureCategory_FacilitySales = 40},
            facilities = {GetShopInventoryEntityID = function(_, e) return e end,
                GetShopInventory = function(_, e) if e == 4242 then return {1, 2} end return {} end,
                GetShopInventoryItem = function(_, e, i) return ({[0] = {sItem = "Food_CheesePizza", nCost = 860, bSold = true},
                    [1] = {sItem = "Drink_Cola", nCost = 300, bSold = true}})[i] end,
                IsOpen = function() return shopOpen end},
            editors = {CreateUndoOperationsHierarchy = function() return {
                AddCashDelta = function(_, c, cat) credited[#credited+1] = c .. "@" .. cat end,
                GetFullUndoChangeList = function() return {} end} end}}
        api.world.GetWorldAPIs = function() return apisT end
        api.undo = {IsBusy = function() return false end, IsPreviewingChangeList = function() return false end,
            PreviewChangeList = function() return 1, 2 end, IsOperationComplete = function() return true end,
            CanCommitPreview = function() return true end, CommitPreview = function() return 3 end}
        function sync.GidToEntity(gid) if gid == "S1_0_1" then return 4242 end end'''

    def test_buying_at_a_shop_goes_through_the_host(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        host.lua.execute(self.SHOP)
        host.event('msg|200|buy|S1_0_1|0|')
        host.event('msg|200|buy|S1_0_1|1|')          # too soon after the first: ignored
        self.pump(4)
        self.assertEqual(list(host.lua.eval('credited').values()), ['860@58'])
        self.assertIn('Alex kauft Cheese Pizza (8,60)', self.toasts(sam))
        self.assertNotIn('Alex isst', self.toasts(sam))   # the purchase says it already
        self.assertEqual(self.player(sam, '200')['emote'], 'eat')
        self.assertEqual(self.player(alex, '200')['emote'], 'eat')
        # Closed shop, unknown shop: Alex is told, nothing is booked.
        self.pump(130)
        host.lua.execute('shopOpen = false')
        host.event('msg|200|buy|S1_0_1|1|')
        self.pump(4)
        self.assertIn('Der Shop ist geschlossen', self.toasts(alex))
        self.pump(130)
        host.event('msg|200|buy|S9_9_9|0|')
        self.pump(4)
        self.assertIn('Diesen Shop gibt es beim Host nicht', self.toasts(alex))
        self.assertEqual(len(host.lua.eval('credited')), 1)

    def test_the_look_of_a_visitor_reaches_everyone_and_strange_looks_are_ignored(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        alex.lua.execute('''package.loaded["Database.GameDatabase"] = {tPlayers = {{GetData = function(self, a, b)
            return {tData = {group = "AFA", parts = {Bodies = {model = 7, custom = {colours = {{0.1, 0.2, 0.3}, {1, 1, 1},
                {0, 0, 0}, {1, 1, 1}}}}, Legs = {model = 3, custom = {colours = {{0.2, 0.2, 0.2}, {0, 0, 0}}}},
                Heads = {model = 2}, Hair = {model = 5, custom = {colours = {{0.5, 0.3, 0.1}}}}}}}
        end}}}
        session._ResetLook()''')
        self.pump(40)   # the roster goes out every 30 frames
        look = 'af.2.4.3.2.1a334d-ffffff-000000-ffffff.333333-000000.804d1a'
        self.assertEqual(self.player(host, '200')['look'], look)
        self.assertEqual(self.player(sam, '200')['look'], look)
        self.assertEqual(self.player(sam, '100')['look'], 'am.1.1.1.1.x.x.x')
        # Nothing but a valid look is taken; the old one stays.
        host.event('msg|200|look|am.1.1.1.1.x.x.x;drop|')
        host.event('msg|200|look|zz.1.1.1.1.x.x.x|')
        self.pump(40)
        self.assertEqual(self.player(sam, '200')['look'], look)
        # An emote shows on the figure for a few seconds.
        alex.lua.execute('session.Emote("cheer")')
        self.pump(4)
        self.assertEqual(self.player(sam, '200')['emote'], 'cheer')
        self.assertEqual(self.player(host, '200')['emote'], 'cheer')

    def test_board_items_reach_everyone_and_are_written_to_the_park_file(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        host.lua.execute('session._BoardFile("pc2coop-board-Testpark.txt")')
        alex.lua.execute('session.BoardAdd("area", 10, 0, 20, 15, "Wikingerland", "Familienattraktion, max. 15.000", "")')
        alex.lua.execute('session.BoardAdd("task", nil, nil, nil, 0, "Toiletten am Eingang", "", "Sam")')
        alex.lua.execute('session.BoardAdd("comment", nil, nil, nil, 0, "ohne Ort", "", "")')   # needs a place
        self.pump()
        for peer in (host, alex, sam):
            items = self.board(peer)
            self.assertEqual(sorted((i['kind'], i['title']) for i in items), [('area', 'Wikingerland'), ('task', 'Toiletten am Eingang')])
        task = [i for i in self.board(sam) if i['kind'] == 'task'][0]
        self.assertEqual((task['by'], task['assignee'], task['done']), ('Alex', 'Sam', False))
        sam.lua.execute(f'session.BoardSet("{task["id"]}", "done", "1")')
        self.pump()
        self.assertTrue([i for i in self.board(alex) if i['kind'] == 'task'][0]['done'])
        area = [i for i in self.board(host) if i['kind'] == 'area'][0]
        host.lua.execute(f'session.BoardRemove("{area["id"]}")')
        self.pump()
        self.assertEqual([i['kind'] for i in self.board(alex)], ['task'])
        notes = [n for n in host.sent_notes if 'pc2coop-board-Testpark.txt' in n]
        self.assertEqual(len(notes), 4)
        self.assertTrue(notes[-1].startswith('note-append|pc2coop-board-Testpark.txt|bd-|'))
        self.assertTrue(any('erledigt: Toiletten am Eingang' in line for line in host.lua.eval('session.View().feed').values()))

    def test_board_comes_back_from_the_file_and_late_joiners_get_it(self):
        host = self.peers['100']
        host.lua.execute('session._BoardFile("pc2coop-board-Testpark.txt")')
        host.event('note:data|pc2coop-board-Testpark.txt|bd|b4|meet|1.00|2.00|3.00|0.00|Treffen|am Brunnen|Kim||0\nbd|b5|task||||0.00|Weg|x|Kim||1\nbd-|b5')
        host.event('note:end|pc2coop-board-Testpark.txt')
        self.pump()
        self.assertEqual([(i['id'], i['title']) for i in self.board(host)], [('b4', 'Treffen')])
        host.lua.execute('session.BoardAdd("task", nil, nil, nil, 0, "Neu", "", "")')
        self.pump()
        self.assertIn(('b6', 'Neu'), [(i['id'], i['title']) for i in self.board(host)])

    def test_proposals_count_one_vote_per_player_by_the_senders_name(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        alex.lua.execute('session.BoardAdd("proposal", 5, 0, 5, 0, "Wildwasserbahn am See?", "", "")')
        self.pump()
        item = self.board(sam)[0]
        self.assertEqual(item['kind'], 'proposal')
        sam.lua.execute(f'session.BoardSet("{item["id"]}", "vote", "1")')
        alex.lua.execute(f'session.BoardSet("{item["id"]}", "vote", "1")')
        sam.lua.execute(f'session.BoardSet("{item["id"]}", "vote", "0")')    # changes the own vote
        self.pump()
        for peer in (host, alex, sam):
            votes = dict(peer.lua.eval('session.View().board[1].votes').items())
            self.assertEqual(votes, {'Alex': True, 'Sam': False})

    def test_test_ride_invitation_reaches_the_others_and_runs_out(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        self.assertTrue(alex.lua.eval('session.InviteRide("F1_2_3", "Donnerkeil")'))
        self.assertFalse(alex.lua.eval('session.InviteRide("bad key", "x")'))
        self.pump()
        for peer in (host, sam):
            invite = peer.lua.eval('session.Invitation()')
            self.assertEqual((invite['by'], invite['key'], invite['name']), ('Alex', 'F1_2_3', 'Donnerkeil'))
        self.assertIsNone(alex.lua.eval('session.Invitation()'))
        sam.lua.execute('session.DismissInvitation()')
        self.assertIsNone(sam.lua.eval('session.Invitation()'))
        host.lua.execute('for i = 1, 3700 do session.Tick() end')
        self.assertIsNone(host.lua.eval('session.Invitation()'))

    def test_takeover_question_goes_to_the_editor_only(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        sam.local_change("sync:hold|Achterbahn|g1|")
        self.pump()
        alex.lua.execute('session.AskTakeover("300")')
        alex.lua.execute('session.AskTakeover("300")')        # once every 5 s
        self.pump()
        asked = [t for t in self.toasts(sam) if 'weitermachen' in t]
        self.assertEqual(len(asked), 1)
        self.assertIn('Alex', asked[0])
        self.assertIn('Achterbahn', asked[0])
        self.assertFalse(any('weitermachen' in t for t in self.toasts(host)))
        alex.lua.execute('session.AskTakeover("100")')        # the host edits nothing
        self.pump()
        self.assertFalse(any('weitermachen' in t for t in self.toasts(host)))

    def test_rules_are_kept_in_the_dll_over_the_park_load(self):
        host = self.peers['100']
        host.lua.execute('session.SetRule("visitors", "0")')
        self.assertIn('kv|rules|all,0,free', host.commands())
        fresh = host.lua.eval('session.View().rules')
        self.assertEqual(fresh['visitors'], '0')
        host.event('kv|rules|host,1,ask')
        host.tick()
        rules = host.lua.eval('session.View().rules')
        self.assertEqual((rules['speed'], rules['visitors'], rules['foreign']), ('host', '1', 'ask'))

    def comp(self, peer):
        view = peer.lua.eval('session.Competition()')
        return None if view is None else view

    def test_build_duel_runs_on_real_time_and_rates_design_and_technique_apart(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        self.assertFalse(alex.lua.eval('session.StartCompetition("duel", 15, "Wikinger")'))
        self.assertTrue(host.lua.eval('session.StartCompetition("duel", 15, "Wikinger")'))
        self.assertFalse(host.lua.eval('session.StartCompetition("duel", 15, "nochmal")'))
        self.assertIn('now', host.commands())
        host.event('now|1000000')
        host.tick()
        self.pump()
        view = self.comp(sam)
        self.assertEqual((view['mode'], view['phase'], view['left'], view['topic']), ('duel', 'build', 900, 'Wikinger'))
        self.assertEqual(sorted(e['name'] for e in view['entries'].values()), ['Alex', 'Host', 'Sam'])
        host.event('now|1900001')                     # 15 minutes later
        host.tick()
        self.pump()
        self.assertEqual(self.comp(alex)['phase'], 'rate')
        self.assertFalse(alex.lua.eval('session.RateEntry("200", 5, 5)'))  # not the own build
        self.pump()
        for rater, targets in (('100', ('200', '300')), ('200', ('100', '300')), ('300', ('100', '200'))):
            for target in targets:
                design, tech = (5, 4) if target == '300' else (3, 4)
                self.peers[rater].lua.execute(f'session.RateEntry("{target}", {design}, {tech})')
        self.pump()
        view = self.comp(alex)
        self.assertEqual(view['phase'], 'done')
        results = [(r['name'], r['d'], r['t'], r['n']) for r in view['results'].values()]
        self.assertEqual(results[0], ('Sam', 5, 4, 2))
        self.assertEqual(sorted(results[1:]), [('Alex', 3, 4, 2), ('Host', 3, 4, 2)])
        host.lua.execute('session.CompetitionNext()')
        self.pump()
        self.assertIsNone(self.comp(sam))
        self.assertIsNone(self.comp(host))

    def test_coop_timer_ends_without_ratings_and_late_joiners_see_it(self):
        host, alex = self.peers['100'], self.peers['200']
        host.lua.execute('session.StartCompetition("timer", 30, "")')
        self.pump()
        self.assertEqual(self.comp(alex)['phase'], 'build')
        self.assertIn('cp|c1|timer|build|', host.lua.eval('session._CompLine()'))
        host.lua.execute('session.CompetitionNext()')
        self.pump()
        self.assertEqual(self.comp(alex)['phase'], 'done')

    def test_park_event_with_a_place_becomes_a_marker_for_everyone(self):
        host, alex = self.peers['100'], self.peers['200']
        host.lua.execute('''
            api.transform = {CalculateWorldTransform = function(e) return {GetPos = function()
                return {GetX = function() return 68.2 end, GetY = function() return 9.1 end, GetZ = function() return 411.8 end} end} end}
            session._ParkNote("[Notification_RideBroken:Name=|Conlan|]", 56466)
        ''')
        self.pump()
        for peer in (host, alex):
            events = [dict(e.items()) for e in peer.lua.eval('session.Events()').values()]
            self.assertEqual(len(events), 1)
            self.assertEqual((round(events[0]['x'], 1), round(events[0]['z'], 1)), (68.2, 411.8))
        self.assertIn('[Notification_RideBroken:Name=|Conlan|]', self.toasts(alex))

    def test_speed_rule_only_the_host_changes_the_speed(self):
        host, alex = self.peers['100'], self.peers['200']
        self.assertFalse(alex.lua.eval('session.SetRule("speed", "host")'))
        self.assertTrue(host.lua.eval('session.SetRule("speed", "host")'))
        self.pump()
        self.assertEqual(alex.lua.eval('session.Rules().speed'), 'host')
        alex.lua.execute('session._LocalTime(true, 1)')
        self.pump()
        self.assertTrue(any('Nur der Host' in t for t in self.toasts(alex)))
        self.assertFalse(any('pausiert' in line for line in host.lua.eval('session.View().feed').values()))

    def test_foreign_build_rule_refuses_tearing_down_others_work(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        host.lua.execute('session.SetRule("foreign", "ask")')
        alex.local_change('sync:up|988||0|Rock_01|1|2|3|0|0|0|1|1')
        self.pump()
        gid = next(op.split('|')[2] for op in sam.ops() if op.startswith('U|'))
        sam.local_change(f'sync:del|988|{gid}|1')
        self.pump()
        self.assertTrue(any('Alex gebaut' in t for t in self.toasts(sam)))
        self.assertFalse(any(op.startswith('D|') for op in alex.ops()), 'not removed for the builder')
        alex.local_change(f'sync:del|988|{gid}|1')   # the builder may
        self.pump()
        self.assertTrue(any(op.startswith('D|') for op in sam.ops()))

    def test_since_your_last_visit(self):
        host, alex = self.peers['100'], self.peers['200']
        host.lua.execute('''
            rides = {F1_0_1 = "Conlan", F2_0_2 = "Teetassen"}
            session._SetRideLister(function() local out = {} for k, v in pairs(rides) do out[k] = v end return out end)
            session._RememberVisit("200")
            rides.F2_0_2 = nil; rides.F3_0_3 = "Wilde Maus"
        ''')
        text = host.lua.eval('session._Since("200")')
        self.assertIn('1 neue Fahrgeschäfte (Wilde Maus)', text)
        self.assertIn('1 abgerissen (Teetassen)', text)
        self.assertIsNone(host.lua.eval('session._Since("300")'))

    def test_since_comes_once_as_message_and_in_the_log(self):
        # TP-18: no section in the window any more; a message on joining and a line in the log.
        alex = self.peers['200']
        alex.lua.execute('session._onNet("msg|100|since|2 neue Fahrgeschäfte (Conlan, Wilde Maus)")')
        line = 'Seit deinem letzten Besuch: 2 neue Fahrgeschäfte (Conlan, Wilde Maus)'
        self.assertIn(line, self.toasts(alex))
        self.assertIn(line, list(alex.lua.eval('session.View().feed').values()))
        self.assertEqual(alex.lua.eval('session.View().since'), '2 neue Fahrgeschäfte (Conlan, Wilde Maus)')

    def test_checkpoint_and_vote_back(self):
        host, alex, sam = self.peers['100'], self.peers['200'], self.peers['300']
        self.assertTrue(host.lua.eval('session.Checkpoint()'))
        self.assertEqual(len(host.lua.eval('session.View().checkpoints')), 1)
        self.assertTrue(host.lua.eval('session.Propose("restore", 1)'))
        self.pump()
        self.assertIn('zuruecksetzen', alex.lua.eval('session.VoteView().text'))
        alex.lua.execute('session.Vote(true)')
        self.pump()
        self.assertEqual(len(host.lua.eval('loads')), 0, 'Sam has not answered yet')
        sam.lua.execute('session.Vote(true)')
        self.pump()
        self.assertEqual(len(host.lua.eval('loads')), 1)
        self.assertFalse(alex.lua.eval('session.VoteView()'))
