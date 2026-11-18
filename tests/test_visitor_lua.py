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

    def test_rides_nearest_first_with_stats(self):
        rides = [dict(r.items()) for r in self.v.Rides(self.lua.globals().keyOf).values()]
        self.assertEqual([(r['name'], r['kind'], r['dist']) for r in rides], [('Teetassen', 'Fahrgeschaeft', 5), ('Conlan', 'Achterbahn', 90)])
        self.assertEqual((rides[0]['e'], rides[0]['n']), (2.5, 1.1))
        self.assertIsNone(rides[1].get('e'), 'untested ride: no excitement yet')
        self.assertEqual((rides[1]['queue'], rides[1]['trains']), (12, 2))


if __name__ == '__main__':
    unittest.main()
