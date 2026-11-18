"""Sync module against a fake editor API: capture, remote apply, echo suppression."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1]/'probe/PC2CoopProbe/Main/pc2coop/sync.lua'

FAKE_GAME = r'''
local parts, nextPart, nextEntity = {}, 988, 50000
local function vec(x, y, z) return {GetX=function() return x end, GetY=function() return y end, GetZ=function() return z end} end
local function quat(x, y, z, w)
    local q = {GetX=function() return x end, GetY=function() return y end, GetZ=function() return z end, GetW=function() return w end}
    q.WithX=function(_, v) return quat(v, y, z, w) end; q.WithY=function(_, v) return quat(x, v, z, w) end
    q.WithZ=function(_, v) return quat(x, y, v, w) end; q.WithW=function(_, v) return quat(x, y, z, v) end
    return q
end
package.preload.Quaternion = function() return {Identity = quat(0, 0, 0, 1)} end
package.preload.Vector3 = function() return {new=function(_, x, y, z) return vec(x, y, z) end} end
package.preload.TransformQ = function() return {FromOrPos=function(q, p)
    return {q=q, p=p, GetPos=function(self) return self.p end, GetOr=function(self) return self.q end} end} end

-- Userdata stand-in: every hierarchy shares one metatable whose __index holds methods.
local H = {}
local meta = {__index = H}
H.__index = H
local function newEdit(part) return {part = part, scale = 1,
    SetTransform=function(self, t) self.t = t end, SetScale=function(self, s) self.scale = s end,
    GetScale=function(self) return self.scale end, Destroy=function(self) self.destroyed = true end} end
function H.CreateNewPart(self, resource) nextPart = nextPart + 1; local e = newEdit(nextPart); e.resource = resource; e.new = true; self.ops[#self.ops+1] = e; return e end
function H.EditExistingPart(self, part) local e = newEdit(part); self.ops[#self.ops+1] = e; return e end
function H.EditExistingParts(self, set) local out = {}; for _, p in ipairs(set:GetPartIDCollection()) do out[#out+1] = H.EditExistingPart(self, p) end; return out end
function H.DestroyExistingParts(self, set) return H.EditExistingParts(self, set) end
function H.StartEditingPart_Scenery(self, e) return e end
function H.StartEditingParts_Scenery(self, es) return es end
function H.GetFullUndoChangeList(self) return {hierarchy = self} end
local function newHierarchy() return setmetatable({ops = {}}, meta) end

local previews, waits = {}, {}
local undo = {}
function undo.IsPreviewingChangeList() return previewingNow == true end
function undo.IsBusy() return false end
function undo.IsOperationComplete() return true end
previewLists = {}
function undo.PreviewChangeList(cl) local token = {cl = cl}; previewLists[#previewLists+1] = cl; return {}, token end
function undo.CanCommitPreview() return true end
function undo.CancelPreview() return {} end
function undo.Checkpoint(data) checkpoint = data end
function undo.GetCheckpointData() return checkpoint end
function undo.GetUndoneCheckpointData() return undone end
-- Undo of the newest placed part: the fake simply removes it.
function undo.Undo()
    local newest
    for part in pairs(parts) do if not newest or part > newest then newest = part end end
    if newest then parts[newest] = nil end
    return {}
end
function undo.Redo() return {} end
commits = 0
function undo.CommitPreview(token)
    commits = commits + 1
    if token.cl.hierarchy.terrain then
        for _, c in ipairs(token.cl.hierarchy.terrain.calls) do
            if type(c) == "table" then
                paths[#paths+1] = string.format("%s %g,%g -> %g,%g merge=%s", c.data, c.start:GetX(), c.start:GetZ(),
                    c.pos:GetX(), c.pos:GetZ(), tostring(token.cl.hierarchy.mergeError))
            else terrainCalls[#terrainCalls+1] = c end
        end
    end
    for _, c in ipairs(token.cl.hierarchy.composites or {}) do
        if c.demolish and c.destroyed then
            for _, e in ipairs(c.moved or {}) do rides[#rides+1] = "demolished " .. tostring(e) end
        elseif c.ride and c.t then rides[#rides+1] = string.format("%s %g,%g", c.ride, c.t:GetPos():GetX(), c.t:GetPos():GetZ()) end
    end
    for _, e in ipairs(token.cl.hierarchy.ops) do
        if e.destroyed then parts[e.part] = nil
        else
            local r = e.resource or (parts[e.part] and parts[e.part].resource)
            local t = e.t or {p = vec(1, 2, 3), q = quat(0, 0, 0, 1)}
            nextEntity = nextEntity + 1
            parts[e.part] = {resource = r, p = t.p, q = t.q, entity = nextEntity}
        end
    end
    return {}
end

local entities = {}
local placement = {}
function placement:PlacementPartExists(p) return parts[p] ~= nil end
function placement:GetPartResourceName(p) return parts[p].resource end
function placement:PlacementIDToEntityID(p) entities[parts[p].entity] = p; return parts[p].entity end
function placement:EntityIDToPlacementID(entity) for p, v in pairs(parts) do if v.entity == entity then return p end end end
function placement:HasPartsRequiringUpdate() return false end
local scenery = {}
function scenery:GetMoveObjectPartIDs(e) return {e.part} end
function scenery:CreateBuildingPartSet() local ids = {}; return {Add=function(_, p) ids[#ids+1] = p end, GetPartIDCollection=function() return ids end} end
local camera = {}
function camera:GetPosYPRZoom() return vec(1, 2, 3), vec(0.5, -0.2, 0), 4 end
function camera:GetCurrentModeName() return "StandardOrbit" end
function camera:GetPlacementFocusPos() return vec(10, 5, 10) end
function camera:SetPosYPR(p, ypr) camera.jumped = {p:GetX(), ypr:GetY()} end
function H.GetTerrainEditOperation(self) self.terrain = self.terrain or {calls = {}}; return self.terrain end
terrainCalls = {}
local gameterrain = {}
function gameterrain:AddPushPullToChangeList(op, pos, size, intensity, hardness)
    op.calls[#op.calls+1] = string.format("pushpull %g %g %g %g %g %g", pos:GetX(), pos:GetY(), pos:GetZ(), size, intensity, hardness)
end
function gameterrain:SetTerrainEditOpCollisionFlags(op, a, b, c, d, e, f) op.calls[#op.calls+1] = "flags" end
function gameterrain:CreateLake(pos, kind) return {hierarchy = {ops = {}, terrain = {calls = {"lake " .. kind}}}} end
-- Paths: a spline move object inside a hierarchy; its end point is set directly on it.
paths = {}
local volumes = {}
function volumes:CreateMoveObjectForVolumeSpline(h, transform, curved, classic, right, stub)
    local mo = {h = h, start = transform:GetPos()}
    mo.GetPosition = function(self) return self.pos end
    mo.SetPosition = function(self, p) self.pos = p end
    h.terrain = h.terrain or {calls = {}}
    table.insert(h.terrain.calls, mo)
    return mo
end
function volumes:SetSplinePathData(mo, outline, render, edge, width, depth, clip, grounded, supports, colour, edgeColour)
    mo.data = outline .. "/" .. render .. "/" .. width .. "/" .. tostring(colour[1])
end
function H.SetErrorOnPathMergeUnchangedModifyVolumes(self, value) self.mergeError = value end
function H.BeginVolumeModificationsBlock(self) self.block = true end
function H.EndVolumeModificationsBlock(self) self.block = false end
function H.SetPerformTerrainModificationsModifyVolumes(self, value) self.terrainFollows = value end
-- Flat rides: a composite object of the hierarchy holds the ride; placed at commit.
rides = {}
function H.CreateCompositeObject(self, opts)
    local c = {t = nil, demolish = opts and opts.bDemolishOnly}
    c.SetTransform = function(me, t) me.t = t end
    c.GetTransform = function(me) return me.t end
    c.AlignCompositeRotation = function() end
    c.Destroy = function(me) me.destroyed = true end
    self.composites = self.composites or {}
    table.insert(self.composites, c)
    return c
end
local flatrides = {}
function flatrides:CreateFlatRideEditToken(name) return {ride = name} end
function flatrides:AddFlatRide(h, composite, token, terrain, everyFrame) composite.ride = token.ride end
function flatrides:GetFlatRideEditToken(entity) return {entity = entity} end
function flatrides:RemoveFlatRide(h, token)
    h.composites = h.composites or {}
    table.insert(h.composites, {demolish = true, destroyed = true, moved = {token.entity}})
end
function flatrides:MoveFlatRide(h, composite, token, terrain, everyFrame)
    composite.moved = composite.moved or {}
    table.insert(composite.moved, token.entity)
end
-- The game's delete of a selection (Editors.Scenery.Utils.SceneryUtils), as it moves rides.
package.preload["Editors.Scenery.Utils.SceneryUtils"] = function()
    local U = {}
    U.DeleteMultiSelection_Core = function(selection, apis, scenario, h)
        local c = h:CreateCompositeObject({bDemolishOnly = true})
        for _, e in ipairs(selection) do
            apis.flatrides:MoveFlatRide(h, c, apis.flatrides:GetFlatRideEditToken(e), 0, false)
        end
        c:Destroy()
        return false, #selection > 0, false, false
    end
    return U
end
mgmt = {}
local park = {}
function park:SetParkName(name) mgmt[#mgmt+1] = "name " .. name end
local facilities = {}
function facilities:SetOpen(entity, open) mgmt[#mgmt+1] = "open " .. tostring(entity) .. " " .. tostring(open) end
local apis = {editors = {CreateUndoOperationsHierarchy = function() return newHierarchy() end}, gameterrain = gameterrain,
    volumes = volumes, flatrides = flatrides,
    park = park, facilities = facilities,
    placement = placement, scenery = scenery, CameraModeManager = camera}
-- The editor: the game hands out the current tool as a Lua object.
editor = {mode = nil, ui = "Select", edit = "Select", left = 0}
package.preload["Editors.Shared.BaseEditMode"] = function() return {GetModeHelperEntity = function() return 1 end} end
package.preload["Editors.Shared.BaseUIMode"] = function() return {GetModeHelperEntity = function() return 2 end,
    SetNewMode = function(name) editor.left = editor.left + 1; editor.mode, editor.ui, editor.edit = nil, name, name end} end
apis.GameModeHelperComponent = {GetCurrentModeName = function() return editor.edit end, GetCurrentMode = function() return editor.mode end}
apis.UIModeHelperComponent = {GetCurrentModeName = function() return editor.ui end}
api = {undo = undo, world = {GetWorldAPIs = function() return apis end},
    entity = {CreateRequestCompletionToken=function() return {} end, HaveRequestsCompleted=function() return true end},
    transform = {CalculateWorldTransform=function(entity)
        local p = parts[entities[entity]]
        return {GetPos=function() return p.p end, GetOr=function() return p.q end}
    end},
    player = {GetPlayerName=function() return "Tester" end},
    spatial = {Flag_Scenery = 4, SphereQuery=function(position, radius)
        local out = {}
        for _, v in pairs(parts) do out[#out+1] = v.entity end
        return out
    end}}
api.ui2 = {}
game = {parts = parts, newHierarchy = newHierarchy, camera = camera}
'''


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class SyncTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKE_GAME)
        self.lua.execute('records = {}')
        for name in ('shared', 'world', 'rides', 'visitor'):
            source = (SOURCE.parent / f'{name}.lua').read_text(encoding='utf8')
            self.lua.eval('function(n, s) package.preload["pc2coop." .. n] = function() return assert(load(s, n, "t", _G))() end end')(name, source)
        recorder = (SOURCE.parent / 'recorder.lua').read_text(encoding='utf8')
        self.lua.eval('function(s) package.preload["pc2coop.recorder"] = function() return assert(load(s, "recorder", "t", _G))() end end')(recorder)
        replay = (SOURCE.parent / 'replay.lua').read_text(encoding='utf8')
        self.lua.eval('function(s) package.preload["pc2coop.replay"] = function() return assert(load(s, "replay", "t", _G))() end end')(replay)
        loader = self.lua.eval('function(s) return assert(load(s, "sync", "t", _G))() end')
        self.sync = loader(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().sync = self.sync
        self.lua.execute('sync.Init(function(s) records[#records+1] = s end); for i = 1, 3 do sync.Tick() end')
        self.lua.execute('sync.Receive("S|Tester")')

    def records(self, prefix):
        return [r for r in self.lua.eval('records').values() if r.startswith(prefix)]

    def tick(self, n=5):
        self.lua.execute(f'for i = 1, {n} do sync.Tick() end')

    def local_build(self):
        self.lua.execute('''
            local h = api.world.GetWorldAPIs().editors:CreateUndoOperationsHierarchy()
            local e = h:StartEditingPart_Scenery(h:CreateNewPart("AQ_Rock_04"))
            e:SetTransform(require("TransformQ").FromOrPos(require("Quaternion").Identity, require("Vector3"):new(10, 5, 10)))
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            api.undo.CommitPreview(preview)
        ''')
        self.tick()

    def test_local_create_is_reported_once(self):
        self.local_build()
        ups = self.records('sync:up|')
        self.assertEqual(len(ups), 1, self.lua.eval('records').values())
        self.assertIn('||0|AQ_Rock_04|10|5|10|0|0|0|1|1', ups[0])
        self.tick(200)
        self.assertEqual(len(self.records('sync:up|')), 1)

    def test_remote_upsert_move_delete_without_echo(self):
        self.lua.execute('sync.Receive("U|1|g1|Alice|1|Fern|30|0.5|30|0|0.7071|0|0.7071|1.5")')
        self.tick(20)
        self.lua.execute('sync.Receive("U|2|g1|Alice|2|Fern|35|0.5|32|0|0|0|1|1")')
        self.tick(20)
        self.assertEqual(len(self.records('sync:applied|')), 2)
        self.assertEqual(self.lua.eval('(function() local n=0; for _ in pairs(game.parts) do n=n+1 end; return n end)()'), 1)
        self.lua.execute('sync.Receive("D|3|g1|Alice|3")')
        self.tick(20)
        self.assertEqual(self.lua.eval('next(game.parts)'), None)
        self.assertEqual(self.records('sync:up|') + self.records('sync:del|'), [])

    def test_ack_maps_local_part_and_later_move_carries_global_id(self):
        self.local_build()
        part = self.records('sync:up|')[0].split('|')[1]
        self.lua.execute(f'sync.Receive("M|1|g7|{part}|1")')
        self.tick(3)
        self.lua.execute(f'''
            local h = api.world.GetWorldAPIs().editors:CreateUndoOperationsHierarchy()
            local e = h:StartEditingPart_Scenery(h:EditExistingPart({part}))
            e:SetTransform(require("TransformQ").FromOrPos(require("Quaternion").Identity, require("Vector3"):new(20, 5, 15)))
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            api.undo.CommitPreview(preview)
        ''')
        self.tick()
        self.assertIn(f'sync:up|{part}|g7|1|AQ_Rock_04|20|5|15', self.records('sync:up|')[-1])

    def test_duplicate_and_old_sequences_are_ignored(self):
        self.lua.execute('sync.Receive("U|1|g1|A|1|Fern|1|1|1|0|0|0|1|1")')
        self.tick(20)
        self.lua.execute('sync.Receive("U|1|g1|A|1|Fern|1|1|1|0|0|0|1|1")')
        self.tick(20)
        self.assertEqual(len(self.records('sync:applied|')), 1)

    def test_presence_and_camera_jump(self):
        self.tick(40)
        self.assertTrue(self.records('sync:pres|1.0|2.0|3.0|0.5|-0.2|4|StandardOrbit|schaut|10.0|5.0|10.0'))
        self.lua.execute('sync.Receive("C|5|6|7|0.1|-0.3")')
        self.assertEqual(list(self.lua.eval('game.camera.jumped').values()), [5, -0.3])


    def terrain_stroke(self, commit=True):
        self.lua.execute(f'''
            local apis = api.world.GetWorldAPIs()
            local h = apis.editors:CreateUndoOperationsHierarchy()
            local op = h:GetTerrainEditOperation()
            apis.gameterrain:SetTerrainEditOpCollisionFlags(op, true, false, false, false, true, false)
            apis.gameterrain:AddPushPullToChangeList(op, require("Vector3"):new(1.5, 2, 3), 8, 0.25, 0.5)
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            if {"true" if commit else "false"} then api.undo.CommitPreview(preview) else api.undo.CancelPreview(preview) end
        ''')
        self.tick()

    def test_committed_terrain_stroke_is_sent_cancelled_is_not(self):
        self.terrain_stroke(commit=False)
        self.assertEqual(self.records('sync:cmd|'), [])
        self.terrain_stroke(commit=True)
        cmds = self.records('sync:cmd|')
        self.assertEqual(cmds, ['sync:cmd|gameterrain.SetTerrainEditOpCollisionFlags(@op,b1,b0,b0,b0,b1,b0);'
                                'gameterrain.AddPushPullToChangeList(@op,v1.5:2:3,n8,n0.25,n0.5)'])

    def test_remote_terrain_batches_replay_exactly_and_are_not_echoed(self):
        batch = 'gameterrain.AddPushPullToChangeList(@op,v1.5:2:3,n8,n0.25,n0.5)'
        self.lua.execute(f'sync.Receive("K|1|{batch}"); sync.Receive("K|2|{batch}")')
        self.tick(20)
        calls = list(self.lua.eval('terrainCalls').values())
        self.assertEqual(calls, ['pushpull 1.5 2 3 8 0.25 0.5'] * 2)
        self.assertEqual(self.records('sync:cmd|'), [])
        self.assertTrue(self.records('sync:applied|2'))

    def test_remote_lake_uses_returned_change_list(self):
        self.lua.execute('sync.Receive("K|1|gameterrain.CreateLake(v4:0:4,sCalmLake)")')
        self.tick(20)
        self.assertEqual(list(self.lua.eval('terrainCalls').values()), ['lake CalmLake'])


    def test_park_management_is_sent_immediately_and_replayed(self):
        self.lua.execute('api.world.GetWorldAPIs().park:SetParkName("Mein Park Ü")')
        self.assertEqual(self.records('sync:cmd|'), ['sync:cmd|!park.SetParkName(x4d65696e205061726b20c39c)'])
        self.local_build()
        part = self.records('sync:up|')[0].split('|')[1]
        entity = self.lua.eval(f'api.world.GetWorldAPIs().placement:PlacementIDToEntityID({part})')
        self.lua.execute(f'sync.Receive("M|1|g9|{part}|1")')
        self.tick(5)
        self.lua.execute(f'api.world.GetWorldAPIs().facilities:SetOpen({entity}, false)')
        self.assertEqual(self.records('sync:cmd|')[-1], 'sync:cmd|!facilities.SetOpen(eg9,b0)')
        self.lua.execute('api.world.GetWorldAPIs().facilities:SetOpen(424242, true)')
        self.assertEqual(len(self.records('sync:cmd|')), 2)
        self.lua.execute('sync.Receive("K|2|!facilities.SetOpen(eg9,b1);!park.SetParkName(x4869)")')
        self.tick(20)
        self.assertEqual(list(self.lua.eval('mgmt').values())[-2:], [f'open {entity} true', 'name Hi'])
        self.assertEqual(len(self.records('sync:cmd|')), 2)


    def test_path_segment_records_object_and_end_point_and_replays(self):
        self.lua.execute('''
            local apis = api.world.GetWorldAPIs()
            local Q, V, T = require("Quaternion"), require("Vector3"), require("TransformQ")
            -- A cancelled preview while the mouse moves, then the committed segment.
            for i = 1, 2 do
                local h = apis.editors:CreateUndoOperationsHierarchy()
                local mo = apis.volumes:CreateMoveObjectForVolumeSpline(h, T.FromOrPos(Q.Identity, V:new(10, 0, 20)), false, false, true, false)
                apis.volumes:SetSplinePathData(mo, "Path", "Path_01", "PathEdge_NoRails", 2, 1, 2, 5, true, {0.5}, {})
                mo:SetPosition(V:new(30, 0, 20 + i))
                local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
                if i == 1 then api.undo.CancelPreview(preview) else api.undo.CommitPreview(preview) end
            end
        ''')
        self.tick()
        cmds = self.records('sync:cmd|')
        self.assertEqual(len(cmds), 1)
        batch = cmds[0][len('sync:cmd|'):]
        self.assertEqual(batch, 'r1=volumes.CreateMoveObjectForVolumeSpline(@h,t10:0:20:0:0:0:1,b0,b0,b1,b0);'
                                'volumes.SetSplinePathData(@r1,sPath,sPath_01,sPathEdge_NoRails,n2,n1,n2,n5,b1,{1=n0.5},{});'
                                '@preview;@r1.SetPosition(v30:0:22)')
        self.lua.execute('paths = {}')
        self.lua.eval('function(b) sync.Receive("K|1|" .. b) end')(batch.replace('v30:0:22', 'v40:0:22'))
        self.tick(20)
        self.assertEqual(list(self.lua.eval('paths').values()), ['Path/Path_01/2/0.5 10,20 -> 40,22 merge=true'])
        self.assertEqual(len(self.records('sync:cmd|')), 1)


if __name__ == '__main__':
    unittest.main()


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class SyncRobustnessTests(SyncTests):
    def resize(self, part, scale):
        # The capture hook notes the new scale; position and rotation stay the same.
        self.lua.execute(f'''
            sync.NoteScale({part}, {scale})
            local h = api.world.GetWorldAPIs().editors:CreateUndoOperationsHierarchy()
            local e = h:StartEditingPart_Scenery(h:EditExistingPart({part}))
            e:SetTransform(require("TransformQ").FromOrPos(require("Quaternion").Identity, require("Vector3"):new(10, 5, 10)))
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            api.undo.CommitPreview(preview)
        ''')
        self.tick()

    def test_pure_resize_is_reported(self):
        self.local_build()
        part = self.records('sync:up|')[0].split('|')[1]
        self.resize(part, 2.5)
        ups = self.records('sync:up|')
        self.assertEqual(len(ups), 2)
        self.assertTrue(ups[-1].endswith('|2.5'), ups[-1])

    def test_remote_resize_back_to_one_is_applied(self):
        self.lua.execute('sync.Receive("U|1|g1|A|1|Fern|1|1|1|0|0|0|1|2")')
        self.tick(20)
        self.lua.execute('''
            local orig = game.newHierarchy
            scales = {}
            local H = getmetatable(orig()).__index
            local edit = H.EditExistingPart
            H.EditExistingPart = function(self, p)
                local e = edit(self, p)
                local set = e.SetScale
                e.SetScale = function(me, s) scales[#scales+1] = s; return set(me, s) end
                return e
            end
        ''')
        self.lua.execute('sync.Receive("U|2|g1|A|2|Fern|1|1|1|0|0|0|1|1")')
        self.tick(20)
        self.assertEqual(list(self.lua.eval('scales').values()), [1])
        self.assertEqual(self.records('sync:up|'), [])

    def test_failed_remote_change_is_retried_then_reported(self):
        self.lua.execute('fails = 0; local can = api.undo.CanCommitPreview; api.undo.CanCommitPreview = function(t) fails = fails + 1; return false end')
        self.lua.execute('sync.Receive("U|1|g1|A|1|Fern|1|1|1|0|0|0|1|1")')
        self.tick(20)
        self.assertEqual(len(self.records('sync:apply-error|')), 1)
        self.assertEqual(self.records('sync:desync|'), [])
        self.tick(80)
        self.assertEqual(len(self.records('sync:apply-error|')), 2)
        self.assertEqual(len(self.records('sync:desync|')), 1)
        self.assertIn('invalid-placement', self.records('sync:desync|')[0])

    def test_transient_failure_succeeds_on_retry(self):
        self.lua.execute('fails = 0; local can = api.undo.CanCommitPreview; api.undo.CanCommitPreview = function(t) fails = fails + 1; return fails > 1 end')
        self.lua.execute('sync.Receive("U|1|g1|A|1|Fern|1|1|1|0|0|0|1|1")')
        self.tick(100)
        self.assertEqual(len(self.records('sync:applied|')), 1)
        self.assertEqual(self.records('sync:desync|'), [])


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class FlatRideTests(unittest.TestCase):
    setUp = SyncTests.setUp
    records = SyncTests.records
    tick = SyncTests.tick

    def test_flat_ride_is_recorded_and_replayed_at_its_final_place(self):
        self.lua.execute('''
            local apis = api.world.GetWorldAPIs()
            local V, Q, T = require("Vector3"), require("Quaternion"), require("TransformQ")
            local token = apis.flatrides:CreateFlatRideEditToken("FR_Teacups")
            local h = apis.editors:CreateUndoOperationsHierarchy()
            local c = h:CreateCompositeObject({})
            apis.flatrides:AddFlatRide(h, c, token, 3, false)
            c:SetTransform(T.FromOrPos(Q.Identity, V:new(10, 0, 20)))
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            c:SetTransform(T.FromOrPos(Q.Identity, V:new(60, 0, 300)))
            api.undo.CommitPreview(preview)
        ''')
        self.tick()
        cmds = self.records('sync:cmd|')
        self.assertEqual(len(cmds), 1)
        batch = cmds[0][len('sync:cmd|'):]
        self.assertIn('r2=@composite', batch)
        self.assertIn('flatrides.AddFlatRide(@h,@r2,@r1,n3,b0)', batch)
        self.assertTrue(batch.endswith('@r2.SetTransform(t60:0:300:0:0:0:1)'), batch)
        self.lua.execute('rides = {}')
        shifted = batch.replace('SetTransform(t60:', 'SetTransform(t90:')
        self.lua.eval('function(b) sync.Receive("K|1|" .. b) end')(shifted)
        self.tick(20)
        self.assertEqual(list(self.lua.eval('rides').values()), ['FR_Teacups 90,300'])
        self.assertEqual(len(self.records('sync:cmd|')), 1)


    def test_deleted_rides_are_replayed_as_a_demolition(self):
        self.lua.execute('''
            local apis = api.world.GetWorldAPIs()
            local h = apis.editors:CreateUndoOperationsHierarchy()
            local deleted = {require("Editors.Scenery.Utils.SceneryUtils").DeleteMultiSelection_Core({41, 42}, apis, nil, h)}
            assert(deleted[2] == true)
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            api.undo.CommitPreview(preview)
        ''')
        self.tick()
        cmds = self.records('sync:cmd|')
        self.assertEqual(len(cmds), 1)
        batch = cmds[0][len('sync:cmd|'):]
        self.assertTrue(batch.startswith('r1=@demolish;'), batch)
        self.assertEqual(batch.count('flatrides.MoveFlatRide(@h,@r1,'), 2, batch)   # both rides, one record
        self.assertNotIn('SetTransform', batch)
        self.assertTrue(batch.endswith(';@r1.Destroy()'), batch)
        self.lua.execute('rides = {}')
        self.lua.eval('function(b) sync.Receive("K|1|" .. b) end')(batch)
        self.tick(20)
        demolished = list(self.lua.eval('rides').values())
        self.assertEqual(len(demolished), 2)
        self.assertTrue(all(r.startswith('demolished') for r in demolished), demolished)
        self.assertEqual(len(self.records('sync:cmd|')), 1)


    def test_ride_deleted_from_its_menu_is_replayed(self):
        # SelectAndEditComponent.DeleteFlatRide: edit token, RemoveFlatRide, preview, commit.
        self.lua.execute('''
            local apis = api.world.GetWorldAPIs()
            local token = apis.flatrides:GetFlatRideEditToken(41)
            local h = apis.editors:CreateUndoOperationsHierarchy()
            apis.flatrides:RemoveFlatRide(h, token)
            local wait, preview = api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            api.undo.CommitPreview(preview)
        ''')
        self.tick()
        cmds = self.records('sync:cmd|')
        self.assertEqual(len(cmds), 1)
        batch = cmds[0][len('sync:cmd|'):]
        self.assertIn('flatrides.RemoveFlatRide(@h,', batch)   # the token: in the game @r1 of GetFlatRideEditToken
        self.lua.execute('rides = {}')
        self.lua.eval('function(b) sync.Receive("K|1|" .. b) end')(batch)
        self.tick(20)
        self.assertEqual(len(self.lua.eval('rides')), 1)
        self.assertEqual(len(self.records('sync:cmd|')), 1)


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class RunTests(unittest.TestCase):
    """A friend's blueprint arrives as many scenery changes; they must not take one commit each."""
    setUp = SyncTests.setUp
    records = SyncTests.records
    tick = SyncTests.tick

    def part_count(self):
        return self.lua.eval('(function() local n=0; for _ in pairs(game.parts) do n=n+1 end; return n end)()')

    def receive(self, lines):
        self.lua.eval('function(t) sync.Receive(t) end')(chr(10).join(lines))

    def test_many_upserts_share_commits_and_deletes_too(self):
        self.receive([f'U|{i}|g{i}|Vici|1|Pipe|{i}|0|5|0|0|0|1|1' for i in range(1, 101)])
        self.tick(60)
        self.assertEqual(self.part_count(), 100)
        self.assertEqual(self.lua.eval('commits'), 2)       # 64 + 36
        self.assertEqual(self.records('sync:applied|')[-1], 'sync:applied|100')
        self.assertEqual(self.records('sync:up|'), [])
        self.receive([f'D|{100 + i}|g{i}|Vici|2' for i in range(1, 101)])
        self.tick(60)
        self.assertEqual(self.part_count(), 0)
        self.assertEqual(self.lua.eval('commits'), 4)
        self.assertEqual(self.records('sync:del|'), [])

    def test_same_object_twice_in_a_run_ends_at_the_last_state(self):
        self.receive(['U|1|g1|Vici|1|Pipe|1|0|5|0|0|0|1|1', 'U|2|g2|Vici|1|Pipe|2|0|5|0|0|0|1|1',
                      'U|3|g1|Vici|2|Pipe|40|0|5|0|0|0|1|1'])
        self.tick(30)
        self.assertEqual(self.part_count(), 2)
        xs = sorted(self.lua.eval('(function() local t={} for _, v in pairs(game.parts) do t[#t+1]=v.p:GetX() end return t end)()').values())
        self.assertEqual(xs, [2, 40])

    def test_one_refused_part_does_not_block_the_rest_of_the_run(self):
        # The fake refuses any commit that contains the resource "Bad".
        self.lua.execute('''
            local can = api.undo.CanCommitPreview
            api.undo.CanCommitPreview = function(token)
                for _, e in ipairs(token.cl.hierarchy.ops) do if e.resource == "Bad" then return false end end
                return true
            end
        ''')
        lines = [f'U|{i}|g{i}|Vici|1|{"Bad" if i == 7 else "Pipe"}|{i}|0|5|0|0|0|1|1' for i in range(1, 21)]
        self.receive(lines)
        self.tick(400)
        self.assertEqual(self.part_count(), 19)
        self.assertEqual(len(self.records('sync:run-split|')), 1)
        self.assertEqual(len(self.records('sync:desync|')), 1)
        self.assertIn('sync:desync|7|', self.records('sync:desync|')[0])
