"""Who may join and what a joiner accepts: the host's consent, Steam friendship, a lobby
that came with the game's start, matching versions, and text from other players."""
import unittest

import test_session_lua as base


@unittest.skipIf(base.LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class JoinSecurityTests(unittest.TestCase):
    setUp = base.SessionTests.setUp
    lobby_enter = base.SessionTests.lobby_enter
    pump = base.SessionTests.pump

    def host(self):
        return self.peers['100']

    def join_state(self, peer):
        state = peer.lua.eval('session.JoinState()')
        return dict(state.items()) if state is not None else None

    def requests(self):
        return [(r['sid'], r['name']) for r in self.host().lua.eval('session.Requests()').values()]

    def feed(self):
        return list(self.host().lua.eval('session.View().feed').values())

    def new_peer(self, sid, name, friend='1'):
        peer = self.peers[sid] = base.Peer(sid, name)
        peer.event(f'lobby:entered|L1|100|Host|{friend}')
        self.host().event(f'member:join|{sid}|{name}')
        return peer

    def test_friend_without_invitation_waits_for_the_hosts_ok(self):
        self.host().lua.execute('session.SetAskBeforeJoin(true)')
        self.host().sent_files.clear()
        guest = self.new_peer('900', 'Neu')
        self.pump(8)
        self.assertEqual(self.requests(), [('900', 'Neu')])
        self.assertEqual(self.host().sent_files, [])                    # no park yet
        self.assertEqual(self.join_state(guest)['phase'], 'asking')
        self.host().lua.execute('session.Answer("900", true)')
        self.pump(12)
        self.assertEqual(self.requests(), [])
        self.assertEqual(self.join_state(guest)['phase'], 'live')
        self.assertIn('Neu ist beigetreten', self.feed())

    def test_host_can_turn_a_friend_away(self):
        self.host().lua.execute('session.SetAskBeforeJoin(true)')
        self.host().sent_files.clear()
        guest = self.new_peer('900', 'Neu')
        self.pump(8)
        self.host().lua.execute('session.Answer("900", false)')
        self.pump(8)
        state = self.join_state(guest)
        self.assertEqual(state['phase'], 'failed')
        self.assertIn('abgelehnt', state['reason'])
        self.assertIsNone(guest.lua.eval('session.View().role'))
        self.assertEqual(self.host().sent_files, [])
        self.assertIn('Neu wurde nicht zugelassen', self.feed())

    def test_invited_friend_walks_in(self):
        self.host().lua.execute('session.SetAskBeforeJoin(true)')
        self.host().event('invite:sent|901')
        guest = self.new_peer('901', 'Geladen')
        self.pump(12)
        self.assertEqual(self.requests(), [])
        self.assertEqual(self.join_state(guest)['phase'], 'live')

    def test_host_who_is_not_a_steam_friend_is_not_joined(self):
        guest = base.Peer('910', 'Fremd')
        guest.event('invite:accepted|L1|0|launch')
        guest.event('lobby:entered|L1|100|Host|0')
        guest.tick()
        commands = guest.commands()
        self.assertIn('leave', commands)
        self.assertFalse(any(c.startswith('send|') for c in commands), commands)
        state = self.join_state(guest)
        self.assertEqual(state['phase'], 'failed')
        self.assertIn('Steam-Freundesliste', state['reason'])

    def test_lobby_from_the_games_start_needs_the_players_ok(self):
        guest = self.peers['920'] = base.Peer('920', 'Start')
        guest.event('invite:accepted|L1|0|launch')
        guest.event('lobby:entered|L1|100|Host|1')
        self.host().event('member:join|920|Start')
        guest.tick()
        self.assertFalse(any(c.startswith('send|') for c in guest.commands()))
        state = self.join_state(guest)
        self.assertEqual((state['phase'], state['host']), ('confirm', 'Host'))
        guest.lua.execute('session.ConfirmJoin()')
        self.pump(12)
        self.assertEqual(self.join_state(guest)['phase'], 'live')

    def test_declining_that_lobby_leaves_it(self):
        guest = base.Peer('921', 'Start')
        guest.event('invite:accepted|L1|0|launch')
        guest.event('lobby:entered|L1|100|Host|1')
        guest.tick()
        guest.commands()
        guest.lua.execute('session.DismissJoin()')
        self.assertIn('leave', guest.commands())
        self.assertIsNone(self.join_state(guest))

    def test_invitation_clicked_in_steam_needs_no_second_question(self):
        guest = self.peers['930'] = base.Peer('930', 'Klick')
        guest.event('invite:accepted|L1|100|Host')
        guest.event('lobby:entered|L1|100|Host|1')
        self.host().event('member:join|930|Klick')
        self.pump(12)
        self.assertEqual(self.join_state(guest)['phase'], 'live')

    def test_players_with_another_game_version_do_not_mix(self):
        guest = self.peers['940'] = base.Peer('940', 'Alt')
        guest.lua.execute('fakeGameVersion = "1.13.0.1"; session.Init(function(m) logs[#logs+1] = m end, net, sync, manager)')
        guest.commands()
        guest.event('lobby:entered|L1|100|Host|1')
        self.host().event('member:join|940|Alt')
        self.pump(8)
        self.assertTrue(any('Alt hat Spielversion 1.13.0.1' in line for line in self.feed()), self.feed())
        state = self.join_state(guest)
        self.assertEqual(state['phase'], 'failed')
        self.assertIn('Spielversion 1.12.2.1035111', state['reason'])
        self.assertNotIn('Alt', [p['name'] for p in self.host().lua.eval('session.View().players').values()])

    def test_only_park_notifications_are_marked_for_translation(self):
        self.peers['200'].lua.execute('session.SendChat("[Notification_RideBroken]")')
        self.host().lua.eval('function(t) session._ParkNote(t) end')('[Notification_RideNoPower:Name=|Teacups 1|]')
        self.pump(4)
        toasts = {t['text']: t['loc'] for t in self.peers['300'].lua.eval('session.Toasts()').values()}
        self.assertTrue(toasts['[Notification_RideNoPower:Name=|Teacups 1|]'])
        chat = [text for text in toasts if text.startswith('Alex: ')]
        self.assertEqual(len(chat), 1)
        self.assertFalse(toasts[chat[0]])

    def test_temporary_park_files_are_removed(self):
        guest = self.new_peer('950', 'Kurz')
        self.pump(12)
        self.assertEqual(sorted(guest.deleted), ['pc2coop-join.bin', 'pc2coop-join.trn'])
        self.host().event('member:leave|950')
        self.pump(4)
        self.assertIn('pc2coop-host-950.bin', self.host().deleted)
        self.assertIn('pc2coop-host-950.trn', self.host().deleted)


if __name__ == '__main__':
    unittest.main()
