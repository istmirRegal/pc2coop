"""visitor.lua: walking as a guest and riding along with the game's cameras (fake game)."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/visitor.lua'

FAKES = r"""
local function vec(x, y, z)
    return {GetX = function() return x end, GetY = function() return y end, GetZ = function() return z end,
        WithY = function(self, ny) return vec(x, ny, z) end}
end
cam = {mode = "StandardOrbit", requests = {}, pos = vec(10, 3.65, 20)}
function cam:GetCurrentModeName() return self.mode end
function cam:RequestMode(name, init) self.requests[#self.requests+1] = name; self.mode = name end
function cam:RequestDefaultMode() self.requests[#self.requests+1] = "default"; self.mode = "StandardOrbit" end
function cam:GetPosYPRZoom() return self.pos end
ui = {mode = "Select"}
rides = {[1] = {name = "Conlan", x = 100, z = 20, info = {type = "tracked", isCoaster = true, numTrains = 2}, stats = {QueueLength = 12}},
         [2] = {name = "Teetassen", x = 15, z = 20, info = {type = "flat"}, stats = {Excitement = 2.5, Fear = 0.4, Nausea = 1.1}}}
local ridesAPI = {}
function ridesAPI:GetRideInfo(r) return rides[r].info end
function ridesAPI:GetRideName(r) return rides[r].name end
function ridesAPI:GetStationsForRide(r) return {r + 100} end
apis = {CameraModeManager = cam,
    UIModeHelperComponent = {GetCurrentModeName = function() return ui.mode end},
    ridestation = {GetAllStations = function() return {101, 102} end, GetRideEntityIDFromStationEntityID = function(_, s) return s - 100 end},
    rides = ridesAPI,
    ridestats = {GetStationStatsLastOnly = function(_, s) return rides[s - 100].stats end}}
api = {world = {GetWorldAPIs = function() return apis end},
    transform = {CalculateWorldTransform = function(e) local r = rides[e]; return {GetPos = function() return vec(r.x, 0, r.z) end} end}}
package.preload["Editors.Shared.BaseUIMode"] = function() return {GetModeHelperEntity = function() return 1 end,
    SetNewMode = function(name) ui.mode = name end} end
package.preload["Editors.Gameface.GamefaceBaseUIMode"] = function() return {SetNewMode = function(name, ride, kind)
    ui.mode = name; ui.ride = ride; ui.kind = kind; cam.mode = "FirstPersonRide" end} end
function keyOf(e) return "F" .. rides[e].x .. "_0_" .. rides[e].z end
function findRide(key) for e in pairs(rides) do if keyOf(e) == key then return e end end end
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class VisitorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.v = self.lua.eval('function(s) return assert(load(s, "visitor", "t", _G))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().V = self.v

    def tick(self, n):
        self.lua.execute(f'for i = 1, {n} do V.Tick() end')

    def test_walk_shows_up_for_the_others_at_the_feet(self):
        self.assertIsNone(self.v.Activity())
        self.v.Start()
        self.assertEqual(self.lua.eval('cam.mode'), 'Walking')
        self.assertEqual(self.v.Activity(), 'geht als Besucher durch den Park')
        self.assertAlmostEqual(self.v.Feet().GetY(), 2.0)
        self.v.Stop()
        self.assertEqual(self.lua.eval('cam.mode'), 'StandardOrbit')
        self.assertIsNone(self.v.Activity())

    def test_leaving_the_walk_with_game_keys_ends_visitor_mode(self):
        self.v.Start()
        self.tick(30)
        self.assertTrue(self.v.Active(), 'not right after the start')
        self.lua.execute('cam.mode = "StandardOrbit"')
        self.tick(90)
        self.assertFalse(self.v.Active())

    def test_ride_along_then_walk_on(self):
        self.v.Start()
        self.assertTrue(self.v.Ride('F100_0_20', self.lua.globals().findRide))
        self.assertEqual((self.lua.eval('ui.mode'), self.lua.eval('ui.kind')), ('GamefaceCameraSettings', 'TrackedRide'))
        self.assertEqual(self.v.Activity(), 'faehrt Conlan')
        self.assertIsNone(self.v.Feet(), 'on a ride the camera is in the car')
        self.tick(120)
        self.assertTrue(self.v.Riding())
        self.lua.execute('ui.mode = "Select"; cam.mode = "StandardOrbit"')   # ride camera closed
        self.tick(30)
        self.assertFalse(self.v.Riding())
        self.assertEqual(self.lua.eval('cam.mode'), 'Walking')
        self.assertTrue(self.v.Active())
        ok, failure = self.v.Ride('F9_9_9', self.lua.globals().findRide)
        self.assertFalse(ok)

    def test_guest_view_then_walk_on(self):
        self.v.Start()
        self.v.WatchGuest()
        self.assertEqual(self.lua.eval('ui.mode'), 'VisitorCamera')
        self.assertEqual(self.v.Activity(), 'geht als Besucher in Ich-Sicht durch den Park')
        self.assertIsNotNone(self.v.Feet())   # the others see a figure at the camera
        self.tick(90)
        self.assertTrue(self.v.GuestView())
        self.lua.execute('ui.mode = "Select"; cam.mode = "StandardOrbit"')
        self.tick(30)
        self.assertFalse(self.v.GuestView())
        self.assertEqual(self.lua.eval('cam.mode'), 'Walking')

    def test_rides_nearest_first_with_stats(self):
        rides = [dict(r.items()) for r in self.v.Rides(self.lua.globals().keyOf).values()]
        self.assertEqual([(r['name'], r['kind'], r['dist']) for r in rides], [('Teetassen', 'Fahrgeschaeft', 5), ('Conlan', 'Achterbahn', 90)])
        self.assertEqual((rides[0]['e'], rides[0]['n']), (2.5, 1.1))
        self.assertIsNone(rides[1].get('e'), 'untested ride: no excitement yet')
        self.assertEqual((rides[1]['queue'], rides[1]['trains']), (12, 2))


THIRD = r"""
-- Third person: placement focus, ground, physics walls, input, avatar camera.
local function vec(x, y, z)
    return {GetX = function() return x end, GetY = function() return y end, GetZ = function() return z end,
        WithY = function(self, ny) return vec(x, ny, z) end}
end
package.preload.Vector3 = function() return {new = function(_, x, y, z) return vec(x, y, z) end} end
package.preload.Quaternion = function()
    local function q(x, y, z, w) return {x = x, y = y, z = z, w = w,
        WithX = function(s, v) return q(v, s.y, s.z, s.w) end, WithY = function(s, v) return q(s.x, v, s.z, s.w) end,
        WithZ = function(s, v) return q(s.x, s.y, v, s.w) end, WithW = function(s, v) return q(s.x, s.y, s.z, v) end} end
    return {Identity = q(0, 0, 0, 1)}
end
package.preload.TransformQ = function() return {FromOrPos = function(q, p) return {q = q, p = p} end} end
cam.focus = vec(0, 0, 0)
cam.pos = vec(0, 5, -5)
function cam:GetPlacementFocusPos() return self.focus end
function cam:GetKeyBindings() return {Forward = "W", Backward = "S", Left = "A", Right = "D", SpeedMod = "Shift"} end
local requestMode = cam.RequestMode
function cam:RequestMode(name, init) requestMode(self, name, init); self.init = init end
keys = {}
apis.InputManager = {GetKeyDown = function(_, k) return keys[k] == true end}
ground = 0
apis.voxelterrain = {GetPrimaryVoxelTerrainEntityID = function() return 1 end,
    RayCast = function(_, id, from, dir, dist) return from:GetY() - ground end}
apis.volumes = {Raycast = function() return nil end}
wallZ = nil   -- a wall across the z axis
figure = {}
api.entity = {FindPrefab = function(name) return prefabOK and name or nil end,
    CreateRequestCompletionToken = function() return {} end, HaveRequestsCompleted = function() return true end,
    InstantiatePrefab = function(name, a, token, t) figure.name = name; return 77 end,
    DestroyEntity = function(e) figure.destroyed = e end, FindEntityByName = function() return 5 end}
api.transform.HasTransform = function() return true end
api.transform.SetTransform = function(e, t) figure.at = {t.p:GetX(), t.p:GetY(), t.p:GetZ()} end
api.physics = {Flag_Building = 1, Flag_Prop = 2, Flag_Ride = 4, Flag_Track = 8, RayCast = function(world, a, b, flags, n)
    if wallZ and flags >= 4 and a:GetZ() < wallZ and b:GetZ() >= wallZ then return {{nEntityID = 9}} end
    return {}
end}
prefabOK = true
commands, emotes = {}, {}
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class ThirdPersonTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.lua.execute(THIRD)
        self.v = self.lua.eval('function(s) return assert(load(s, "visitor", "t", _G))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().V = self.v
        self.lua.execute('V.Init(function(c) commands[#commands+1] = c end, function(k) emotes[#emotes+1] = k end)')

    def tick(self, n):
        self.lua.execute(f'for i = 1, {n} do V.Tick() end')

    def at(self):
        return list(self.lua.eval('figure.at').values())

    def test_third_person_figure_and_avatar_camera(self):
        self.v.Start()
        self.assertEqual(self.v.View(), 'third')
        self.assertEqual(self.lua.eval('figure.name'), 'my_stoneguests_01_game')
        self.assertEqual(self.lua.eval('cam.mode'), 'Avatar')
        head = self.lua.eval('cam.init.tChangeSource.GetFocusPoints()')[0]
        self.assertAlmostEqual(head.GetY(), 1.6)
        self.assertEqual(list(self.lua.eval('commands').values())[-1], 'visitor|1|1')

    def test_walks_away_from_the_camera_and_stops_at_a_wall(self):
        self.v.Start()
        self.lua.execute('keys.W = true')
        self.tick(60)
        x, y, z = self.at()
        self.assertAlmostEqual(x, 0, places=3)
        self.assertGreater(z, 2.5)                    # camera is at -z: forward is +z
        self.lua.execute('wallZ = 5')
        self.tick(120)
        self.assertLess(self.at()[2], 5)
        self.lua.execute('keys.W = false; keys.D = true; wallZ = nil; ground = 0.3')
        self.tick(30)
        x2, y2, z2 = self.at()
        self.assertGreater(abs(x2), 1)
        self.assertAlmostEqual(y2, 0.3)

    def test_the_own_figure_is_no_wall_and_qa_keys_walk(self):
        self.v.Start()
        self.lua.execute('api.physics.RayCast = function() return {{nEntityID = 77}} end')   # only the figure itself
        self.lua.execute('V._TestKeys({W = true})')
        self.tick(60)
        self.assertGreater(self.at()[2], 2.5)
        self.lua.execute('V._TestKeys(nil)')
        z = self.at()[2]
        self.tick(30)
        self.assertAlmostEqual(self.at()[2], z)

    def test_mouse_turns_the_camera(self):
        self.v.Start()
        self.v.OnMouse(100, 0)
        self.assertGreater(self.lua.eval('cam.init.tChangeSource.GetRotation()'), 0)
        self.assertEqual(self.lua.eval('cam.init.tChangeSource.GetRotation()'), 0)

    def test_emote_wheel(self):
        self.v.Start()
        self.v.OnKey('t', True)
        self.tick(61)
        self.assertEqual(list(self.lua.eval('commands').values())[-1], 'visitor|1|0', 'no mouse look while the wheel is open')
        self.v.OnMouse(40, -40)                          # up right: the second wedge
        self.assertEqual(self.lua.eval('V.Wheel().selected'), 2)
        self.v.OnKey('4', True)
        self.assertEqual(self.lua.eval('V.Wheel().selected'), 4)
        self.v.OnKey('t', False)
        self.assertEqual(list(self.lua.eval('emotes').values()), ['up'])
        self.assertIsNone(self.v.Wheel())

    NATIVE = r'''
        -- The game's walker helper: a flat ride entrance in front of the figure (+z).
        gate = {blocker = nil, triggered = 0}
        package.loaded["Helpers.VisitorCameraTargetUtils"] = {
            FindInteractionTarget = function(at, fwd, apis)
                if fwd:GetZ() > 0.5 then return {nEntityID = 900, nRideEntityID = 2, sType = "FlatRideGate"} end
            end,
            TestInteraction = function(t) return {sInteraction = "BoardFlatRide", sBlocker = gate.blocker} end,
            GetInteractionString = function() return "[VisitorCameraInteraction_BoardRide:NAME='Teetassen']" end,
            GetBlockerString = function() return "[VisitorCameraBlocker_BrokenDown]" end,
            TriggerInteraction = function(t, r, apis)
                gate.triggered = gate.triggered + 1
                require("Editors.Shared.BaseUIMode").SetNewMode("GamefaceCameraSettings")
                return {bModeChanged = true}
            end}'''

    def test_f_opens_the_rides_and_frees_the_mouse(self):
        # TP-27: F opens the rides panel; mouse look pauses so its buttons can be clicked.
        self.v.Start()
        self.assertEqual(self.v.OnKey('f', True), 'list')
        self.assertIsNone(self.v.OnKey('f', False))
        self.v.SetList(True)
        self.assertTrue(self.v.ListOpen())
        self.assertEqual(list(self.lua.eval('commands').values())[-1], 'visitor|1|0')
        self.v.SetList(False)
        self.assertEqual(list(self.lua.eval('commands').values())[-1], 'visitor|1|1')
        self.v.SetList(True)
        self.v.Stop()
        self.assertFalse(self.v.ListOpen(), 'gone with the visit')
        self.v.SetList(True)
        self.assertFalse(self.v.ListOpen(), 'only while visiting')

    def test_tab_and_e_use_the_entrance_in_front_like_the_game(self):
        self.lua.execute(self.NATIVE)
        self.v.Start()
        self.assertEqual(self.v.OnKey('tab', True), 'stop')
        self.assertEqual(self.v.OnKey('e', True), 'interact')
        self.assertEqual(self.v.Hint()['action'], "[VisitorCameraInteraction_BoardRide:NAME='Teetassen']")
        keyOf, findRide = self.lua.globals().keyOf, self.lua.globals().findRide
        self.lua.execute('gate.blocker = "BrokenDown"')
        self.assertEqual(tuple(self.v.Interact(keyOf, findRide)), (False, '[VisitorCameraBlocker_BrokenDown]'))
        self.lua.execute('gate.blocker = nil')
        self.assertTrue(self.v.Interact(keyOf, findRide))
        self.assertEqual((self.lua.eval('gate.triggered'), self.lua.eval('ui.mode')), (1, 'GamefaceCameraSettings'))
        self.assertEqual(self.v.Activity(), 'faehrt Teetassen')
        self.assertIsNone(self.v.Hint())
        # After the ride the game puts its walker at the exit; the figure goes on from there.
        self.lua.execute('ui.mode = "VisitorCamera"; cam.mode = "Visitor"; cam.pos = require("Vector3"):new(12, 1.65, 9)')
        self.tick(90)
        self.assertEqual((self.lua.eval('ui.mode'), self.lua.eval('cam.mode')), ('Select', 'Avatar'))
        self.assertEqual(self.v.Activity(), 'geht als Besucher durch den Park')
        self.assertEqual(self.at(), [12, 0, 9])
        # Nothing in front: E says where to go.
        self.lua.execute('package.loaded["Helpers.VisitorCameraTargetUtils"].FindInteractionTarget = function() return nil end')
        self.assertFalse(self.v.Interact(keyOf, findRide)[0])
        self.v.Stop()
        self.assertEqual(self.lua.eval('figure.destroyed'), 77)
        self.assertEqual(list(self.lua.eval('commands').values())[-1], 'visitor|0|0')

    def test_e_at_a_shop_opens_its_list_and_a_number_buys(self):
        self.lua.execute('''shopHere = true
            package.loaded["pc2coop.shop"] = {
                InFront = function(x, y, z, yaw) if shopHere then return 4242 end end,
                Items = function(e) return {{index = 0, loc = "[ShopItem_Food_CheesePizza]", item = "Food_CheesePizza",
                    cost = 860, kind = "eat"}} end}''')
        keyOf, findRide = self.lua.globals().keyOf, self.lua.globals().findRide
        self.v.Start()
        self.assertEqual(self.v.Hint()['action'], 'Einkaufen')
        self.assertTrue(self.v.Interact(keyOf, findRide))
        self.assertEqual(self.v.Shop()['entity'], 4242)
        self.assertIsNone(self.v.OnKey('t', True))            # no emote wheel over the list
        self.assertIsNone(self.v.Wheel())
        self.assertEqual(tuple(self.v.OnKey('1', True)), ('buy', 1))
        entity, item = self.v.Pick(1)
        self.assertEqual((entity, item['item'], item['cost']), (4242, 'Food_CheesePizza', 860))
        self.assertIsNone(self.v.Shop())
        # Tab closes the list instead of ending the visit; E closes it too.
        self.v.Interact(keyOf, findRide)
        self.assertIsNone(self.v.OnKey('tab', True))
        self.assertIsNone(self.v.Shop())
        self.assertTrue(self.v.Active())
        self.v.Interact(keyOf, findRide)
        self.assertTrue(self.v.Interact(keyOf, findRide))
        self.assertIsNone(self.v.Shop())
        self.lua.execute('shopHere = false')
        self.assertFalse(self.v.Interact(keyOf, findRide)[0])

    def test_v_switches_between_the_figure_and_the_games_walk(self):
        self.v.Start()
        self.assertEqual(self.v.OnKey('v', True), 'view')
        self.assertTrue(self.v.ToggleView())
        self.assertEqual(self.lua.eval('ui.mode'), 'VisitorCamera')
        self.assertTrue(self.v.GuestView())
        self.assertEqual(self.lua.eval('figure.destroyed'), 77)   # no own figure in first person
        self.assertEqual(self.v.Activity(), 'geht als Besucher in Ich-Sicht durch den Park')
        # The walker went somewhere; V: the figure stands there.
        self.lua.execute('cam.pos = require("Vector3"):new(30, 1.65, 40); cam.mode = "Visitor"')
        self.assertTrue(self.v.ToggleView())
        self.assertFalse(self.v.GuestView())
        self.assertEqual(self.lua.eval('ui.mode'), 'Select')
        # The game resets the camera after its mode change; the figure's camera comes back.
        self.lua.execute('cam.mode = "StandardOrbit"')
        self.tick(30)
        self.assertEqual(self.lua.eval('cam.mode'), 'Avatar')
        self.tick(120)
        self.assertTrue(self.v.Active())
        self.assertEqual(self.at(), [30, 0, 40])

    def test_riding_from_the_games_walk_comes_back_into_it(self):
        self.v.Start('first')
        self.assertTrue(self.v.GuestView())
        self.assertEqual(self.lua.eval('ui.mode'), 'VisitorCamera')
        # The game's walker used an entrance (its own key).
        self.lua.execute('ui.mode = "GamefaceCameraSettings"; cam.mode = "FirstPersonRide"')
        self.tick(30)
        self.assertTrue(self.v.Riding())
        self.assertTrue(self.v.Active())
        self.lua.execute('ui.mode = "VisitorCamera"; cam.mode = "Visitor"')
        self.tick(90)
        self.assertIsNone(self.v.Riding())
        self.assertTrue(self.v.GuestView())
        self.assertTrue(self.v.Active())

    def test_first_person_when_the_figure_is_missing(self):
        self.lua.execute('prefabOK = false')
        self.v.Start()
        self.assertEqual(self.v.View(), 'first')
        self.assertEqual(self.lua.eval('cam.mode'), 'Walking')


if __name__ == '__main__':
    unittest.main()
