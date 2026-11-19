"""figure.lua: the visitor figure from the game's guest models and animations (fake game)."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/figure.lua'

FAKES = r"""
local function vec(x, y, z) return {x = x, y = y, z = z, GetX = function() return x end, GetY = function() return y end,
    GetZ = function() return z end} end
local function quat(x, y, z, w)
    return {x = x, y = y, z = z, w = w, WithX = function(self, v) return quat(v, y, z, w) end,
        WithY = function(self, v) return quat(x, v, z, w) end, WithZ = function(self, v) return quat(x, y, v, w) end,
        WithW = function(self, v) return quat(x, y, z, v) end}
end
package.preload.Vector3 = function() return {new = function(_, x, y, z) return vec(x, y, z) end} end
package.preload.Quaternion = function() return {Identity = quat(0, 0, 0, 1)} end
package.preload.TransformQ = function() return {FromOrPos = function(q, p) return {q = q, p = p} end} end
local function part() return {Components = {Model = {ModelName = {__property = "ModelName"}},
    MaterialCustomisationProvider = {Slot0 = {Colour = {__property = "Slot0_Colour"}}, Slot3 = {Colour = {__property = "Slot3_Colour"}}},
    RenderMaterialEffects = {InstanceData = {ToneSwatchesEntryName = {__property = "SkinActual"}}}},
    Properties = {ModelName = {Default = "", Type = "string"}}} end
PEEP = {Components = {ModelSkeleton = {ModelName = {__property = "SkeletonName"}}, BakedAnimation = {AnimName = {__property = "DefaultAnimName"}},
    BakedAnimTree = {TreeSymbol = {__property = "AnimTreeName"}}, GuestVisual = {}, BakedMotionApplication = {MovingEntity = {__property = "MovingEntity"}},
    AssetPackageLoader = {ManualPackageNames = {"CharacterPatterns"}, PackageNames = {__inheritance = "Append"}}, Transform = {}},
    Children = {Torso = part(), Legs = part(), Head = part(), Hair = part(), SwimBody = part()}}
prefabs, spawned, destroyed, placed, ready = {}, {}, {}, {}, {}
local nextId = 100
api = {entity = {
    FindPrefab = function(name) if name == "peep" then return PEEP end end,
    CompilePrefab = function(t, name) prefabs[name] = t end,
    CreateRequestCompletionToken = function() return {} end,
    InstantiatePrefab = function(name, _, token, tr) nextId = nextId + 1; spawned[nextId] = name; return nextId end,
    DestroyEntity = function(e) destroyed[#destroyed+1] = e end},
  transform = {HasTransform = function(e) return ready[e] == true end,
    SetTransform = function(e, t) placed[e] = t end}}
function readyAll() for e in pairs(spawned) do ready[e] = true end end
function shownState(fig) return fig:Shown() end
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class FigureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.lua.globals().Figure = self.lua.eval('function(s) return assert(load(s, "figure", "t", _G))() end')(
            SOURCE.read_text(encoding='utf8'))

    def test_look_text_round_trips_and_strange_text_is_refused(self):
        text = 'af.2.4.3.2.1a334d-ffffff-000000-ffffff.333333-000000.804d1a'
        self.assertEqual(self.lua.eval(f'Figure.LookText(Figure.ParseLook("{text}"))'), text)
        self.assertEqual(self.lua.eval('Figure.LookText(Figure.ParseLook("am.1.1.1.1.x.x.x"))'), 'am.1.1.1.1.x.x.x')
        for bad in ('zz.1.1.1.1.x.x.x', 'am.9.1.1.1.x.x.x', 'am.0.1.1.1.x.x.x', 'am.1.1.1.1.x.x', 'am.1.1.1.1.ff.x.x',
                    'am.1.1.1.1.x.x.x|send', 'am.1.1.1.1.x.x.gggggg', 'am.1.5.1.1.x.x.x' + 'x' * 80, ''):
            self.assertIsNone(self.lua.eval(f'Figure.ParseLook("{bad}")'), bad)
        self.assertIsNone(self.lua.eval('Figure.ParseLook(nil)'))

    def test_the_frontier_avatar_gives_group_models_and_colours(self):
        text = self.lua.eval('''Figure.LookText(Figure.FromAvatar({group = "AFA", parts = {
            Bodies = {model = 7, custom = {colours = {{0.1, 0.2, 0.3}, {1, 1, 1}, {0, 0, 0}, {1, 1, 1}}}},
            Legs = {model = 3, custom = {colours = {{0.2, 0.2, 0.2}, {0, 0, 0}}}},
            Heads = {model = 2}, Hair = {model = 5, custom = {colours = {{0.5, 0.3, 0.1}}}}}}))''')
        self.assertEqual(text, 'af.2.4.3.2.1a334d-ffffff-000000-ffffff.333333-000000.804d1a')
        # An unknown group becomes an adult man; missing colours are the player's colour.
        self.assertEqual(self.lua.eval('Figure.LookText(Figure.FromAvatar({group = "XYZ", parts = {}}))'), 'am.1.1.1.1.x.x.x')
        self.assertIsNone(self.lua.eval('Figure.FromAvatar(nil)'))
        # Without a readable avatar: the default look.
        self.assertEqual(self.lua.eval('Figure.LookText(Figure.OwnLook())'), 'am.1.1.1.1.x.x.x')

    def test_prefab_is_the_guest_without_guest_logic_with_fixed_models(self):
        self.assertTrue(self.lua.eval('Figure.Available()'))
        self.lua.execute('fig = Figure.New(Figure.ParseLook("af.2.4.3.2.x.x.x"), "ff0000"); fig:Place(1, 2, 3, 0, "walk")')
        names = list(self.lua.eval('prefabs').keys())
        self.assertEqual(len(names), 1)
        self.assertTrue(names[0].endswith('_walkbase'), names[0])
        root = self.lua.eval(f'prefabs["{names[0]}"]')
        comps = root['Components']
        for gone in ('GuestVisual', 'BakedMotionApplication', 'BakedAnimTree'):
            self.assertIsNone(comps[gone], gone)
        self.assertEqual(comps['ModelSkeleton']['ModelName'], 'af_skeleton')
        self.assertEqual(comps['BakedAnimation']['AnimName'], 'af$walkbase')
        self.assertIsNone(comps['AssetPackageLoader']['PackageNames']['__inheritance'])
        children = root['Children']
        self.assertEqual(children['Torso']['Components']['Model']['ModelName'], 'af_body02')
        self.assertEqual(children['Legs']['Components']['Model']['ModelName'], 'af_legs12')
        self.assertEqual(children['Head']['Components']['Model']['ModelName'], 'af_head03')
        self.assertEqual(children['Hair']['Components']['Model']['ModelName'], 'af_hair02')
        self.assertIsNone(children['SwimBody'])
        # The player's colour on the top; optional properties nobody set stay out.
        self.assertAlmostEqual(children['Torso']['Components']['MaterialCustomisationProvider']['Slot0']['Colour'].x, 1.0)
        self.assertIsNone(children['Torso']['Components']['RenderMaterialEffects']['InstanceData']['ToneSwatchesEntryName'])

    def test_one_entity_per_animation_shown_one_at_a_time(self):
        self.lua.execute('fig = Figure.New(Figure.DefaultLook(), "00ff00"); fig:Warm()')
        self.assertEqual(len(list(self.lua.eval('spawned').keys())), 3)      # stand, walk, run built up front
        self.assertFalse(self.lua.eval('fig:Place(5, 1, 7, 0, "walk")'))   # nothing loaded yet
        self.lua.execute('readyAll()')
        self.assertTrue(self.lua.eval('fig:Place(5, 1, 7, 0, "walk")'))
        self.assertEqual(self.lua.eval('fig:Shown()'), 'walk')
        self.lua.execute('fig:Place(6, 1, 7, 0, "idle")')
        self.assertEqual(self.lua.eval('fig:Shown()'), 'idle')
        walk = self.lua.eval('fig.ents.walk.entity')
        self.assertEqual(self.lua.eval(f'placed[{walk}].p.y'), -500)   # waits under the ground
        idle = self.lua.eval('fig.ents.idle.entity')
        self.assertEqual(self.lua.eval(f'placed[{idle}].p.x'), 6)
        # An emote is built when needed; until it is there, the figure keeps standing.
        self.lua.execute('fig:Place(6, 1, 7, 0, "cheer")')
        self.assertEqual(self.lua.eval('fig:Shown()'), 'idle')
        self.lua.execute('readyAll(); fig:Place(6, 1, 7, 0, "cheer")')
        self.assertEqual(self.lua.eval('fig:Shown()'), 'cheer')
        cheer = self.lua.eval('fig.ents.cheer.entity')
        self.lua.execute('fig:Place(6, 1, 7, 0, "laugh")')   # only one emote at a time
        self.assertIn(cheer, list(self.lua.eval('destroyed').values()))
        self.assertTrue(self.lua.eval(f'fig:Owns({idle})'))
        self.assertFalse(self.lua.eval('fig:Owns(1)'))
        self.lua.execute('fig:Destroy()')
        self.assertIn(idle, list(self.lua.eval('destroyed').values()))
        self.assertFalse(self.lua.eval(f'fig:Owns({idle})'))

    def test_unknown_state_stands_and_children_wave_with_a_cheer(self):
        self.lua.execute('readyAll(); fig = Figure.New(Figure.ParseLook("cm.1.1.1.1.x.x.x")); fig:Place(0, 0, 0, 0, "dance")')
        self.assertEqual(self.lua.eval('fig:Shown()'), None)
        self.lua.execute('readyAll(); fig:Place(0, 0, 0, 0, "dance")')
        self.assertEqual(self.lua.eval('fig:Shown()'), 'idle')
        self.lua.execute('fig:Place(0, 0, 0, 0, "wave"); readyAll(); fig:Place(0, 0, 0, 0, "wave")')
        names = ' '.join(self.lua.eval('prefabs').keys())
        self.assertIn('_standreactcheer', names)     # no waving animation for boys in the base game
        self.assertNotIn('standwaveflag', names)

    def test_without_the_ace_prefab_functions_there_is_no_figure(self):
        self.lua.execute('api.entity.CompilePrefab = nil; Figure._Reset()')
        self.assertFalse(self.lua.eval('Figure.Available()'))

    def test_gait_from_speed(self):
        self.assertEqual(self.lua.eval('Figure.Gait(0.2)'), 'idle')
        self.assertEqual(self.lua.eval('Figure.Gait(3.2)'), 'walk')
        self.assertEqual(self.lua.eval('Figure.Gait(7.5)'), 'run')


if __name__ == '__main__':
    unittest.main()
