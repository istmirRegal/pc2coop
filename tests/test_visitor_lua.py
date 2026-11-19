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

    def test_tab_and_e(self):
        self.v.Start()
        self.assertEqual(self.v.OnKey('tab', True), 'stop')
        self.assertEqual(self.v.OnKey('e', True), 'interact')
        self.lua.execute('rides[2].x, rides[2].z = 10, 5')   # 11 m from the figure
        self.assertTrue(self.v.Interact(self.lua.globals().keyOf, self.lua.globals().findRide))
        self.assertEqual(self.lua.eval('ui.mode'), 'GamefaceCameraSettings')
        self.v.Stop()
        self.assertEqual(self.lua.eval('figure.destroyed'), 77)
        self.assertEqual(list(self.lua.eval('commands').values())[-1], 'visitor|0|0')

    def test_g_goes_along_with_the_nearest_guest_and_back(self):
        self.lua.execute('''
            local V3 = require("Vector3")
            guestsAt = {[501] = {6, 0, 8}, [502] = {2, 0, 3}}   -- guest -> where it stands; 502 is nearer
            apis.SelectAndEditComponent = {FindParentWithComponent = function(_, e)
                if e == 601 then return 501 elseif e == 602 then return 502 end
                return e
            end}
            apis.guests = {TryGetGuestGroupID = function(_, e) if guestsAt[e] then return 7 end return nil end}
            local calc = api.transform.CalculateWorldTransform
            api.transform.CalculateWorldTransform = function(e)
                local g = guestsAt[e]
                if g then return {GetPos = function() return V3:new(g[1], g[2], g[3]) end} end
                return calc(e)
            end
            -- only the select mode's "everything" ray sees guests
            api.physics.RayCast = function(world, a, b, flags, n)
                if flags == -1 then return {{nEntityID = 9}, {nEntityID = 601}, {nEntityID = 602}} end
                return {}
            end''')
        self.v.Start()
        self.lua.execute('''local B = require("Editors.Shared.BaseUIMode")
            B.SetNewMode = function(name, a, b) ui.mode, ui.target, ui.kind = name, a, b end''')
        self.assertEqual(self.v.OnKey('g', True), 'follow')
        self.assertTrue(self.v.FollowGuest())
        self.assertEqual((self.lua.eval('ui.mode'), self.lua.eval('ui.target'), self.lua.eval('ui.kind')),
                         ('GamefaceCameraSettings', 502, 'Guest'))
        self.assertEqual(self.v.Activity(), 'begleitet einen Gast')
        self.assertIsNone(self.v.Feet())                     # the others draw no figure meanwhile
        self.assertIsNone(self.v.OnKey('g', True))
        self.tick(30)
        self.assertTrue(self.v.Active())
        # "Zurueck" in the game's guest camera: back to the figure.
        self.lua.execute('ui.mode = "Select"; cam.mode = "StandardOrbit"')
        self.tick(90)
        self.assertEqual(self.v.Activity(), 'geht als Besucher durch den Park')
        self.assertEqual(self.lua.eval('cam.mode'), 'Avatar')
        self.lua.execute('guestsAt = {}')
        self.assertEqual(tuple(self.v.FollowGuest()), (False, 'kein Gast in der Naehe'))

    def test_first_person_when_the_figure_is_missing(self):
        self.lua.execute('prefabOK = false')
        self.v.Start()
        self.assertEqual(self.v.View(), 'first')
        self.assertEqual(self.lua.eval('cam.mode'), 'Walking')


if __name__ == '__main__':
    unittest.main()
