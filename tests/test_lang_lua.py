"""lang.lua: the language of the labels Lua draws at objects in the world (ADR-022)."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

MAIN = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop'


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class LangTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('api = {ui2 = {}}')
        for name in ('shared', 'lang'):
            source = (MAIN / (name + '.lua')).read_text(encoding='utf8')
            self.lua.eval('function(n, s) package.preload["pc2coop." .. n] = function() return assert(load(s, n, "t", _G))() end end')(name, source)
        self.lang = self.lua.eval('require("pc2coop.lang")')

    def test_german_until_the_layer_says_otherwise(self):
        self.assertEqual(self.lang.Code(), 'de')
        self.assertEqual(self.lang.World('Erstellt von Vici'), 'Erstellt von Vici')
        self.lang.Set('xx')
        self.assertEqual(self.lang.Code(), 'de')

    def test_english_labels_keep_the_names(self):
        self.lang.Set('en')
        cases = {
            'Erstellt von Vici, zuletzt Sam': 'Built by Vici, last edited by Sam',
            'Erstellt von Vici': 'Built by Vici',
            'Zuletzt bearbeitet von Sam 100%': 'Last edited by Sam 100%',
            'Vici baut hier gerade': 'Vici is building here',
            'Ein Mitspieler baut hier gerade': 'A player is building here',
            'Host war schneller': 'Host was faster',
            'Sam hat das gerade geändert': 'Sam just changed this',
            'Vici': 'Vici',
        }
        for german, english in cases.items():
            self.assertEqual(self.lang.World(german), english)

    def test_the_language_is_shared_between_module_instances(self):
        # The main menu loads a module anew on every require; the code lives in the shared table.
        self.lang.Set('en')
        again = self.lua.eval('package.preload["pc2coop.lang"]()')
        self.assertEqual(again.Code(), 'en')


if __name__ == '__main__':
    unittest.main()
