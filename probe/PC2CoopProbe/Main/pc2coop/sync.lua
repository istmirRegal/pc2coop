-- Original MIT code. Live co-op scenery sync for PC2 build 26255360.
--
-- Capture: every editor commit passes api.undo.CommitPreview (wrapping it is proven to
-- work; wrapping the change-list userdata methods is not, the engine bypasses those
-- wrappers on ':' calls). After a local commit completes, the world is diffed: every
-- synced part is re-read (move/delete), and a sphere query around the placement focus
-- finds new parts. Results are reported as final states: "up" or "del".
--
-- Apply: remote state arrives in host order and is replayed through the editor API.
-- The game allows one preview at a time, so a remote change waits until the local
-- player holds nothing, and local editor code waits (yields) while a remote one runs.
--
-- Concurrency: every synced object carries a host revision. Changes are sent with the
-- revision they were based on; the host rejects stale ones and restores its state.
local global = _G
local Sync = {}
local Replay = global.require("pc2coop.replay")
local Rides = global.require("pc2coop.rides")
local Visitor = global.require("pc2coop.visitor")
local Recorder = global.require("pc2coop.recorder")
local World = global.require("pc2coop.world")
local shared = global.require("pc2coop.shared")

local emit = function() end
local active = false
local playerName = "?"
local applying = false
local wrapped = false
local pending = {}
local localToGlobal, globalToLocal, revision = {}, {}, {}
local known = {}          -- local part -> fingerprint of the last known state
local scaleHint = {}      -- local part -> scale seen by the placement capture hook
local inbound = {}        -- queued remote lines, host order
local lastSeq = 0
local task
local frames = 0
local reconcileCursor
local groupSize = 1
local grouped = false     -- the running task applies inbound[1..groupSize] in one commit
local MAX_RUN = 64        -- scenery changes applied together (a blueprint has 100+ parts)
local heldParts = {}      -- local part -> true: what the local player holds in the editor right now
local lastHold, lastHoldFrame = "", 0
local activityText = nil  -- what the editor tool says the player is doing ("baut Wege")
local remoteLocked = {}   -- gid -> name of the other player who holds that object
local MAX_HOLD_ITEMS = 8  -- ghosts shown to the others per held selection
local cmdSent = 0
local lastCmd = ""
local lastPresence, lastPresenceFrame = nil, 0
local raw = {}
local D
local baselineCount = -1
local NEW_PART_RADIUS = 96
local BASELINE_RADIUS = 6000

local function fmt(n) return global.string.format("%.6g", n) end

local function apis() return global.api.world.GetWorldAPIs() end

-- Part state read back from the committed world.
local function readPart(part)
    local w = apis()
    if not w.placement:PlacementPartExists(part) then return nil end
    local resource = w.placement:GetPartResourceName(part)
    local entity = w.placement:PlacementIDToEntityID(part)
    local transform = global.api.transform.CalculateWorldTransform(entity)
    local p, q = transform:GetPos(), transform:GetOr()
    return {resource = resource, x = p:GetX(), y = p:GetY(), z = p:GetZ(),
        qx = q:GetX(), qy = q:GetY(), qz = q:GetZ(), qw = q:GetW()}
end

-- Scale is not readable from the committed world; the capture hook notes it per part,
-- so a pure resize still changes the fingerprint.
local function fingerprint(s, part)
    if not s then return "gone" end
    return global.table.concat({s.resource, fmt(s.x), fmt(s.y), fmt(s.z),
        fmt(s.qx), fmt(s.qy), fmt(s.qz), fmt(s.qw), fmt(scaleHint[part] or 1)}, "|")
end

local function report(part)
    local ok, state = global.pcall(readPart, part)
    if not ok then emit("sync:read-error|" .. global.tostring(part) .. "|" .. global.tostring(state)); return end
    local gid = localToGlobal[part] or ""
    local print = fingerprint(state, part)
    if known[part] == print then return end
    if not state then
        if known[part] == nil then return end
        known[part] = nil
        emit("sync:del|" .. global.tostring(part) .. "|" .. gid .. "|" .. global.tostring(revision[gid] or 0))
        return
    end
    known[part] = print
    emit("sync:up|" .. global.tostring(part) .. "|" .. gid .. "|" .. global.tostring(revision[gid] or 0) .. "|"
        .. state.resource .. "|" .. fmt(state.x) .. "|" .. fmt(state.y) .. "|" .. fmt(state.z) .. "|"
        .. fmt(state.qx) .. "|" .. fmt(state.qy) .. "|" .. fmt(state.qz) .. "|" .. fmt(state.qw) .. "|"
        .. fmt(scaleHint[part] or 1))
end

local function partsAround(position, radius)
    local w, result, seen = apis(), {}, {}
    local entities = global.api.spatial.SphereQuery(position, radius, global.api.spatial.Flag_Scenery)
    for i = 1, #entities do
        local part = w.placement:EntityIDToPlacementID(entities[i])
        if part and not seen[part] then seen[part] = true; result[#result+1] = part end
    end
    return result
end

local function focusPosition()
    local feet = Visitor.Feet()
    if feet then return feet end
    local cam = apis().CameraModeManager
    local ok, focus = global.pcall(function() return cam:GetPlacementFocusPos() end)
    if ok and focus ~= nil and global.pcall(function() return focus:GetX() end)
        and (global.math.abs(focus:GetX()) + global.math.abs(focus:GetZ())) > 0.01 then return focus end
    -- (0,0,0): no placement tool - the middle of the view on the ground
    local okW, point = global.pcall(function() return global.require("pc2coop.world").FocusPoint() end)
    if okW and point then return point end
    local pos = cam:GetPosYPRZoom()
    return pos
end

-- Parts that exist when sync starts get deterministic ids, so friends who loaded the
-- same park file address the same objects.
local function baseline()
    local count = 0
    for _, part in global.ipairs(partsAround(focusPosition(), BASELINE_RADIUS)) do
        if not known[part] then
            local ok, state = global.pcall(readPart, part)
            if ok and state then
                known[part] = fingerprint(state, part)
                local gid = "P" .. global.tostring(part)
                localToGlobal[part], globalToLocal[gid] = gid, part
                count = count + 1
            end
        end
    end
    baselineCount = 0
    for _ in global.pairs(known) do baselineCount = baselineCount + 1 end
    emit("sync:baseline|" .. baselineCount .. "|new=" .. count)
end

local function diffAfterLocalCommit(focus)
    for part in global.pairs(known) do report(part) end
    if focus then
        for _, part in global.ipairs(partsAround(focus, NEW_PART_RADIUS)) do
            if not known[part] then report(part) end
        end
    end
end

-- Engine tables (api.undo, the hierarchy metatable) outlive this module instance: park
-- managers get a fresh module after each frontend transition. The wrappers are installed
-- once and dispatch to whichever instance registered last. The dispatcher lives on the
-- shared hierarchy metatable, which is engine-owned and proven writable.
local Handlers = {}

-- True when the caller is our own remote-apply task, not the player's editor code.
local function ours()
    return task ~= nil and global.coroutine.running() == task
end

function Handlers.WaitForRemote()
    if task and not ours() and global.coroutine.isyieldable() then
        while task do global.coroutine.yield() end
    end
end

function Handlers.BeforeCommit(token)
    if ours() then return nil end
    Recorder.Mark("commit")
    local batch = Replay.OnCommit(token)
    if batch then lastCmd = batch end
    if batch and active then
        cmdSent = cmdSent + 1
        -- Long batches (a path brush stroke) go in parts; replay puts them together.
        for _, part in global.ipairs(Replay.Split(batch)) do emit("sync:cmd|" .. part) end
    end
    if not active then return nil end
    local ok, focus = global.pcall(focusPosition)
    return {focus = ok and focus or nil}
end

function Handlers.AfterCommit(entry, results)
    if entry then entry.wait = results[1]; pending[#pending+1] = entry end
end

function Handlers.AfterUndo(wait)
    if ours() or not active then return end
    local ok, focus = global.pcall(focusPosition)
    pending[#pending+1] = {wait = wait, focus = ok and focus or nil}
end

local function installDispatcher()
    local hierarchy = apis().editors:CreateUndoOperationsHierarchy()
    local index = global.getmetatable(hierarchy).__index
    D = index.__PC2CoopSyncDispatch or {}
    index.__PC2CoopSyncDispatch = D
end

-- Parallel editing: the engine allows one preview. When a remote change arrives while
-- the local player holds a preview, the remote task cancels that preview, commits the
-- remote change and previews the player's change list again. The player's code keeps
-- its old token; every token-taking function translates it to the newest one. While
-- the task runs, the player's editor coroutines wait one frame at a time; calls from
-- outside a coroutine get the answer "still validating".
local localPreview            -- {changeList, token} of the player's current preview

function Handlers.Paused() return task ~= nil and not ours() end

function Handlers.OnCancel(token) if not ours() then Replay.OnCancel(token); Recorder.Mark("cancel") end end

function Handlers.OnLocalPreview(changeList, token)
    if ours() then return end
    Recorder.Mark("preview")
    Replay.OnPreview(changeList, token)
    localPreview = token ~= nil and {changeList = changeList, token = token} or nil
end

function Handlers.OnLocalPreviewEnd(token)
    if ours() or not localPreview then return end
    if Handlers.resolve(localPreview.token) == token then localPreview = nil end
end

local function installUndo()
    local undo = global.api.undo
    local d = D
    d.tokens = d.tokens or global.setmetatable({}, {__mode = "k"})
    local function resolve(token)
        local seen = 0
        while token ~= nil and d.tokens[token] ~= nil and seen < 64 do token = d.tokens[token]; seen = seen + 1 end
        return token
    end
    Handlers.resolve = resolve
    if not d.raw then
        local r = {}
        for _, name in global.ipairs({"PreviewChangeList", "CommitPreview", "CancelPreview", "IsPreviewingChangeList",
            "CanCommitPreview", "CanCommitPreviewApprox", "GetCommitFailReasons", "IsBusy"}) do
            r[name] = undo[name]
        end
        d.raw = r
        local function wait()
            local h = d.handlers
            if h then h.WaitForRemote() end
            return h and h.Paused()
        end
        undo.IsPreviewingChangeList = function(...)
            if wait() then return true end
            return r.IsPreviewingChangeList(...)
        end
        undo.PreviewChangeList = function(changeList, ...)
            wait()
            local results = global.table.pack(r.PreviewChangeList(changeList, ...))
            local h = d.handlers
            if h then global.pcall(h.OnLocalPreview, changeList, results[2]) end
            return global.table.unpack(results, 1, results.n)
        end
        undo.CommitPreview = function(token, ...)
            wait()
            token = resolve(token)
            local h = d.handlers
            local ok, entry = false, nil
            if h then ok, entry = global.pcall(h.BeforeCommit, token) end
            local results = global.table.pack(r.CommitPreview(token, ...))
            if h and ok then global.pcall(h.AfterCommit, entry, results) end
            if h then global.pcall(h.OnLocalPreviewEnd, token) end
            return global.table.unpack(results, 1, results.n)
        end
        undo.CancelPreview = function(token, ...)
            wait()
            token = resolve(token)
            local h = d.handlers
            if h then global.pcall(h.OnLocalPreviewEnd, token) end
            if h and h.OnCancel then global.pcall(h.OnCancel, token) end
            return r.CancelPreview(token, ...)
        end
        undo.CanCommitPreview = function(token, ...)
            if wait() then return nil end
            return r.CanCommitPreview(resolve(token), ...)
        end
        if r.CanCommitPreviewApprox then
            undo.CanCommitPreviewApprox = function(token, ...)
                if wait() then return false end
                return r.CanCommitPreviewApprox(resolve(token), ...)
            end
        end
        if r.GetCommitFailReasons then
            undo.GetCommitFailReasons = function(token, ...)
                if wait() then return {} end
                return r.GetCommitFailReasons(resolve(token), ...)
            end
        end
        undo.IsBusy = function(...)
            if wait() then return true end
            return r.IsBusy(...)
        end
        -- Undo and redo change the world without a commit; the result is diffed like one.
        for _, name in global.ipairs({"Undo", "Redo"}) do
            local original = undo[name]
            if global.type(original) == "function" then
                r[name] = original
                undo[name] = function(...)
                    local results = global.table.pack(original(...))
                    local h = d.handlers
                    if h and h.AfterUndo then global.pcall(h.AfterUndo, results[1]) end
                    return global.table.unpack(results, 1, results.n)
                end
            end
        end
    end
    raw = d.raw
    d.handlers = Handlers
end

-- Inside the remote task: set the player's preview aside, and afterwards restore it.
local function pauseLocalPreview()
    if not localPreview or not raw.IsPreviewingChangeList() then return nil end
    local undo = global.api.undo
    local token = Handlers.resolve(localPreview.token)
    local wait = raw.CancelPreview(token)
    for _ = 1, 600 do
        if undo.IsOperationComplete(wait) then return token end
        global.coroutine.yield()
    end
    global.error("timeout-pause")
end

local function resumeLocalPreview(oldToken)
    if not oldToken or not localPreview then return end
    local undo = global.api.undo
    local wait, token = raw.PreviewChangeList(localPreview.changeList)
    for _ = 1, 600 do
        if undo.IsOperationComplete(wait) then break end
        global.coroutine.yield()
    end
    D.tokens[oldToken] = token
    Replay.Remap(oldToken, token)
    emit("sync:preview-resumed")
end

-- A remote change touched the objects the player holds (it won the race at the host).
-- Re-previewing the player's change list would bring back parts that no longer exist, so
-- the player's token is pointed at an empty preview and the editor tool is left.
-- hit: the remote line that won ({kind, seq, gid, owner, ...}), named in "sync:hold-lost".
local function abandonLocalPreview(oldToken, hit)
    if not oldToken then return end
    local undo = global.api.undo
    local hierarchy = apis().editors:CreateUndoOperationsHierarchy()
    local changeList = hierarchy:GetFullUndoChangeList()
    local wait, token = raw.PreviewChangeList(changeList)
    for _ = 1, 600 do
        if undo.IsOperationComplete(wait) then break end
        global.coroutine.yield()
    end
    D.tokens[oldToken] = token
    Replay.OnCancel(oldToken)
    localPreview = {changeList = changeList, token = token}
    heldParts = {}
    emit("sync:hold-lost|" .. global.tostring(hit and hit[4] or "") .. "|" .. global.tostring(hit and hit[3] or ""))
    World.LeaveTool()
end

-- The first of these remote lines that changes an object the local player holds, or nil.
local function touchesHeld(lines)
    if global.next(heldParts) == nil then return nil end
    for _, f in global.ipairs(lines) do
        local part = (f[1] == "U" or f[1] == "D") and globalToLocal[f[3]]
        if part and heldParts[part] then return f end
    end
    return nil
end

-- Internal checks must never wait on our own remote task.
local function previewing() return (raw.IsPreviewingChangeList or global.api.undo.IsPreviewingChangeList)() end

function Sync.Init(logger) emit = logger end

function Sync.BaselineCount() return baselineCount end

function Sync.LocalPart(gid) return globalToLocal[gid] end

-- Entity ids differ between game sessions; the part id does not. Shared objects are
-- addressed by gid: assigned by the host, or "P<part>" for objects of the base park.
-- Rides and their stations have no placement part, and entity ids differ between games.
-- Every game builds the same ride at the same place, so the id is the rounded position:
-- F<x>_<y>_<z> for a ride, S<x>_<y>_<z> for a station (decimetres).
local function placeKey(prefix, entity)
    local p = global.api.transform.CalculateWorldTransform(entity):GetPos()
    local r = function(v) return global.math.floor(v * 10 + 0.5) end
    return prefix .. r(p:GetX()) .. "_" .. r(p:GetY()) .. "_" .. r(p:GetZ())
end

local function stations()
    local ok, list = global.pcall(function() return apis().ridestation:GetAllStations() end)
    return ok and global.type(list) == "table" and list or {}
end

local function findByPlace(gid)
    local prefix, x, y, z = global.string.match(gid, "^([FS])(%-?%d+)_(%-?%d+)_(%-?%d+)$")
    if not prefix then return nil end
    local want = {global.tonumber(x), global.tonumber(y), global.tonumber(z)}
    for _, station in global.pairs(stations()) do
        local entity = station
        if prefix == "F" then entity = apis().ridestation:GetRideEntityIDFromStationEntityID(station) end
        local ok, key = global.pcall(placeKey, prefix, entity)
        if ok then
            local a, b, c = global.string.match(key, "^%a(%-?%d+)_(%-?%d+)_(%-?%d+)$")
            -- One decimetre of tolerance against rounding at the grid edge.
            if global.math.abs(a - want[1]) <= 1 and global.math.abs(b - want[2]) <= 1 and global.math.abs(c - want[3]) <= 1 then
                return entity
            end
        end
    end
end

-- Shared id of a ride (coaster) for rides.lua: F<x>_<y>_<z> of the ride entity.
function Sync.RideKey(entity)
    local ok, key = global.pcall(placeKey, "F", entity)
    return ok and key or nil
end

function Sync.EntityToGid(entity)
    if global.type(entity) ~= "number" then return nil end
    local w = apis()
    local part = w.placement:EntityIDToPlacementID(entity)
    if part then return localToGlobal[part] or ("P" .. global.tostring(part)) end
    local okS, isStation = global.pcall(function() return w.ridestation:IsRideStation(entity) end)
    if okS and isStation then return placeKey("S", entity) end
    local okR, isRide = global.pcall(function() return w.rides:IsRide(entity) end)
    if okR and isRide then return placeKey("F", entity) end
    return nil
end

function Sync.GidToEntity(gid)
    local first = global.string.sub(gid, 1, 1)
    if first == "F" or first == "S" then return findByPlace(gid) end
    local part = globalToLocal[gid] or (first == "P" and global.tonumber(global.string.sub(gid, 2)))
    if not part or not apis().placement:PlacementPartExists(part) then return nil end
    return apis().placement:PlacementIDToEntityID(part)
end

-- Objects the other players hold right now: gid -> player name (from the host).
function Sync.SetRemoteLocks(locks) remoteLocked = locks or {} end
function Sync.RemoteLocks() return remoteLocked end
function Sync.HeldParts() return heldParts end
function Sync.GidOfPart(part) return localToGlobal[part] end
-- Test seam: the editor is not driven by tests, so they say what is held.
function Sync._SetHeld(parts) heldParts = parts or {} end

-- The player may only undo or redo a step of their own: the newest step on this game's
-- undo stack can be another player's change, and undoing that would tear down their work.
function Sync.MayUndo(isUndo)
    if not active then return true end
    local ok, data = global.pcall(function()
        local undo = global.api.undo
        if isUndo then return undo.GetCheckpointData() end
        return undo.GetUndoneCheckpointData()
    end)
    if ok and global.type(data) == "table" and data.pc2coopRemote then
        emit("sync:undo-blocked|" .. (isUndo and "undo" or "redo"))
        return false
    end
    return true
end

-- The object's state in this game's world: {res, p, q, s}, or nil when it is not here.
function Sync.StateOf(gid)
    local part = globalToLocal[gid] or (global.string.sub(gid, 1, 1) == "P" and global.tonumber(global.string.sub(gid, 2)))
    if not part then return nil end
    local ok, state = global.pcall(readPart, part)
    if not ok or not state then return nil end
    return {res = state.resource, p = {state.x, state.y, state.z}, q = {state.qx, state.qy, state.qz, state.qw},
        s = scaleHint[part] or 1}
end

local paused = false

-- Developer switch: stop applying remote changes (they queue up), capture continues.
function Sync.SetPaused(value) paused = value == true end

function Sync.Stats()
    local count = 0
    for _ in global.pairs(known) do count = count + 1 end
    return {active = active, known = count, baseline = baselineCount, inbound = #inbound, lastSeq = lastSeq, cmdSent = cmdSent, lastCmd = lastCmd}
end

-- The placement capture hook still sees scale, which the world readback cannot.
function Sync.NoteScale(part, scale)
    if global.type(scale) == "number" then scaleHint[part] = scale end
end

local function finalizeCommits()
    local i = 1
    while i <= #pending do
        local entry = pending[i]
        if entry.wait == nil or global.api.undo.IsOperationComplete(entry.wait) then
            global.table.remove(pending, i)
            if active then diffAfterLocalCommit(entry.focus) end
        else
            i = i + 1
        end
    end
end

-- Remote apply ---------------------------------------------------------------------

local function waitFor(predicate, label, limit)
    for _ = 1, limit or 1800 do
        if predicate() then return end
        global.coroutine.yield()
    end
    global.error("timeout-" .. label)
end

local function parse(line)
    local f = {}
    for field in global.string.gmatch(line, "[^|]+") do f[#f+1] = field end
    return f
end

local function number(v)
    local n = global.tonumber(v)
    if not n or n ~= n or global.math.abs(n) > 1e6 then global.error("bad-number") end
    return n
end

local function transformOf(op)
    local Quaternion, Vector3, TransformQ = global.require("Quaternion"), global.require("Vector3"), global.require("TransformQ")
    local q = Quaternion.Identity:WithX(op.qx):WithY(op.qy):WithZ(op.qz):WithW(op.qw)
    return TransformQ.FromOrPos(q, Vector3:new(op.x, op.y, op.z))
end

local function beginList(changeList)
    local undo = global.api.undo
    local wait, preview = undo.PreviewChangeList(changeList)
    waitFor(function() return undo.IsOperationComplete(wait) end, "preview")
    return preview
end

local function finishList(w, preview, settleFrames)
    local undo = global.api.undo
    for _ = 1, settleFrames or 0 do global.coroutine.yield() end
    waitFor(function() return not w.placement:HasPartsRequiringUpdate() end, "placement")
    local valid
    waitFor(function() valid = undo.CanCommitPreview(preview); return valid ~= nil end, "validation")
    if valid ~= true then
        global.pcall(function()
            local reasons = {}
            for k, v in global.pairs(undo.GetCommitFailReasons(preview) or {}) do
                reasons[#reasons+1] = global.tostring(k) .. "=" .. global.tostring(global.type(v) == "table" and (v.sReason or v.sType or #v) or v)
            end
            emit("sync:commit-refused|" .. global.table.concat(reasons, ","))
        end)
        local wait = undo.CancelPreview(preview)
        waitFor(function() return undo.IsOperationComplete(wait) end, "cancel")
        global.error("invalid-placement")
    end
    local wait = undo.CommitPreview(preview)
    waitFor(function() return undo.IsOperationComplete(wait) end, "commit")
    undo.Checkpoint({pc2coopRemote = true})
end

local function commitList(w, changeList) finishList(w, beginList(changeList), 0) end

local function commit(w, hierarchy) commitList(w, hierarchy:GetFullUndoChangeList()) end

local function applyUpsert(op)
    local w, api = apis(), global.api
    local hierarchy = w.editors:CreateUndoOperationsHierarchy()
    local part = globalToLocal[op.gid]
    local edit
    if part and w.placement:PlacementPartExists(part) then
        local token = api.entity.CreateRequestCompletionToken()
        local object = hierarchy:EditExistingPart(part, nil, token)
        waitFor(function() return api.entity.HaveRequestsCompleted(token) end, "edit")
        edit = hierarchy:StartEditingPart_Scenery(object)
    else
        local token = api.entity.CreateRequestCompletionToken()
        local object = hierarchy:CreateNewPart(op.resource, token)
        waitFor(function() return api.entity.HaveRequestsCompleted(token) end, "create")
        edit = hierarchy:StartEditingPart_Scenery(object)
        part = nil
    end
    edit:SetTransform(transformOf(op))
    -- Also when it is 1: an existing object may be scaled back to its default size.
    if op.scale then global.pcall(function() edit:SetScale(op.scale) end) end
    local ids = w.scenery:GetMoveObjectPartIDs(edit)
    global.assert(global.type(ids) == "table" and #ids >= 1, "no-part")
    part = part or ids[1]
    commit(w, hierarchy)
    globalToLocal[op.gid], localToGlobal[part] = part, op.gid
    scaleHint[part] = op.scale
    -- Let placement settle before recording, so engine snapping is not echoed back.
    for _ = 1, 5 do global.coroutine.yield() end
    known[part] = fingerprint(readPart(part), part)
end

-- A run of remote upserts in one change list and one commit, the way the game itself
-- places a blueprint. Later entries for the same object replace earlier ones.
-- A resource name from the network must look like one before it is given to the game.
local function resource(name)
    if global.type(name) ~= "string" or #name > 96 or not global.string.match(name, "^[%w_%.%-]+$") then
        global.error("bad-resource")
    end
    return name
end

local function applyUpserts(run)
    local w, api = apis(), global.api
    local hierarchy = w.editors:CreateUndoOperationsHierarchy()
    local last, items = {}, {}
    for i, f in global.ipairs(run) do last[f[3]] = i end
    for i, f in global.ipairs(run) do
        revision[f[3]] = global.tonumber(f[5])
        if last[f[3]] == i then
            local op = {gid = f[3], resource = resource(f[6]), x = number(f[7]), y = number(f[8]), z = number(f[9]),
                qx = number(f[10]), qy = number(f[11]), qz = number(f[12]), qw = number(f[13]), scale = number(f[14] or 1)}
            local part = globalToLocal[op.gid]
            local token = api.entity.CreateRequestCompletionToken()
            local object
            if part and w.placement:PlacementPartExists(part) then
                object = hierarchy:EditExistingPart(part, nil, token)
            else
                object, part = hierarchy:CreateNewPart(op.resource, token), nil
            end
            items[#items+1] = {op = op, part = part, object = object, token = token}
        end
    end
    for _, item in global.ipairs(items) do
        waitFor(function() return api.entity.HaveRequestsCompleted(item.token) end, "edit")
        local edit = hierarchy:StartEditingPart_Scenery(item.object)
        edit:SetTransform(transformOf(item.op))
        if item.op.scale then global.pcall(function() edit:SetScale(item.op.scale) end) end
        local ids = w.scenery:GetMoveObjectPartIDs(edit)
        global.assert(global.type(ids) == "table" and #ids >= 1, "no-part")
        item.part = item.part or ids[1]
    end
    commit(w, hierarchy)
    for _, item in global.ipairs(items) do
        globalToLocal[item.op.gid], localToGlobal[item.part] = item.part, item.op.gid
        scaleHint[item.part] = item.op.scale
    end
    -- Let placement settle before recording, so engine snapping is not echoed back.
    for _ = 1, 5 do global.coroutine.yield() end
    for _, item in global.ipairs(items) do known[item.part] = fingerprint(readPart(item.part), item.part) end
end

local function applyDeletes(run)
    local w = apis()
    local selection, count = w.scenery:CreateBuildingPartSet(), 0
    local parts = {}
    for _, f in global.ipairs(run) do
        revision[f[3]] = nil
        local part = globalToLocal[f[3]]
        if part and not parts[part] and w.placement:PlacementPartExists(part) then
            selection:Add(part)
            count = count + 1
        end
        if part then parts[part] = true end
    end
    if count > 0 then
        local hierarchy = w.editors:CreateUndoOperationsHierarchy()
        local edits = hierarchy:StartEditingParts_Scenery(hierarchy:DestroyExistingParts(selection))
        for _, edit in global.ipairs(edits) do edit:Destroy() end
        commit(w, hierarchy)
    end
    for _, f in global.ipairs(run) do
        local part = globalToLocal[f[3]]
        if part then localToGlobal[part], known[part] = nil, nil end
        globalToLocal[f[3]] = nil
    end
end

local function applyDelete(op)
    local w = apis()
    local part = globalToLocal[op.gid]
    if part and w.placement:PlacementPartExists(part) then
        local hierarchy = w.editors:CreateUndoOperationsHierarchy()
        local selection = w.scenery:CreateBuildingPartSet()
        selection:Add(part)
        local edits = hierarchy:StartEditingParts_Scenery(hierarchy:DestroyExistingParts(selection))
        for _, edit in global.ipairs(edits) do edit:Destroy() end
        commit(w, hierarchy)
    end
    if part then localToGlobal[part], known[part] = nil, nil end
    globalToLocal[op.gid] = nil
end

local function camera(f)
    local Vector3 = global.require("Vector3")
    apis().CameraModeManager:SetPosYPR(Vector3:new(number(f[2]), number(f[3]), number(f[4])),
        Vector3:new(number(f[5]), number(f[6]), 0))
end

-- U|seq|gid|owner|rev|resource|x|y|z|qx|qy|qz|qw|scale   D|seq|gid|owner|rev
-- M|seq|gid|part|rev (our own change accepted)             R|seq|gid|reason|who (rejected)
local function runOp(f)
    local kind, seq = f[1], global.tonumber(f[2])
    if kind == "U" then
        revision[f[3]] = global.tonumber(f[5])
        applyUpsert({gid = f[3], resource = resource(f[6]), x = number(f[7]), y = number(f[8]), z = number(f[9]),
            qx = number(f[10]), qy = number(f[11]), qz = number(f[12]), qw = number(f[13]), scale = number(f[14] or 1)})
    elseif kind == "D" then
        revision[f[3]] = nil
        applyDelete({gid = f[3]})
    elseif kind == "M" then
        local part = global.tonumber(f[4])
        if f[5] == "0" then
            -- Accepted delete of our own object.
            globalToLocal[f[3]], revision[f[3]] = nil, nil
            if part then localToGlobal[part] = nil end
        else
            globalToLocal[f[3]], localToGlobal[part], revision[f[3]] = part, f[3], global.tonumber(f[5])
        end
    elseif kind == "A" then
        -- Alias: after loading the host's park this part already is that object.
        local part = global.tonumber(f[4])
        if part and apis().placement:PlacementPartExists(part) then
            globalToLocal[f[3]], localToGlobal[part], revision[f[3]] = part, f[3], global.tonumber(f[5])
            known[part] = fingerprint(readPart(part), part)
        end
    elseif kind == "Y" then
        -- A ride (coaster) as a blueprint file: swap ours for it (rides.lua).
        local w = apis()
        Rides.Apply(f[3], f[4], f[5], {
            waitFor = function(predicate, label) waitFor(predicate, label, 7200) end,
            commit = function(changeList) commitList(w, changeList) end})
    elseif kind == "R" then
        -- f[5]: who was in the way (from the host; the session cleans it before showing it).
        emit("sync:rejected|" .. global.tostring(f[3]) .. "|" .. global.tostring(f[4]) .. "|" .. global.tostring(f[5] or ""))
    end
    lastSeq = seq
    emit("sync:applied|" .. global.tostring(seq))
end

function Sync.Receive(message)
    for line in global.string.gmatch(message, "[^\n]+") do
        local f = parse(line)
        if f[1] == "S" then
            playerName = f[2] or playerName
            if not active then
                active = true
                global.pcall(baseline)
                global.pcall(Rides.Baseline)
            end
            emit("sync:started|" .. playerName)
        elseif f[1] == "X" then
            active = false; emit("sync:stopped")
        elseif f[1] == "C" then
            global.pcall(camera, f)
        else
            local seq = global.tonumber(f[2])
            if seq and seq > lastSeq and (#inbound == 0 or seq > inbound[#inbound].seq) then
                inbound[#inbound+1] = {seq = seq, fields = f}
            end
        end
    end
end

-- Presence and reconciliation ----------------------------------------------------------

local function activity()
    if applying then return "empfaengt" end
    local visiting = Visitor.Activity()
    if visiting then return visiting end
    if activityText then return activityText end
    if previewing() then return "baut" end
    return "schaut"
end

local function two(n) return global.string.format("%.2f", n) end

-- What the player holds in the editor: reported as "sync:hold|label|gids|items" a few times
-- per second, "sync:hold|" when it is put down. gids = shared objects being edited (locked
-- for the others), items = "resource,x,y,z,qx,qy,qz,qw,scale;..." for their ghost view;
-- a leading "!" marks something that must not be shown as a model (rides).
local function hold()
    local info = World.Activity()
    activityText = info.text and global.string.gsub(info.text, "[|,;\n]", " ") or nil
    local held = info.held
    local line, parts = "", {}
    if held then
        local w = apis()
        local gids, items = {}, {}
        for i, part in global.ipairs(held.parts) do
            if i > MAX_RUN then break end
            parts[part] = true
            local gid = localToGlobal[part]
            if gid then gids[#gids+1] = gid end
            if #items < MAX_HOLD_ITEMS then
                global.pcall(function()
                    local t = global.api.transform.CalculateWorldTransform(w.placement:PlacementIDToEntityID(part))
                    local pos, q = t:GetPos(), t:GetOr()
                    items[#items+1] = global.table.concat({w.placement:GetPartResourceName(part), two(pos:GetX()), two(pos:GetY()),
                        two(pos:GetZ()), fmt(q:GetX()), fmt(q:GetY()), fmt(q:GetZ()), fmt(q:GetW()), two(held.scale or 1)}, ",")
                end)
            end
        end
        if #items == 0 then
            local name = global.string.gsub(global.tostring(held.resource or "?"), "[^%w_%.%-]", "")
            items[1] = global.table.concat({"!" .. name, two(held.x), two(held.y), two(held.z), fmt(held.qx), fmt(held.qy),
                fmt(held.qz), fmt(held.qw), two(held.scale or 1)}, ",")
        end
        -- Someone else already works on one of these objects: step back at once.
        for _, gid in global.ipairs(gids) do
            if remoteLocked[gid] then
                emit("sync:hold-denied|" .. global.tostring(remoteLocked[gid]) .. "|" .. gid)
                heldParts = {}
                World.LeaveTool()
                return
            end
        end
        local label = global.string.gsub(global.tostring(held.resource or global.string.match(items[1], "^!?([^,]*)") or "?"), "[|,;]", "")
        line = label .. "|" .. global.table.concat(gids, ",") .. "|" .. global.table.concat(items, ";")
    else
        -- In the track editor: the ride is locked for the others while it is open here.
        local keys = Rides.Editing()
        for _, key in global.ipairs(keys) do
            if remoteLocked[key] then
                emit("sync:hold-denied|" .. global.tostring(remoteLocked[key]) .. "|" .. key)
                Rides.Abandon()
                World.LeaveTool()
                return
            end
        end
        if #keys > 0 then line = "Achterbahn|" .. global.table.concat(keys, ",") .. "|" end
    end
    heldParts = parts
    if line ~= lastHold or (line ~= "" and frames - lastHoldFrame >= 60) then
        lastHold, lastHoldFrame = line, frames
        emit("sync:hold|" .. line)
    end
end

local function presence()
    local cam = apis().CameraModeManager
    local pos, ypr, zoom = cam:GetPosYPRZoom()
    local okFocus, focus = global.pcall(focusPosition)
    if not okFocus or focus == nil then focus = pos end
    local short = function(n) return global.string.format("%.1f", n) end
    local line = "sync:pres|" .. short(pos:GetX()) .. "|" .. short(pos:GetY()) .. "|" .. short(pos:GetZ()) .. "|"
        .. fmt(ypr:GetX()) .. "|" .. fmt(ypr:GetY()) .. "|" .. fmt(zoom or 0) .. "|"
        .. global.tostring(cam:GetCurrentModeName()) .. "|" .. activity() .. "|"
        .. short(focus:GetX()) .. "|" .. short(focus:GetY()) .. "|" .. short(focus:GetZ())
    if line ~= lastPresence or frames - lastPresenceFrame >= 120 then
        lastPresence, lastPresenceFrame = line, frames
        emit(line)
    end
end

-- Undo/redo of a remote object can bypass a commit diff. A slow sweep reports drift.
local function reconcile()
    if previewing() or raw.IsBusy() then return end
    for _ = 1, 8 do
        local part = global.next(known, reconcileCursor)
        reconcileCursor = part
        if part == nil then return end
        report(part)
    end
end

function Sync.Tick()
    frames = frames + 1
    if not wrapped then
        local ok, failure = global.pcall(function()
            installDispatcher(); installUndo()
            Replay.Init(emit, ours, function(call)
                if active then cmdSent = cmdSent + 1; emit("sync:cmd|" .. call) end
            end, Sync.EntityToGid, Sync.GidToEntity)
            Replay.Install()
            Rides.Init(emit, ours, Sync.RideKey, Sync.GidToEntity)
            Rides.Install()
        end)
        wrapped = true
        emit(ok and "sync:hooks-installed" or ("sync:hook-error|" .. global.tostring(failure)))
        shared.undoGuard = Sync.MayUndo
        global.pcall(function() playerName = global.api.player.GetPlayerName() or playerName end)
        emit("sync:ready|" .. global.tostring(playerName))
    end
    finalizeCommits()
    if active then
        -- Not while any preview runs: ghosts of rides being placed or moved are entities too.
        local okR, failureR = global.pcall(Rides.Tick, task ~= nil or paused or previewing())
        if not okR then emit("rides:tick-error|" .. global.tostring(failureR)) end
    end
    if task then
        local ok, failure = global.coroutine.resume(task)
        if not ok then
            local head = inbound[1]
            local seq = head and head.seq or 0
            if grouped and head and head.fields[1] ~= "K" and groupSize > 1 then
                -- One part of the run was refused: apply them one by one, so only that part fails.
                emit("sync:run-split|" .. global.tostring(seq) .. "|" .. groupSize .. "|" .. global.tostring(failure))
                for i = 1, groupSize do if inbound[i] then inbound[i].single = true end end
                task, applying, grouped = nil, false, false
                return
            end
            emit("sync:apply-error|" .. global.tostring(seq) .. "|" .. global.tostring(failure))
            if head and not head.retried then
                -- Often transient (placement still settling, a validation race): retry once.
                head.retried, head.after = true, frames + 60
                task, applying, grouped = nil, false, false
                return
            end
            -- Dropping it means this game no longer matches the host: say so, never silently.
            emit("sync:desync|" .. global.tostring(seq) .. "|" .. global.tostring(failure))
            for _ = 1, global.math.max(1, groupSize) do
                if inbound[1] then lastSeq = inbound[1].seq; global.table.remove(inbound, 1) end
            end
            task, applying, grouped = nil, false, false
        elseif global.coroutine.status(task) == "dead" then
            if grouped then
                for _ = 1, groupSize do
                    lastSeq = inbound[1].seq
                    global.table.remove(inbound, 1)
                end
                emit("sync:applied|" .. global.tostring(lastSeq))
            else
                global.table.remove(inbound, 1)
            end
            task, applying, grouped = nil, false, false
        end
    elseif active and not paused and #inbound > 0 and not raw.IsBusy()
        and (not inbound[1].after or frames >= inbound[1].after) then
        local fields = inbound[1].fields
        applying = true
        if fields[1] == "K" then
            -- Consecutive replay batches (e.g. a terrain brush stroke) share one commit.
            local batches = {}
            while #batches < 20 and inbound[#batches + 1] and inbound[#batches + 1].fields[1] == "K" do
                batches[#batches + 1] = inbound[#batches + 1].fields[3]
            end
            groupSize, grouped = #batches, true
            task = global.coroutine.create(function()
                local paused = pauseLocalPreview()
                local w = apis()
                local ok, failure = global.pcall(Replay.Apply, batches,
                    function(changeList) commitList(w, changeList) end,
                    beginList,
                    function(preview) finishList(w, preview, 10) end)
                resumeLocalPreview(paused)
                if not ok then global.error(failure, 0) end
            end)
        elseif (fields[1] == "U" or fields[1] == "D") and not inbound[1].single then
            -- Consecutive scenery changes of one kind (a friend's blueprint) share one commit.
            local kind, run = fields[1], {}
            while #run < MAX_RUN and inbound[#run + 1] and inbound[#run + 1].fields[1] == kind
                and not inbound[#run + 1].single do
                run[#run + 1] = inbound[#run + 1].fields
            end
            groupSize, grouped = #run, true
            task = global.coroutine.create(function()
                local paused = pauseLocalPreview()
                local hit = touchesHeld(run)
                local ok, failure = global.pcall(kind == "U" and applyUpserts or applyDeletes, run)
                if hit then abandonLocalPreview(paused, hit) else resumeLocalPreview(paused) end
                if not ok then global.error(failure, 0) end
            end)
        else
            groupSize, grouped = 1, false
            task = global.coroutine.create(function()
                local paused = pauseLocalPreview()
                local hit = touchesHeld({fields})
                local ok, failure = global.pcall(runOp, fields)
                if hit then abandonLocalPreview(paused, hit) else resumeLocalPreview(paused) end
                if not ok then global.error(failure, 0) end
            end)
        end
    end
    if active and frames % 8 == 0 then global.pcall(hold); global.pcall(presence) end
    if active and frames % 60 == 30 then global.pcall(reconcile) end
end

function Sync.Stop()
    if D and D.handlers == Handlers then D.handlers = nil end
    active, task, applying, inbound, pending, grouped = false, nil, false, {}, {}, false
    localToGlobal, globalToLocal, revision, known, scaleHint, lastSeq, wrapped = {}, {}, {}, {}, {}, 0, false
    heldParts, remoteLocked, lastHold, activityText = {}, {}, "", nil
    shared.undoGuard = nil
    Replay.Stop()
    Rides.Stop()
    emit("sync:not-ready")
end

return Sync
