"""Ping, camera follow, authors of objects, and getting back in after a dropped connection.
Three Lua runtimes over the simulated Steam lobby."""
import unittest

import test_session_lua as base

ROCK = 'AQ_Rock_04|1|2|3|0|0|0|1|1'
# The world module answers "where is the cursor" from this fake.
CURSOR = '''
package.loaded["pc2coop.world"].CursorPoint = function() return 40, 2, 60 end
'''
# sync.lua stand-ins the host uses for attribution: local parts and their state.
PARTS = '''
sync.parts = {}
function sync.LocalPart(gid) return sync.parts[gid] end
function sync.StateOf(gid)
    local part = tonumber(string.match(gid, "^P(%d+)$"))
    if part == 4242 then return {res = "AQ_Rock_04"} end
    return nil
end
'''


@unittest.skipIf(base.LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class PresenceExtrasTests(unittest.TestCase):
    setUp = base.SessionTests.setUp
    lobby_enter = base.SessionTests.lobby_enter
    pump = base.SessionTests.pump

    def host(self):
        return self.peers['100']

    def pings(self, sid):
        return {p['sid']: (p['x'], p['z']) for p in self.peers[sid].lua.eval('session.Pings()').values()}

    def toasts(self, sid):
        return [t['text'] for t in self.peers[sid].lua.eval('session.Toasts()').values()]

    # --- ping -------------------------------------------------------------------------------

    def test_ping_reaches_everyone_and_fades(self):
        self.peers['200'].lua.execute(CURSOR)
        self.peers['200'].event('key:ping')
        self.pump(4)
        for sid in ('100', '200', '300'):
            self.assertEqual(self.pings(sid), {'200': (40, 60)}, sid)
        self.assertTrue(any('Alex zeigt auf etwas' in t for t in self.toasts('300')))
        self.peers['300'].lua.execute('for i = 1, 500 do session.Tick() end')
        self.assertEqual(self.pings('300'), {})

    def test_short_middle_click_pings_but_turning_the_camera_does_not(self):
        alex = self.peers['200']
        alex.lua.execute(CURSOR + """
cam = {10, 20, 30, 0.5, 0.4}
package.loaded["pc2coop.world"].Camera = function() return cam[1], cam[2], cam[3], cam[4], cam[5] end
""")
        def click(ms, travel, turn=False):
            alex.event('key:mdown')
            alex.tick()
            if turn:
                alex.lua.execute('cam[4] = cam[4] + 0.3')
            alex.event(f'key:mup|{ms}|{travel}')
            alex.tick()
            return len([c for c in alex.commands() if '|ping|' in c])
        self.assertEqual(click(120, 4), 1)
        alex.lua.execute('for i = 1, 70 do session.Tick() end')
        self.assertEqual(click(120, 4, turn=True), 0)   # quick drag that turned the camera
        self.assertEqual(click(900, 0), 0)              # held down
        self.assertEqual(click(150, 400), 0)            # the cursor moved
        alex.event('key:mup|100|0')                     # release without a press seen
        alex.tick()
        self.assertEqual(len([c for c in alex.commands() if '|ping|' in c]), 0)

    def test_ping_flood_is_cut_to_one_per_second(self):
        self.peers['200'].lua.execute(CURSOR)
        for _ in range(5):
            self.peers['200'].lua.execute('session.Ping()')
        self.pump(4)
        relayed = [t for t in self.toasts('300') if 'zeigt auf etwas' in t]
        self.assertEqual(len(relayed), 1)

    # --- follow -----------------------------------------------------------------------------

    def test_follow_sees_the_others_camera_and_pitch(self):
        self.peers['200'].local_change('sync:pres|7.0|20.0|9.0|1.5|-0.4|4|Orbit|baut|10.0|5.0|12.0')
        self.pump(4)
        alex = [p for p in self.peers['300'].lua.eval('session.View().players').values() if p['sid'] == '200'][0]
        self.assertEqual((alex['x'], alex['y'], alex['z'], alex['yaw'], alex['pitch']), (7, 20, 9, 1.5, -0.4))
        self.peers['300'].lua.execute('session.SetFollow("200")')
        self.assertEqual(self.peers['300'].lua.eval('session.Following()'), '200')
        self.peers['300'].lua.execute('session.Leave()')
        self.assertIsNone(self.peers['300'].lua.eval('session.Following()'))

    # --- authors ----------------------------------------------------------------------------

    def ask(self, sid, gid):
        self.peers[sid].lua.eval('function(g) return session.Attribution(g) end')(gid)
        self.pump(4)
        who = self.peers[sid].lua.eval('function(g) return session.Attribution(g) end')(gid)
        return (who['creator'], who['last']) if who is not None else None

    def test_author_and_last_editor_are_answered_by_the_host(self):
        self.peers['200'].local_change(f'sync:up|101||0|{ROCK}')
        self.pump(4)
        gid = [op for op in self.peers['200'].ops() if op.startswith('M|')][-1].split('|')[2]
        self.peers['300'].local_change(f'sync:up|55|{gid}|1|AQ_Rock_04|9|9|9|0|0|0|1|1')
        self.pump(4)
        self.assertEqual(self.ask('300', gid), ('Alex', 'Sam'))
        self.assertEqual(self.ask('100', gid), ('Alex', 'Sam'))     # the host asks itself
        self.assertEqual(self.ask('200', 'P1'), ('', ''))           # nobody touched it

    def test_authors_are_written_per_park_and_survive_a_restart(self):
        host = self.host()
        host.lua.execute(PARTS)
        self.peers['200'].local_change(f'sync:up|101||0|{ROCK}')
        self.pump(4)
        gid = [op for op in self.peers['200'].ops() if op.startswith('M|')][-1].split('|')[2]
        host.lua.eval('function(g) sync.parts[g] = 4242 end')(gid)
        host.lua.execute('for i = 1, 300 do session.Tick() end')
        written = [c for c in host.commands() if c.startswith('note-append|')]
        self.assertEqual(len(written), 1, written)
        self.assertTrue(written[0].startswith('note-append|pc2coop-authors-Testpark.txt|4242|AQ_Rock_04|Alex|Alex'))
        # Next session in this park: the object is base park "P4242" and keeps its author.
        fresh = base.Peer('100', 'Host')
        fresh.lua.execute(PARTS)
        fresh.event('lobby:entered|L2|100|Host|1')
        fresh.tick()
        self.assertIn('note-read|pc2coop-authors-Testpark.txt', fresh.commands())
        fresh.event('note:data|pc2coop-authors-Testpark.txt|4242|AQ_Rock_04|Alex|Alex\n4243|Fern|Sam|Sam\n')
        fresh.event('note:end|pc2coop-authors-Testpark.txt')
        fresh.tick()
        fresh.lua.execute('sync.parts["P4242"] = 4242')
        fresh.lua.execute('session.Attribution("P4242")')
        fresh.tick()
        who = fresh.lua.eval('session.Attribution("P4242")')
        self.assertEqual((who['creator'], who['last']), ('Alex', 'Alex'))
        # 4243 no longer stands as a Fern (park not saved): no author for it.
        fresh.lua.execute('sync.parts["P4243"] = 4243; session.Attribution("P4243")')
        fresh.tick()
        who = fresh.lua.eval('session.Attribution("P4243")')
        self.assertEqual((who['creator'], who['last']), ('', ''))

    # --- reconnect --------------------------------------------------------------------------

    def test_player_the_host_could_not_reach_reloads_when_back(self):
        self.host().event('net:peer-stalled|200|25|3')
        self.host().tick()
        self.peers['200'].local_change('sync:pres|1.0|2.0|3.0|0.5|-0.2|4|Orbit|baut|10.0|5.0|12.0')
        loads = len(self.peers['200'].lua.eval('loads'))
        self.pump(12)
        self.assertTrue(any('Alex war kurz weg' in line for line in self.host().lua.eval('session.View().feed').values()))
        self.assertEqual(len(self.peers['200'].lua.eval('loads')), loads + 1)
        self.assertEqual(self.peers['200'].memory['phase'], 'live')

    def test_joiner_that_lost_its_own_messages_reloads(self):
        alex = self.peers['200']
        alex.event('net:peer-stalled|100|25|2')
        alex.tick()
        loads = len(alex.lua.eval('loads'))
        self.pump(40)                       # the host's roster arrives again
        self.assertEqual(len(alex.lua.eval('loads')), loads + 1)
        self.assertTrue(any('Verbindung war unterbrochen' in t for t in self.toasts('200')))

    def test_silent_host_is_shown_and_cleared(self):
        sam = self.peers['300']
        sam.lua.execute('for i = 1, 700 do session.Tick() end')
        self.assertEqual(sam.lua.eval('session.JoinState()')['phase'], 'silent')
        self.pump(40)
        self.assertEqual(sam.lua.eval('session.JoinState()')['phase'], 'live')
        # The connection pill says both (it turns green when it is back); no toasts.
        self.assertFalse(any('Verbindung zum Host' in t for t in self.toasts('300')), self.toasts('300'))

    def test_rejoin_is_offered_in_the_menu_after_a_crash(self):
        alex = self.peers['200']
        self.assertIn('note-write|pc2coop-lastsession.txt|L1|100|Host', alex.sent_notes)
        menu = base.Peer('200', 'Alex')
        menu.lua.execute('session.SetContext("menu"); session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')
        self.assertIn('note-read|pc2coop-lastsession.txt', menu.commands())
        menu.event('note:data|pc2coop-lastsession.txt|L1|100|Host')
        menu.event('note:end|pc2coop-lastsession.txt')
        menu.tick()
        self.assertIn('friends', menu.commands())
        self.assertIsNone(menu.lua.eval('session.JoinState()'))       # host not seen in PC2 yet
        for event in ('friends:begin|1', 'friend|100|Host|1|1', 'friends:end'):
            menu.event(event)
        menu.tick()
        state = menu.lua.eval('session.JoinState()')
        self.assertEqual((state['phase'], state['host']), ('rejoin', 'Host'))
        menu.lua.execute('session.Rejoin()')
        self.assertIn('join|L1', menu.commands())

    def test_leaving_on_purpose_forgets_the_session(self):
        alex = self.peers['200']
        alex.lua.execute('session.Leave()')
        self.assertIn('note-write|pc2coop-lastsession.txt|', alex.commands())

    def test_returning_player_keeps_their_colour(self):
        colour = {p['name']: p['color'] for p in self.host().lua.eval('session.View().players').values()}['Alex']
        self.host().event('member:leave|200')
        self.pump(2)
        version = self.host().lua.eval('session.VERSION')
        self.host().event(f'msg|200|hello|Alex|-1|live|{version}|1.12.2.1035111')
        self.pump(2)
        back = {p['name']: p['color'] for p in self.host().lua.eval('session.View().players').values()}['Alex']
        self.assertEqual(back, colour)


if __name__ == '__main__':
    unittest.main()
