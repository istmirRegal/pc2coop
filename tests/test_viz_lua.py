"""viz.lua: marks never cover anything of the park (P6 A9, second round).

A mark on an object outlines that object (the game's highlight, blinking), nothing is drawn
over it; a mark on the ground and a build area are a ring of small dots around the spot with
the middle free. The game's entity, transform and highlight calls are faked.
"""
from pathlib import Path
import math
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

MAIN = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop'

FAKES = r"""
spawned, positions, scales, lit, refuse = {}, {}, {}, {}, false
local nextEntity = 1000
local V = {}
V.__index = V
function V:new(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end
function V:GetX() return self.x end
function V:GetY() return self.y end
function V:GetZ() return self.z end
package.preload["Vector3"] = function() return V end
package.preload["Quaternion"] = function() return {Identity = {}} end
package.preload["TransformQ"] = function() return {FromOrPos = function(q, p) return p end} end
package.preload["pc2coop.world"] = function() return {Camera = function() return 0, 50, 0 end} end
api = {
    entity = {
        CreateRequestCompletionToken = function() return {} end,
        HaveRequestsCompleted = function() return true end,
        InstantiatePrefab = function(prefab)
            if refuse then return nil end
            nextEntity = nextEntity + 1; spawned[nextEntity] = prefab; return nextEntity end,
        DestroyEntity = function(e) spawned[e] = nil; positions[e] = nil end,
        FindPrefab = function() return nil end},
    transform = {
        HasTransform = function() return true end,
        SetScale = function(e, s) scales[e] = s end,
        SetPosition = function(e, p) positions[e] = {p.x, p.y, p.z} end,
        SetTransform = function(e, p) positions[e] = {p.x, p.y, p.z} end},
    model = {
        HighlightDefault = 0,
        SetHighlighted = function(e, channel, on) lit[e] = on end,
        SetHighlightBehaviour = function() end,
        SetHighlightEdgeColour = function() end,
        SetHighlightFillColour = function() end},
    world = {GetWorldAPIs = function() return {voxelterrain = {
        GetPrimaryVoxelTerrainEntityID = function() return 1 end,
        RayCast = function(self, id, from, dir, length) return 80 end}} end},
    ui2 = {},
}
function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class MarkTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        for name in ('shared', 'viz'):
            source = (MAIN / (name + '.lua')).read_text(encoding='utf8')
            self.lua.eval('function(n, s) package.preload["pc2coop." .. n] = function() return assert(load(s, n, "t", _G))() end end')(name, source)
        self.lua.execute('viz = require("pc2coop.viz"); viz.Init(function(m) last = m end)')

    def frames(self, n, pings, locked='{}'):
        self.lua.execute(f'for i = 1, {n} do viz.Update({{}}, {locked}, "ff922b", 1 / 60, {pings}) end')

    def dots(self):
        return [tuple(p.values()) for e, p in self.lua.eval('positions').items()]

    def test_a_mark_on_an_object_blinks_its_outline_and_draws_nothing(self):
        mark = '{{sid = "200", x = 5, y = 0, z = 5, age = 0.1, entity = 77}}'
        states = set()
        for _ in range(40):
            self.frames(1, mark)
            states.add(self.lua.eval('lit[77]'))
        self.assertEqual(states, {True, False})                       # it blinks
        self.assertEqual(self.lua.eval('count(spawned)'), 0)          # nothing over the park
        self.frames(1, '{}')                                          # the mark is over
        self.assertFalse(self.lua.eval('lit[77]'))
        self.assertIsNone(self.lua.eval('last'))                      # no viz error

    def test_a_locked_object_keeps_its_tint_after_a_mark(self):
        self.frames(40, '{{sid = "200", x = 5, y = 0, z = 5, age = 0.1, entity = 77}}', '{[77] = true}')
        self.frames(1, '{}', '{[77] = true}')
        self.assertTrue(self.lua.eval('lit[77]'))

    def test_a_mark_on_the_ground_is_a_ring_of_small_dots_around_the_spot(self):
        self.frames(3, '{{sid = "200", x = 10, y = 0, z = 0, age = 0.1}}')
        dots = self.dots()
        self.assertEqual(len(dots), 10)
        distances = [math.hypot(x - 10, z) for x, y, z in dots]
        self.assertTrue(min(distances) > 0.5, distances)              # the middle stays free
        self.assertTrue(max(distances) - min(distances) < 0.01)       # one circle
        self.assertTrue(all(abs(y - 0.06) < 0.01 for _, y, _ in dots))  # flat on the ground
        self.assertTrue(max(self.lua.eval('scales').values()) < 0.6)   # small dots

    def test_a_build_area_is_a_still_dotted_ring_of_its_size(self):
        self.frames(3, '{{sid = "board:b1", x = 0, y = 0, z = 0, age = 0, radius = 20}}')
        dots = self.dots()
        self.assertEqual(len(dots), 24)                               # 20 m * 1.2
        self.assertTrue(all(abs(math.hypot(x, z) - 20) < 0.01 for x, _, z in dots))
        before = sorted(dots)
        self.frames(30, '{{sid = "board:b1", x = 0, y = 0, z = 0, age = 0, radius = 20}}')
        self.assertEqual(sorted(self.dots()), before)                 # it does not turn

    def test_no_entities_from_the_game_means_no_dots_and_no_hang(self):
        self.lua.execute('refuse = true')
        self.frames(5, '{{sid = "200", x = 10, y = 0, z = 0, age = 0.1}}')
        self.assertEqual(self.lua.eval('count(spawned)'), 0)
        self.assertIsNone(self.lua.eval('last'))

    def test_marks_going_away_leave_no_entities(self):
        self.frames(3, '{{sid = "200", x = 10, y = 0, z = 0, age = 0.1}, {sid = "board:b1", x = 0, y = 0, z = 0, age = 0, radius = 10}}')
        self.assertGreater(self.lua.eval('count(spawned)'), 0)
        self.frames(1, '{}')
        self.assertEqual(self.lua.eval('count(spawned)'), 0)


if __name__ == '__main__':
    unittest.main()
