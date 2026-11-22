"""Diagnosis (FEAT-222, FEAT-223): errors with their stack, written sparingly; snapshots, the
recent network events, the session code and the problem report command."""
from pathlib import Path
import unittest

try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

from test_session_lua import Peer

GUARD = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/guard.lua'


@unittest.skipIf(LuaRuntime is None, 'lupa missing')
class GuardTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.guard = self.lua.eval('function(s) return assert(load(s, "guard", "t", _G))() end')(GUARD.read_text(encoding='utf8'))
        self.lua.globals().guard = self.guard
        self.lua.execute('lines, firsts = {}, {}; guard.Init(function(l) lines[#lines+1] = l end, function(w) firsts[#firsts+1] = w end)')

    def lines(self):
        return list(self.lua.eval('lines').values())

    def test_error_is_written_with_its_stack_and_the_game_goes_on(self):
        ok, value = self.lua.execute('''
            local function inner() error("boom") end
            return guard.Call("session.tick", function() inner() end)''')
        self.assertFalse(ok)
        (line,) = self.lines()
        self.assertTrue(line.startswith('error|session.tick|x1|'), line)
        self.assertIn('boom', line)
        self.assertIn('stack traceback', line)
        self.assertIn('inner', line)

    def test_results_pass_through(self):
        self.assertEqual(self.lua.execute('return guard.Call("x", function(a, b) return a + b, "ok" end, 2, 3)'), (True, 5, 'ok'))
        self.assertEqual(self.lines(), [])

    def test_a_repeating_error_is_written_at_1_10_100_and_1000(self):
        self.lua.execute('for i = 1, 2000 do guard.Call("ui.tick", function() error("same") end) end')
        counts = [line.split('|')[2] for line in self.lines()]
        self.assertEqual(counts, ['x1', 'x10', 'x100', 'x1000', 'x2000'])
        self.assertEqual(self.lua.eval('guard.Count()'), 2000)
        self.assertEqual(list(self.lua.eval('firsts').values()), ['ui.tick'], 'the first error dumps the recent events once')

    def test_at_most_100_kinds(self):
        self.lua.execute('for i = 1, 150 do guard.Call("k", function() error("kind " .. i) end) end')
        self.assertEqual(len(self.lines()), 100)
        self.assertLessEqual(len(self.lua.eval('guard.Recent()')), 20)


@unittest.skipIf(LuaRuntime is None, 'lupa missing')
class SessionDiagnosisTests(unittest.TestCase):
    def setUp(self):
        self.host = Peer('76561190000000100', 'Host')
        self.host.lua.execute('session.Host()')
        self.host.commands()
        self.host.event('lobby:entered|109775240000000001|76561190000000100|Host|1')
        self.host.tick()

    def logs(self, peer):
        return list(peer.lua.eval('logs').values())

    def test_session_code_is_the_same_for_everyone_in_a_lobby(self):
        guest = Peer('76561190000000200', 'Vici')
        guest.event('lobby:entered|109775240000000001|76561190000000100|Host|1')
        guest.tick()
        codes = [[l for l in self.logs(p) if l.startswith('session:code|')] for p in (self.host, guest)]
        self.assertEqual(codes[0], codes[1])
        self.assertRegex(codes[0][0], r'^session:code\|[A-Z2-9]{6}$')
        self.assertNotIn('109775240000000001', codes[0][0])

    def test_snapshot_every_30_seconds_in_a_session(self):
        for _ in range(1800):
            self.host.tick()
        snaps = [l for l in self.logs(self.host) if l.startswith('session:snap|')]
        self.assertEqual(len(snaps), 1)
        self.assertIn('role=host', snaps[0])
        self.assertIn('players=1', snaps[0])
        self.assertIn('faults=0', snaps[0])

    def test_recent_events_are_kept_and_runs_counted(self):
        for _ in range(5):
            self.host.event('msg|76561190000000200|pres|1|2|3')
        self.host.event('msg|76561190000000200|chat|hi')
        self.host.tick()
        self.host.lua.execute('session._DumpRing("test")')
        (line,) = [l for l in self.logs(self.host) if l.startswith('session:recent|test|')]
        self.assertRegex(line, r'msg:pres@\d+:\d+x5')
        self.assertIn('msg:chat@', line)
        self.assertNotIn('hi', line.split('|', 2)[2], 'only kinds and sizes, never content')

    def test_report_command_names_everyone_and_waits_for_the_answer(self):
        self.host.lua.execute('session.Report()')
        (command,) = [c for c in self.host.commands() if c.startswith('report|')]
        fields = command.split('|')
        self.assertEqual(fields[:4], ['report', 'de', '', self.host.lua.eval('session.VERSION')])
        self.assertEqual(fields[4], '76561190000000100=Host')
        self.assertEqual(self.host.lua.eval('session.ReportState().state'), 'busy')
        self.host.event('report:done|PC2Coop-Bericht-2026-11-22-1403.txt')
        self.host.tick()
        state = self.host.lua.eval('session.ReportState()')
        self.assertEqual((state.state, state.file), ('done', 'PC2Coop-Bericht-2026-11-22-1403.txt'))
        self.assertTrue(any(l.startswith('session:recent|report|') for l in self.logs(self.host)))

    def test_report_error_and_timeout(self):
        self.host.lua.execute('session.Report()')
        self.host.event('report:error|desktop')
        self.host.tick()
        self.assertEqual(self.host.lua.eval('session.ReportState().reason'), 'Der Desktop-Ordner wurde nicht gefunden.')
        self.host.lua.execute('session.Report()')
        for _ in range(902):
            self.host.tick()
        self.assertEqual(self.host.lua.eval('session.ReportState().reason'), 'Keine Antwort von der Mod-DLL.')

    def test_an_error_in_a_handler_is_caught_with_its_place(self):
        self.host.lua.execute('local real = session._ReportResult; session._ReportResult = function() error("broken handler") end; session._real = real')
        self.host.event('report:done|x.txt')
        self.host.tick()
        self.host.lua.execute('session._ReportResult = session._real')
        errors = [l for l in self.logs(self.host) if l.startswith('error|session.net|x1|')]
        self.assertEqual(len(errors), 1)
        self.assertIn('broken handler', errors[0])
        self.assertTrue(any(l.startswith('session:recent|first-error|') for l in self.logs(self.host)))
        self.host.tick()   # the session goes on


if __name__ == '__main__':
    unittest.main()
