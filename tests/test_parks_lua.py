"""parks.lua: the host's saved parks and new parks for the lobby, against a fake game API."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/parks.lua'

FAKES = r"""
saves = {
    {token = "t1", mode = "sandbox", name = "Alt", world = "Taiga"},
    {token = "t2", mode = "challenge", name = "Challenge", world = "Temperate"},
    {token = "t3", mode = "sandbox", name = "Neu|Park;1", world = "Tropical"},
}
api = {save = {
    GetExistingSaves_SortOldestFirst = "oldest",
    GetSaveMetadata = function(token)
        for _, s in ipairs(saves) do if s.token == token then return {tSave = {sGameMode = s.mode, sWorldName = s.world}} end end
    end,
    GetSaveCustomName = function(token)
        for _, s in ipairs(saves) do if s.token == token then return s.name end end
    end}}
loaded, created = {}, {}
manager = {}
function manager:EnumerateParkSaves(order, kind)
    assert(order == "oldest" and kind == "park2")
    local out = {}
    for i, s in ipairs(saves) do out[i] = s.token end
    return true, out
end
function manager:LoadParkFromSaveToken(token) loaded[#loaded+1] = token; return true end
menu = {}
function menu:OnSandboxConfirmNewParkSetup(preset, biome, difficulty, scenario)
    created[#created+1] = {preset = preset, biome = biome, name = self.sNewParkName}
    return true
end
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class ParksTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.parks = self.lua.eval('function(s) return assert(load(s, "parks", "t", _G))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().parks = self.parks

    def test_lists_sandbox_saves_newest_first_with_clean_names(self):
        listed = [dict(p.items()) for p in self.lua.eval('parks.List(manager)').values()]
        self.assertEqual([(p['id'], p['name'], p['world']) for p in listed], [('1', 'Neu Park 1', 'Tropical'), ('2', 'Alt', 'Taiga')])

    def test_loads_the_listed_save_only(self):
        self.lua.execute('parks.List(manager)')
        self.assertTrue(self.lua.eval('parks.Load(manager, "2")'))
        self.assertEqual(list(self.lua.eval('loaded').values()), ['t1'])
        ok, failure = self.lua.eval('parks.Load(manager, "99")')
        self.assertFalse(ok)

    def test_new_park_uses_the_game_presets_and_known_biomes(self):
        self.assertTrue(self.lua.eval('parks.New(menu, "Taiga", true, "Unser Park")'))
        self.assertTrue(self.lua.eval('parks.New(menu, "Tropical", false, "")'))
        ok, failure = self.lua.eval('parks.New(menu, "Moon", true, "x")')
        self.assertFalse(ok)
        made = [dict(c.items()) for c in self.lua.eval('created').values()]
        self.assertEqual([(c['preset'], c['biome'], c['name']) for c in made], [(1, 'Taiga', 'Unser Park'), (0, 'Tropical', 'PC2Coop Park')])

    def test_failing_game_calls_do_not_raise(self):
        self.lua.execute('function manager:EnumerateParkSaves() error("boom") end')
        self.assertEqual(len(self.lua.eval('parks.List(manager)')), 0)
        self.assertEqual(len(self.lua.eval('parks.List(nil)')), 0)


if __name__ == '__main__':
    unittest.main()
