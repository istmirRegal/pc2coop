"""rides.lua: coasters travel as blueprint files, against a fake game world."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/rides.lua'

FAKES = r"""
records = {}
-- rides[entity] = {x, z, tracked, size}; one station per ride (entity + 1000)
rides = {}
saved, loaded, removed, added, commits = {}, {}, {}, {}, 0
local function vec(x, y, z) return {GetX = function() return x end, GetY = function() return y end, GetZ = function() return z end} end
local ridestation = {}
function ridestation:GetAllStations()
    local out = {}
    for e in pairs(rides) do out[#out+1] = e + 1000 end
    table.sort(out)
    return out
end
function ridestation:GetRideEntityIDFromStationEntityID(s) return s - 1000 end
local ridesAPI = {}
function ridesAPI:IsTrackedRide(e) return rides[e] ~= nil and rides[e].tracked end
function ridesAPI:IsRide(e) return rides[e] ~= nil end
function ridestation:IsWaterSlide(e) return rides[e] ~= nil and rides[e].platform ~= nil end
platforms, platformMoves = {}, {}
local flumes = {}
function flumes:GetPlatformForAttachedRide(e) return rides[e] and rides[e].platform end
function flumes:GetFlumePlatformEditToken(p) return {platform = p} end
function flumes:AttachFlumeToPlatform(e) end
-- The game's delete of a selection, as rides.lua calls it.
package.preload["Editors.Scenery.Utils.SceneryUtils"] = function()
    return {DeleteMultiSelection_Core = function(sel, w, scenario, h)
        assert(not scenario:HandlePreventDeletingRidesScenarioParam())
        for i = 1, sel:CountCategory(sel.SelectionCategories_TrackedRides) do removed[#removed+1] = sel:GetTrackRide(i) end
        for i = 1, sel:CountCategory(sel.SelectionCategories_FlumePlatforms) do
            platformMoves[#platformMoves+1] = sel:GetFlumePlatform(i) .. ":" .. sel:CountCategory(sel.SelectionCategories_TrackedRides)
        end
        assert(sel:CountCategory(sel.SelectionCategories_Scenery) == 0)
    end}
end
trackedrides = {notified = {}}
function trackedrides:NotifyTrackedRideOfTrackEdit(e, editing) table.insert(self.notified, tostring(e) .. ":" .. tostring(editing)) end
function trackedrides:CompleteBlueprintSerialisationLoad() end
local ws = {}
function ws:CreateSaveSelection()
    local sel = {ids = {}}
    function sel:AddEntityID(e) table.insert(self.ids, e) end
    return sel
end
local hierarchies = {}
local editors = {}
function editors:CreateUndoOperationsHierarchy()
    local h = {}
    function h:IsLoadedBlueprintReadyForEditing() return true end
    function h:CreateCompositeObject(opts) return {Destroy = function() end} end
    function h:AddBlueprintToCompositeObject(c) table.insert(added, pendingFile) end
    function h:GetFullUndoChangeList() return h end
    return h
end
apis = {ridestation = ridestation, rides = ridesAPI, trackedrides = trackedrides, worldserialisation = ws, editors = editors,
    flatrides = {}, flumes = flumes}
manager = {}
function manager:SaveBlueprintToFile(path, sel, compressed)
    coroutine.yield()
    saved[#saved+1] = path .. "=" .. table.concat(sel.ids, ",")
    return true, path
end
function manager:LoadBlueprintFromFile(path) pendingFile = path; loaded[#loaded+1] = path; return true end
api = {world = {GetWorldAPIs = function() return apis end},
    game = {GetEnvironment = function() return {RequireInterface = function() return manager end} end},
    track = {
        GetTrackHolder = function(e) return {ride = e} end,
        GetTrackEntity = function(h) return h.ride end,
        RemoveHolder = function(h, holder) removed[#removed+1] = holder.ride end,
        ComputeApproxLocalAABB = function(holder)
            local r = rides[holder.ride]
            return vec(0, 0, 0), vec(r.size, 5, r.size)
        end}}
function keyOf(e) local r = rides[e] or platforms[e]; return r and ("F" .. r.x .. "_0_" .. r.z) or nil end
function findRide(key) for e in pairs(rides) do if keyOf(e) == key then return e end end end
applyingNow = false
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class RidesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.rides = self.lua.eval('function(s) return assert(load(s, "rides", "t", _G))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().R = self.rides
        self.lua.execute('''
            rides[10] = {x = 100, z = 200, tracked = true, size = 30}
            R.Init(function(s) records[#records+1] = s end, function() return applyingNow end, keyOf, findRide)
            R.SetTag("76561190000000001")
            assert(R.Install())
        ''')
        self.tick(50)   # first scan: what is there already is known, nothing is sent

    def tick(self, n):
        self.lua.execute(f'for i = 1, {n} do R.Tick(false) end')

    def sent(self):
        return [r for r in self.lua.eval('records').values() if r.startswith('sync:ride|')]

    def test_existing_rides_are_not_sent_at_start(self):
        self.assertEqual(self.sent(), [])

    def test_track_editor_session_sends_the_ride_once_when_it_closes(self):
        self.lua.execute('apis.trackedrides:NotifyTrackedRideOfTrackEdit(10, true)')
        self.assertEqual(list(self.rides.Editing().values()), ['F100_0_200'])
        self.lua.execute('rides[10].size = 60')     # track edited: bigger
        self.tick(160)
        self.assertEqual(self.sent(), [], 'nothing goes out while the editor is open')
        self.lua.execute('apis.trackedrides:NotifyTrackedRideOfTrackEdit(10, false)')
        self.assertEqual(len(self.rides.Editing()), 0)
        self.tick(160)
        self.assertEqual(self.sent(), ['sync:ride|F100_0_200|F100_0_200|pc2coop-ride-76561190000000001-1.blueprint'])
        self.assertEqual(list(self.lua.eval('saved').values()), ['/run/pc2coop-ride-76561190000000001-1.blueprint=10'])
        self.assertEqual(list(self.lua.eval('trackedrides.notified').values()), ['10:true', '10:false'])   # game still told

    def test_scan_finds_new_moved_and_removed_rides(self):
        self.lua.execute('rides[20] = {x = 5, z = 6, tracked = true, size = 10}')   # from a blueprint
        self.lua.execute('rides[30] = {x = 7, z = 8, tracked = false, size = 10}')  # flat ride: not ours
        self.tick(160)
        self.assertEqual(self.sent(), ['sync:ride|-|F5_0_6|pc2coop-ride-76561190000000001-1.blueprint'])
        self.lua.execute('rides[20].x = 50')
        self.tick(160)
        self.assertEqual(self.sent()[-1], 'sync:ride|F5_0_6|F50_0_6|pc2coop-ride-76561190000000001-2.blueprint')
        self.lua.execute('rides[20] = nil')
        self.tick(160)
        self.assertEqual(self.sent()[-1], 'sync:ride|F50_0_6|-|-')
        self.assertEqual(len(self.sent()), 3)

    def test_remote_snapshot_waits_for_its_file_then_swaps_without_echo(self):
        self.lua.execute('''
            -- the swap: the blueprint becomes a new entity at the same place, still settling
            swap = function() local old = rides[10]; rides[10] = nil; rides[11] = {x = old.x, z = old.z, tracked = true, size = 31} end
            tools = {waitFor = function(p, label) for i = 1, 100 do if p() then return end; coroutine.yield() end; error("timeout-" .. label) end,
                     commit = function() commits = commits + 1; swap() end}
            task = coroutine.create(function()
                applyingNow = true
                R.Apply("F100_0_200", "F100_0_200", "pc2coop-ride-1-7.blueprint", tools)
                applyingNow = false
            end)
            for i = 1, 10 do coroutine.resume(task) end
        ''')
        self.assertEqual(self.lua.eval('commits'), 0, 'the file is not there yet')
        self.lua.execute('''
            R.FileReady("pc2coop-ride-1-7.blueprint")
            for i = 1, 10 do if coroutine.status(task) ~= "dead" then coroutine.resume(task) end end
            rides[11].size = 33   -- settles a moment later
        ''')
        self.assertEqual(self.lua.eval('commits'), 1)
        self.assertEqual(list(self.lua.eval('removed').values()), [10])
        self.assertEqual(list(self.lua.eval('added').values()), ['/run/pc2coop-ride-1-7.blueprint'])
        self.tick(400)
        self.assertEqual(self.sent(), [], 'what came from the host is not sent back')
        self.lua.execute('rides[11].x = 300')   # a real local move later is sent again
        self.tick(160)
        self.assertEqual(self.sent(), ['sync:ride|F100_0_200|F300_0_200|pc2coop-ride-76561190000000001-1.blueprint'])

    def test_a_removal_needs_no_file(self):
        self.lua.execute('''
            tools = {waitFor = function(p) assert(p()) end, commit = function() commits = commits + 1 end}
            local task = coroutine.create(function() R.Apply("F100_0_200", "-", "-", tools) end)
            assert(coroutine.resume(task))
        ''')
        self.assertEqual(list(self.lua.eval('removed').values()), [10])
        self.assertEqual(len(self.lua.eval('loaded')), 0)

    def test_a_flume_platform_travels_with_all_its_slides(self):
        self.lua.execute('''
            platforms[50] = {x = 9, z = 9, sections = {1, 2}}
            rides[51] = {x = 1, z = 1, tracked = true, size = 10, platform = 50}
            rides[52] = {x = 2, z = 2, tracked = true, size = 12, platform = 50}
        ''')
        self.tick(160)
        self.assertEqual(self.sent(), ['sync:ride|-|F9_0_9|pc2coop-ride-76561190000000001-1.blueprint'])
        saved = list(self.lua.eval('saved').values())[0]
        self.assertEqual(sorted(saved.split('=')[1].split(',')), ['50', '51', '52'])
        self.lua.execute('apis.trackedrides:NotifyTrackedRideOfTrackEdit(52, true)')
        self.assertEqual(list(self.rides.Editing().values()), ['F9_0_9'], 'editing a slide locks its platform')
        self.lua.execute('''
            apis.trackedrides:NotifyTrackedRideOfTrackEdit(52, false)
            local task = coroutine.create(function()
                R.Apply("F9_0_9", "-", "-", {waitFor = function(p) assert(p()) end, commit = function() commits = commits + 1 end})
            end)
            assert(coroutine.resume(task))
        ''')
        self.assertEqual(sorted(self.lua.eval('removed').values()), [51, 52])
        self.assertEqual(list(self.lua.eval('platformMoves').values()), ['50:2'])

    def test_flat_rides_from_a_blueprint_travel_as_files_others_through_the_replay(self):
        self.lua.execute('rides[40] = {x = 3, z = 4, tracked = false, size = 5}')   # placed with the flat ride tool
        self.tick(160)
        self.assertEqual(self.sent(), [])
        self.lua.execute('''
            rides[41] = {x = 6, z = 7, tracked = false, size = 5}
            apis.trackedrides:CompleteBlueprintSerialisationLoad()               -- the blueprint tool's commit
        ''')
        self.tick(160)
        self.assertEqual(self.sent(), ['sync:ride|-|F6_0_7|pc2coop-ride-76561190000000001-1.blueprint'])
        self.lua.execute('rides[41] = nil')
        self.tick(160)
        self.assertEqual(len(self.sent()), 1, 'its delete goes through the replay, not as a ride file')

    def test_lines_are_checked(self):
        for key, ok in (('F1_-2_3', True), ('-', True), ('S1_2_3', False), ('F1_2', False), ('F1_2_3|x', False)):
            self.assertEqual(self.rides.ValidKey(key), ok, key)
        for name, ok in (('pc2coop-ride-1-2.blueprint', True), ('-', True), ('pc2coop-join.bin', False),
                         ('../pc2coop-ride-1-2.blueprint', False), ('pc2coop-ride-1-2.blueprint.exe', False)):
            self.assertEqual(self.rides.ValidFile(name), ok, name)
        with self.assertRaises(Exception):
            self.lua.execute('R.Apply("S1_2_3", "-", "-", {waitFor = function() end, commit = function() end})')

    def test_old_files_are_cleaned_up(self):
        for i in range(45):
            self.rides.FileReady(f'pc2coop-ride-1-{i}.blueprint')
        deletes = [r for r in self.lua.eval('records').values() if r.startswith('sync:ridedel|')]
        self.assertEqual(deletes[0], 'sync:ridedel|pc2coop-ride-1-0.blueprint')
        self.assertEqual(len(deletes), 5)


if __name__ == '__main__':
    unittest.main()
