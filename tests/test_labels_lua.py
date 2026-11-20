"""labels.lua: a player's name tag is only the name in the player's colour (TP-14); other tags
keep their word; nothing in a tag can break the game's STRING_LITERAL form."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/labels.lua'
BULLET = '•'

FAKES = r"""
labels_set = {}
local manager = {
    SetBillboardWidgetData = function(self, kind, positions) labels_count = #positions end,
    SetBillboardWidgetUIInfo = function(self, kind, i, info) labels_set[i] = info.sLabel end,
    ClearBillboardWidgetData = function() labels_count = 0 end}
api = {world = {
    GetActive = function() return 1 end,
    GetScript = function() return {tEnvironment = {RequireInterface = function() return manager end}} end,
    GetWorldAPIs = function() return {billboardwidgets = {WidgetType_CoasterLabels = 7}} end}}
package.preload["Vector3"] = function() return {new = function(self, x, y, z) return {x, y, z} end} end
"""


@unittest.skipIf(LuaRuntime is None, 'lupa missing')
class LabelTextTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.labels = self.lua.execute(SOURCE.read_text(encoding='utf-8'))

    def text(self, **tag):
        table = self.lua.table_from(tag)
        return self.labels._Text(table)

    def test_player_tag_is_name_in_colour(self):
        self.assertEqual(self.text(name='Vici', activity='', color='4dabf7'), BULLET + '#4dabf7 Vici')

    def test_tag_without_colour_keeps_word(self):
        self.assertEqual(self.text(name='Wikingerland', activity='Baugebiet'), BULLET + ' Wikingerland - Baugebiet')
        self.assertEqual(self.text(name='Vici', activity='baut'), BULLET + ' Vici - baut')

    def test_bad_colour_is_ignored(self):
        self.assertEqual(self.text(name='Vici', activity='', color='red; x'), BULLET + ' Vici')

    def test_literal_breakers_are_removed(self):
        self.assertEqual(self.text(name='A|b[c]', activity='', color='ff6b6b'), BULLET + '#ff6b6b Abc')

    def test_show_sets_literal_label(self):
        tags = self.lua.table_from([self.lua.table_from({'key': '1', 'name': 'Vici', 'activity': '', 'color': '51cf66',
                                                         'x': 1, 'y': 2, 'z': 3})])
        self.labels.Show(tags, 0.016)
        self.assertEqual(self.lua.eval('labels_set[1]'), '[STRING_LITERAL:Value=|' + BULLET + '#51cf66 Vici|]')


if __name__ == '__main__':
    unittest.main()
