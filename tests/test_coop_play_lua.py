"""Playing together: locks while editing, shared pause and speed, the session log, park
numbers and notifications. Three Lua runtimes over the simulated Steam lobby."""
import unittest

import test_session_lua as base

ROCK = 'AQ_Rock_04|1|2|3|0|0|0|1|1'
HUD = '''
local shared = require("pc2coop.shared")
shared.hud = {bPaused = false, nTimeScaleIndex = 1, ChangeSimulationSpeedSettings = function(self, paused, index)
    if paused ~= nil then self.bPaused = paused end
    if index ~= nil then self.nTimeScaleIndex = index end
end}
'''


@unittest.skipIf(base.LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class CoopPlayTests(unittest.TestCase):
    setUp = base.SessionTests.setUp
    lobby_enter = base.SessionTests.lobby_enter
    pump = base.SessionTests.pump

    def view(self, sid):
        return {p['name']: p for p in self.peers[sid].lua.eval('session.View().players').values()}

    def toasts(self, sid):
        return [t['text'] for t in self.peers[sid].lua.eval('session.Toasts()').values()]

    def feed(self):
        return list(self.peers['100'].lua.eval('session.View().feed').values())

    def host_ticks(self, n=60):
        self.peers['100'].lua.execute(f'for i = 1, {n} do session.Tick() end')
        self.pump(4)

    def build(self, sid, part='101'):
        """A player places a rock; returns the id the host gave it."""
        self.peers[sid].local_change(f'sync:up|{part}||0|{ROCK}')
        self.pump(4)
        ack = [op for op in self.peers[sid].ops() if op.startswith('M|')][-1]
        return ack.split('|')[2]

    def hold(self, sid, gid):
        self.peers[sid].local_change(f'sync:hold|AQ_Rock_04|{gid}|AQ_Rock_04,1.00,2.00,3.00,0,0,0,1,1.00')
        self.pump(4)

    def release(self, sid):
        self.peers[sid].local_change('sync:hold|')
        self.pump(4)

    def test_what_a_player_holds_reaches_everyone_and_locks_the_object(self):
        gid = self.build('200')
        self.hold('200', gid)
        for viewer in ('100', '300'):
            held = self.view(viewer)['Alex']['hold']
            self.assertEqual(held['label'], 'AQ_Rock_04')
            item = held['items'][1]
            self.assertEqual((item['resource'], item['model'], item['x'], item['z']), ('AQ_Rock_04', True, 1, 3))
            self.assertEqual(self.peers[viewer].lua.eval('sync.locks')[gid], 'Alex')
        own = self.peers['200'].lua.eval('sync.locks')      # the holder is not locked out himself
        self.assertTrue(own is None or own[gid] is None)
        self.release('200')
        self.assertIsNone(self.view('300')['Alex']['hold'])
        self.assertIsNone(self.peers['300'].lua.eval('sync.locks')[gid])

    def test_second_player_is_refused_and_told_who_holds_it(self):
        gid = self.build('200')
        self.hold('200', gid)
        self.hold('300', gid)
        self.peers['300'].lua.execute('for i = 1, 31 do session.Tick() end')   # not in this game: a notice card
        self.assertTrue(any('Alex baut hier gerade' in t for t in self.toasts('300')), self.toasts('300'))
        self.assertIsNone(self.view('100')['Sam']['hold'])
        self.assertEqual(self.view('100')['Alex']['hold']['label'], 'AQ_Rock_04')
        # Put down: now Sam may take it.
        self.release('200')
        self.hold('300', gid)
        self.assertEqual(self.view('100')['Sam']['hold']['label'], 'AQ_Rock_04')

    def test_change_to_an_object_someone_else_holds_is_taken_back(self):
        gid = self.build('200')
        self.hold('200', gid)
        before = len(self.peers['300'].ops())
        self.peers['300'].local_change(f'sync:up|55|{gid}|1|AQ_Rock_04|9|9|9|0|0|0|1|1')
        self.pump(4)
        answers = self.peers['300'].ops()[before:]
        self.assertTrue(any(op.startswith('R|') and op.endswith('|gesperrt|Alex') for op in answers), answers)
        restored = [op for op in answers if op.startswith('U|')][-1]
        self.assertIn('|AQ_Rock_04|1|2|3|', restored)
        self.peers['300'].local_change(f'sync:del|55|{gid}|1')
        self.pump(4)
        self.assertTrue(self.peers['100'].lua.eval(f'session.View().stats["Sam"].deleted') == 0)

    def test_leaving_frees_what_the_player_held(self):
        gid = self.build('200')
        self.hold('200', gid)
        self.peers['100'].event('member:leave|200')
        self.pump(4)
        self.assertIsNone(self.peers['300'].lua.eval('sync.locks')[gid])
        self.hold('300', gid)
        self.assertEqual(self.view('100')['Sam']['hold']['label'], 'AQ_Rock_04')

    def test_pause_and_speed_are_shared(self):
        for peer in self.peers.values():
            peer.lua.execute(HUD)
        self.peers['200'].lua.execute('session._LocalTime(true, 2)')
        self.pump(4)
        for sid in ('100', '300'):
            hud = self.peers[sid].lua.eval('require("pc2coop.shared").hud')
            self.assertEqual((hud['bPaused'], hud['nTimeScaleIndex']), (True, 2), sid)
        self.assertIn('Alex hat das Spiel pausiert', self.feed())
        self.assertIn('Alex hat das Spiel pausiert', self.toasts('300'))
        # The host lets it run again at x5.
        self.peers['100'].lua.execute('session._LocalTime(false, 3)')
        self.pump(4)
        hud = self.peers['200'].lua.eval('require("pc2coop.shared").hud')
        self.assertEqual((hud['bPaused'], hud['nTimeScaleIndex']), (False, 3))
        self.assertTrue(any('Host lässt das Spiel laufen (x5)' in t for t in self.toasts('200')))

    def test_many_placements_are_one_log_line(self):
        for part in range(101, 106):
            self.peers['200'].local_change(f'sync:up|{part}||0|{ROCK}')
        self.pump(4)
        self.peers['300'].local_change(f'sync:up|201||0|{ROCK}')
        self.pump(4)
        self.host_ticks()
        self.assertIn('Alex hat 5 Objekte platziert', self.feed())
        self.assertIn('Sam hat AQ_Rock_04 platziert', self.feed())
        self.assertEqual(sum('platziert' in line for line in self.feed()), 2)

    def test_host_cannot_place_a_friends_object_so_it_is_removed_everywhere(self):
        gid = self.build('200')
        placed = [op for op in self.peers['100'].ops() if op.startswith('U|') and f'|{gid}|' in op][-1]
        seq = placed.split('|')[1]
        self.peers['100'].local_change(f'sync:desync|{seq}|.\\\\pc2coop\\\\sync.lua:448: invalid-placement')
        self.pump(4)
        self.assertTrue(any(op.startswith('D|') and f'|{gid}|' in op for op in self.peers['200'].ops()))
        self.assertTrue(any(op.startswith('D|') and f'|{gid}|' in op for op in self.peers['300'].ops()))
        self.assertTrue(any('Objekt von Alex entfernt' in line and 'Parkgrenze' in line for line in self.feed()), self.feed())
        self.assertIsNone(self.peers['100'].lua.eval('session.Desync()'))

    def test_park_numbers_and_notifications_come_from_the_host(self):
        self.host_ticks(40)
        park = self.peers['300'].lua.eval('session.View().park')
        self.assertEqual((park['guests'], park['cash'], park['unlimited']), (1234, 5000, False))
        note = '[Notification_RideBroken:Name=|Teacups 1|]'
        self.peers['100'].lua.eval('function(t) session._ParkNote(t) end')(note)
        self.peers['100'].lua.eval('function(t) session._ParkNote(t) end')(note)   # the same again: not repeated
        self.pump(4)
        self.assertEqual(self.toasts('200').count(note), 1)

    def test_refusals_are_explained_to_the_player(self):
        peer = self.peers['300']
        peer.local_change('sync:rejected|g1|gesperrt')
        peer.local_change('sync:undo-blocked|undo')
        peer.local_change('sync:hold-lost')
        peer.lua.execute('for i = 1, 31 do session.Tick() end')   # g1 is not in this game: a notice card
        texts = ' / '.join(self.toasts('300'))
        self.assertIn('Zurückgenommen: Ein Mitspieler baut hier gerade.', texts)
        self.assertIn('eigenen letzten Schritt', texts)
        self.assertIn('Objekt geändert, das du gerade bearbeitet hast', texts)


if __name__ == '__main__':
    unittest.main()
