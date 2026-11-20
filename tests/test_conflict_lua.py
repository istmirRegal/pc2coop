"""Refused changes at the object (TP-16): the host names who was in the way, the refused
player sees a short line at the object (Session.Conflicts, drawn by the park manager), and
a notice card only when the object is not in that game. Three Lua runtimes over the
simulated Steam lobby."""
import unittest

import test_session_lua as base
import test_coop_play_lua as play

FOUND = 'sync.GidToEntity = function(gid) return 77 end'


@unittest.skipIf(base.LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class ConflictTests(unittest.TestCase):
    setUp = base.SessionTests.setUp
    lobby_enter = base.SessionTests.lobby_enter
    pump = base.SessionTests.pump
    build = play.CoopPlayTests.build
    hold = play.CoopPlayTests.hold
    toasts = play.CoopPlayTests.toasts

    def conflicts(self, sid):
        return [dict(c) for c in self.peers[sid].lua.eval('session.Conflicts()').values()]

    def color(self, sid, name):
        return {p['name']: p['color'] for p in self.peers[sid].lua.eval('session.View().players').values()}[name]

    def relay(self, sid, before):
        """What sync.lua does with an R line from the host (tested in test_editor_sync_lua)."""
        for op in self.peers[sid].ops()[before:]:
            f = op.split('|')
            if f[0] == 'R':
                self.peers[sid].local_change('sync:rejected|' + '|'.join(f[2:]))
        self.ticks(sid, 1)

    def ticks(self, sid, n):
        self.peers[sid].lua.execute(f'for i = 1, {n} do session.Tick() end')

    def test_a_locked_object_says_who_builds_there(self):
        gid = self.build('200')
        self.hold('200', gid)
        sam = self.peers['300']
        sam.lua.execute(FOUND)
        before = len(sam.ops())
        sam.local_change(f'sync:up|55|{gid}|1|AQ_Rock_04|9|9|9|0|0|0|1|1')
        self.pump(4)
        self.assertIn(f'R|{gid}|gesperrt|Alex', [op.split('|', 2)[0] + '|' + op.split('|', 2)[2] for op in sam.ops()[before:]])
        self.relay('300', before)
        [mark] = self.conflicts('300')
        self.assertEqual((mark['gid'], mark['text'], mark['color']), (gid, 'Alex baut hier gerade', self.color('300', 'Alex')))
        self.assertFalse([t for t in self.toasts('300') if 'Zurückgenommen' in t], 'shown at the object, no card')

    def test_a_stale_change_says_who_was_faster(self):
        gid = self.build('200')
        self.peers['200'].local_change(f'sync:up|101|{gid}|1|AQ_Rock_04|5|2|3|0|0|0|1|1')
        self.pump(4)
        self.peers['300'].lua.execute(FOUND)
        before = len(self.peers['300'].ops())
        self.peers['300'].local_change(f'sync:up|7|{gid}|1|AQ_Rock_04|9|2|3|0|0|0|1|1')
        self.pump(4)
        self.relay('300', before)
        self.assertEqual([c['text'] for c in self.conflicts('300')], ['Alex war schneller'])

    def test_picking_up_what_another_one_holds_is_marked_there(self):
        gid = self.build('200')
        self.hold('200', gid)
        self.peers['300'].lua.execute(FOUND)
        self.hold('300', gid)
        self.assertEqual([(c['gid'], c['text']) for c in self.conflicts('300')], [(gid, 'Alex baut hier gerade')])

    def test_the_line_goes_after_five_seconds(self):
        sam = self.peers['300']
        sam.lua.execute(FOUND)
        sam.local_change('sync:hold-lost|Vici|g7')
        self.ticks('300', 2)
        self.assertEqual([c['text'] for c in self.conflicts('300')], ['Vici hat das gerade geändert'])
        self.ticks('300', 300)
        self.assertEqual(self.conflicts('300'), [])
        self.assertEqual(self.toasts('300'), [t for t in self.toasts('300') if 'geändert' not in t])

    def test_an_object_that_is_not_here_gets_a_notice_card(self):
        sam = self.peers['300']
        sam.local_change('sync:rejected|g1|veraltet|Alex')
        self.ticks('300', 10)
        self.assertEqual(self.conflicts('300'), [], 'never found: not shown at an object')
        self.assertFalse([t for t in self.toasts('300') if 'schneller' in t], 'the object may still turn up')
        self.ticks('300', 25)
        self.assertIn('Zurückgenommen: Alex war bei diesem Objekt schneller.', self.toasts('300'))

    def test_names_and_ids_from_the_network_are_checked(self):
        sam = self.peers['300']
        sam.lua.execute(FOUND)
        sam.local_change('sync:rejected|bad id!|gesperrt|Al;ex,')
        sam.local_change('sync:rejected|g2|gesperrt|host')
        self.assertIn('Zurückgenommen: Alex baut hier gerade.', self.toasts('300'))
        self.ticks('300', 1)
        self.assertEqual([c['text'] for c in self.conflicts('300')], ['Ein Mitspieler baut hier gerade'])


if __name__ == '__main__':
    unittest.main()
