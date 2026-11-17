"""Optional Lua 5.3 execution checks; these are mocks, not PC2 runtime tests."""
from pathlib import Path
import unittest

try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe' / 'PC2CoopProbe' / 'Main' / 'database' / 'pc2coopprobeluadatabase.lua'


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class ProbeLuaTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            messages = {}
            api = {
                acse = {versionNumber=0.729, tAppendToVersionString={}},
                debug = {Trace=function(s) table.insert(messages,s) end},
                undo = {
                    CommitPreview=function() error("Probe must not commit") end,
                    PreviewChangeList=function() error("Probe must not preview") end
                }
            }
            require=function(name)
                assert(name == "database.pc2coopprobeluadatabase")
                return probe_module
            end
        ''')
        load_module = self.lua.eval('''function(source)
            local chunk, err = load(source, "probe", "t", {_G=_G})
            assert(chunk,err)
            return chunk()
        end''')
        self.module = load_module(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().probe_module = self.module

    def test_registers_only_its_own_module(self):
        content = self.lua.table()
        self.module.AddContentToCall(content)
        self.assertEqual(len(content), 1)
        self.assertTrue(self.lua.eval('function(a,b) return rawequal(a,b) end')(content[1], self.module))

    def test_missing_acse_skips_registration(self):
        self.lua.execute('api.acse=nil')
        content = self.lua.table()
        self.module.AddContentToCall(content)
        self.assertEqual(len(content), 0)

    def test_unsupported_acse_skips_registration(self):
        self.lua.execute('api.acse.versionNumber=0.6')
        content = self.lua.table()
        self.module.AddContentToCall(content)
        self.assertEqual(len(content), 0)

    def test_init_traces_types_and_adds_one_version_marker(self):
        self.module.Init()
        self.module.Init()
        suffixes = self.lua.globals().api.acse.tAppendToVersionString
        self.assertEqual(len(suffixes), 1)
        self.assertTrue(suffixes[1].text.startswith('PC2CoopProbe 1.7.0 Init OK'))
        self.assertIn('P:f C:f O:n', suffixes[1].text)
        messages = tuple(self.lua.globals().messages.values())
        self.assertTrue(any('api.undo.CommitPreview=function' in m for m in messages))
        self.assertTrue(any('world-mutations=0; editor-hooks=registered; save-calls=0' in m for m in messages))

    def test_marker_does_not_require_debug_logger(self):
        self.lua.execute('api.debug=nil')
        self.module.Init()
        self.assertEqual(len(self.lua.globals().api.acse.tAppendToVersionString), 1)

    def test_absent_api_does_not_crash_registration_or_init(self):
        # The module captured api at load time, so load afresh with absent api.
        self.lua.execute('api=nil')
        load_module = self.lua.eval('function(s) return assert(load(s,"probe","t",{_G=_G}))() end')
        module = load_module(SOURCE.read_text(encoding='utf8'))
        content = self.lua.table()
        module.AddContentToCall(content)
        module.Init()
        self.assertEqual(len(content), 0)


if __name__ == '__main__':
    unittest.main()
