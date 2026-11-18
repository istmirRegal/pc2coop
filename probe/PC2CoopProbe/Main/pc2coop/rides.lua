-- Original MIT code. Rides built with the track editor (coasters, track rides) are not
-- replayed call by call: the track editor works with selections, drag handles and live
-- previews. Instead, a changed ride is saved as a blueprint file (the game's own
-- SaveBlueprintToFile) and sent; the others swap their copy for it in one change list
-- (old track removed, blueprint added). A blueprint loads at the place it was saved from,
-- so the ride ends up exactly where it is for the author (checked in game: position,
-- rotation, stations and the ride name are the same).
--
-- What changed is found two ways: the track editor tells the ride when editing starts and
-- ends (trackedrides:NotifyTrackedRideOfTrackEdit), and a scan compares every tracked
-- ride's place and size every second (moves, deletes, undo, rides from blueprints).
--
-- Water slides hang on a flume platform: the platform with all its slides is one unit
-- (its key is the platform's place), as the game's own blueprint save does it.
--
-- Wire (through the session, host orders): ride|<old key>|<new key>|<file>
--   old "-": the ride is new.  new "-" and file "-": the ride was removed.
-- Keys are the shared ride ids of sync (F<x>_<y>_<z>, decimetres of the ride entity).
local global = _G
local Rides = {}

local emit = function() end
local ours = function() return false end
local keyOf = function() return nil end
local findRide = function() return nil end
local frames = 0
local seq = 0
local tag = "0"
local installed = false
local known = nil          -- ride entity -> {key, print} of the last state everyone has
local editing = {}         -- ride entity -> key when the local player opened the track editor
local jobs = {}            -- rides to send: {ride, old, after}
local job                  -- running save coroutine
local ready = {}           -- file -> true when it is complete here
local mine = {}            -- files this game wrote or received, oldest first
local settle = {}          -- key -> frame: a remote change there is still settling, take it as is
local candidates = {}      -- ride -> true: new since the last scan; counts if still there next time
local vanished = {}        -- ride -> true: missing since the last scan; removed if still gone next time
local SETTLE_FRAMES = 180
local knownFlat = nil      -- flat ride entities seen in the last scan
local blueprintAt = -100000 -- frame of the last local blueprint placement
local SCAN_FRAMES = 45
local KEEP_FILES = 40

local function apis() return global.api.world.GetWorldAPIs() end

local function manager()
    return global.api.game.GetEnvironment():RequireInterface("Interfaces.IParkLoadSaveManager")
end

local function stations()
    local ok, list = global.pcall(function() return apis().ridestation:GetAllStations() end)
    return ok and global.type(list) == "table" and list or {}
end

local function isTracked(ride)
    local ok, value = global.pcall(function() return apis().rides:IsTrackedRide(ride) end)
    return ok and value == true
end

local function alive(ride)
    local ok, value = global.pcall(function() return apis().rides:IsRide(ride) end)
    return ok and value == true
end

-- Place and size of a tracked ride: changes when the track is edited, moved or undone.
local function printOf(ride)
    local ok, text = global.pcall(function()
        local a, b = global.api.track.ComputeApproxLocalAABB(global.api.track.GetTrackHolder(ride))
        local n = 0
        for _, s in global.ipairs(stations()) do
            if apis().ridestation:GetRideEntityIDFromStationEntityID(s) == ride then n = n + 1 end
        end
        local r = function(v) return global.math.floor(v + 0.5) end
        -- Name and trains: renamed rides and changed trains go out as well.
        local okN, name = global.pcall(function() return apis().rides:GetRideName(ride) end)
        local okI, info = global.pcall(function() return apis().rides:GetRideInfo(ride) end)
        return global.string.format("%d,%d,%d,%d,%d,%d,%d,%s,%s", r(a:GetX()), r(a:GetY()), r(a:GetZ()), r(b:GetX()), r(b:GetY()), r(b:GetZ()), n,
            global.tostring(okN and name or ""), global.tostring(okI and global.type(info) == "table" and info.numTrains or ""))
    end)
    return ok and text or "?"
end

-- The flume platform a water slide hangs on, or nil.
local function platformOf(ride)
    local ok, slide = global.pcall(function() return apis().ridestation:IsWaterSlide(ride) end)
    if not ok or not slide then return nil end
    local okP, platform = global.pcall(function() return apis().flumes:GetPlatformForAttachedRide(ride) end)
    return okP and platform or nil
end

-- Units that travel as one file: a tracked ride, or a flume platform with its slides.
local function current()
    local now, slides, seen = {}, {}, {}
    for _, s in global.ipairs(stations()) do
        local ok, ride = global.pcall(function() return apis().ridestation:GetRideEntityIDFromStationEntityID(s) end)
        if ok and ride and not seen[ride] and isTracked(ride) then
            seen[ride] = true
            local platform = platformOf(ride)
            if platform then
                slides[platform] = slides[platform] or {}
                global.table.insert(slides[platform], ride)
            else
                local key = keyOf(ride)
                if key then now[ride] = {key = key, print = printOf(ride)} end
            end
        end
    end
    for platform, list in global.pairs(slides) do
        local key = keyOf(platform)
        if key then
            local prints = {}
            for _, ride in global.ipairs(list) do prints[#prints+1] = printOf(ride) end
            global.table.sort(prints)
            -- Only calls checked in game here: a wrong argument to an engine call can end the game.
            now[platform] = {key = key, print = #list .. ":" .. global.table.concat(prints, ";"),
                slides = list}
        end
    end
    return now
end

-- The unit at a key, one decimetre of tolerance against rounding at the grid edge.
local function findUnit(key)
    local x, y, z = global.string.match(key or "", "^F(%-?%d+)_(%-?%d+)_(%-?%d+)$")
    if not x then return nil end
    x, y, z = global.tonumber(x), global.tonumber(y), global.tonumber(z)
    for entity, state in global.pairs(current()) do
        local a, b, c = global.string.match(state.key, "^F(%-?%d+)_(%-?%d+)_(%-?%d+)$")
        if a and global.math.abs(a - x) <= 1 and global.math.abs(b - y) <= 1 and global.math.abs(c - z) <= 1 then
            return entity, state
        end
    end
end

local function queue(ride, old, flat)
    for _, j in global.ipairs(jobs) do
        if j.ride == ride then j.after = frames + 20; return end
    end
    jobs[#jobs+1] = {ride = ride, old = old, after = frames + 20, flat = flat}
end

-- Flat rides: placed, moved and deleted through the replay; only those that came out of a
-- blueprint travel as files (the replay never saw them being built).
local function flats()
    local out = {}
    for _, s in global.ipairs(stations()) do
        local ok, ride = global.pcall(function() return apis().ridestation:GetRideEntityIDFromStationEntityID(s) end)
        if ok and ride and not isTracked(ride) and alive(ride) then out[ride] = true end
    end
    return out
end

local function remember(file)
    mine[#mine+1] = file
    while #mine > KEEP_FILES do
        local old = global.table.remove(mine, 1)
        ready[old] = nil
        emit("sync:ridedel|" .. old)
    end
end

function Rides.Init(logger, oursFunction, toKey, fromKey)
    emit = logger or emit
    ours = oursFunction or ours
    keyOf = toKey or keyOf
    findRide = fromKey or findRide
end

-- Our Steam id: makes file names unique per author.
function Rides.SetTag(value)
    local digits = global.string.match(global.tostring(value or ""), "^(%d+)$")
    if digits and #digits <= 20 then tag = digits end
end

-- Track editor: editing starts (true) and ends (false) for a track entity.
local function onTrackEdit(trackEntity, bEditing)
    if ours() then return end
    local ride = trackEntity
    if not isTracked(ride) then
        for _, s in global.ipairs(stations()) do
            local r = apis().ridestation:GetRideEntityIDFromStationEntityID(s)
            local okE, e = global.pcall(function() return global.api.track.GetTrackEntity(global.api.track.GetTrackHolder(r)) end)
            if okE and e == trackEntity then ride = r; break end
        end
    end
    ride = platformOf(ride) or ride
    if bEditing then
        local was = known and known[ride]
        editing[ride] = was and was.key or keyOf(ride) or "-"
        emit("rides:editing|" .. global.tostring(editing[ride]))
    elseif editing[ride] then
        queue(ride, editing[ride])
        editing[ride] = nil
    end
end

function Rides.Install()
    if installed then return true end
    local trackedrides = apis().trackedrides
    local original = trackedrides and trackedrides.NotifyTrackedRideOfTrackEdit
    if global.type(original) ~= "function" then emit("rides:no-track-hook"); return false end
    -- The blueprint tool calls this after its commit: its flat rides go out as files.
    local complete = trackedrides.CompleteBlueprintSerialisationLoad
    if global.type(complete) == "function" then
        trackedrides.CompleteBlueprintSerialisationLoad = function(self, ...)
            if not ours() then blueprintAt = frames end
            return complete(self, ...)
        end
    end
    trackedrides.NotifyTrackedRideOfTrackEdit = function(self, trackEntity, bEditing, ...)
        local ok, failure = global.pcall(onTrackEdit, trackEntity, bEditing)
        if not ok then emit("rides:hook-error|" .. global.tostring(failure)) end
        return original(self, trackEntity, bEditing, ...)
    end
    installed = true
    emit("rides:installed")
    return true
end

-- Another player holds the ride: the editor is closed without sending anything.
function Rides.Abandon()
    for ride in global.pairs(editing) do editing[ride] = nil end
end

-- Keys of the rides the local player has open in the track editor (locked for others).
function Rides.Editing()
    local keys = {}
    for _, key in global.pairs(editing) do if key ~= "-" then keys[#keys+1] = key end end
    return keys
end

local function send(j)
    local state = current()[j.ride]
    if j.flat then
        local key = alive(j.ride) and keyOf(j.ride)
        state = key and {key = key} or nil
        if not state then return end
    end
    if not state then
        if j.old ~= "-" then emit("sync:ride|" .. j.old .. "|-|-") end
        if known then known[j.ride] = nil end
        return
    end
    local key = state.key
    seq = seq + 1
    local file = "pc2coop-ride-" .. tag .. "-" .. seq .. ".blueprint"
    local selection = apis().worldserialisation:CreateSaveSelection()
    selection:AddEntityID(j.ride)
    for _, slide in global.ipairs(state.slides or {}) do selection:AddEntityID(slide) end
    local ok, failure = manager():SaveBlueprintToFile("/run/" .. file, selection, true)
    if not ok then emit("rides:save-failed|" .. global.tostring(failure)); return end
    ready[file] = true
    remember(file)
    if known and not j.flat then known[j.ride] = state end
    emit("sync:ride|" .. j.old .. "|" .. key .. "|" .. file)
end

local function settling(key) return key and settle[key] and frames < settle[key] end

-- What everyone has: taken when the session starts here (all games have the same park then).
function Rides.Baseline()
    known, candidates, vanished = current(), {}, {}
    knownFlat = flats()
end

-- A new or vanished ride counts only when two scans in a row agree: tools briefly show
-- ghosts of rides being placed (seen in game between two previews).
local function scan()
    local now = current()
    local flatNow = flats()
    if knownFlat and frames - blueprintAt < 600 then
        for ride in global.pairs(flatNow) do
            if not knownFlat[ride] then queue(ride, "-", true) end
        end
    end
    knownFlat = flatNow
    if not known then known = now; return end
    local nextKnown, nextCandidates, nextVanished = {}, {}, {}
    for ride, state in global.pairs(now) do
        local was = known[ride]
        if editing[ride] then
            nextKnown[ride] = was
        elseif settling(state.key) then
            nextKnown[ride] = state
        elseif was then
            if was.key ~= state.key or was.print ~= state.print then queue(ride, was.key) end
            nextKnown[ride] = state
        elseif candidates[ride] then
            queue(ride, "-")
            nextKnown[ride] = state
        else
            nextCandidates[ride] = true
        end
    end
    for ride, was in global.pairs(known) do
        if not now[ride] and not editing[ride] and not settling(was.key) then
            local waiting = false
            for _, j in global.ipairs(jobs) do if j.ride == ride then waiting = true end end
            if waiting then
                -- its job finds it gone and says so
            elseif vanished[ride] then
                emit("sync:ride|" .. was.key .. "|-|-")
            else
                nextVanished[ride], nextKnown[ride] = true, was
            end
        end
    end
    known, candidates, vanished = nextKnown, nextCandidates, nextVanished
end

-- Every frame while a session runs. busy: a remote change is being applied right now.
function Rides.Tick(busy)
    frames = frames + 1
    if job then
        local ok, failure = global.coroutine.resume(job)
        if not ok then emit("rides:send-error|" .. global.tostring(failure)); job = nil
        elseif global.coroutine.status(job) == "dead" then job = nil end
        return
    end
    if busy then return end
    if jobs[1] and frames >= jobs[1].after then
        local j = global.table.remove(jobs, 1)
        job = global.coroutine.create(function() send(j) end)
        return
    end
    if frames % SCAN_FRAMES == 0 then
        local ok, failure = global.pcall(scan)
        if not ok then emit("rides:scan-error|" .. global.tostring(failure)) end
    end
end

-- A file arrived completely (event of the DLL).
function Rides.FileReady(file)
    if not ready[file] then ready[file] = true; remember(file) end
end

function Rides.IsReady(file) return file == "-" or ready[file] == true end

function Rides.ValidKey(key)
    return key == "-" or (global.string.match(key or "", "^F%-?%d+_%-?%d+_%-?%d+$") ~= nil and #key <= 40)
end

function Rides.ValidFile(file)
    return file == "-" or (global.string.match(file or "", "^pc2coop%-ride%-%d+%-%d+%.blueprint$") ~= nil and #file <= 64)
end

-- Removed with the game's own delete of a selection (SceneryUtils), into the same change
-- list as the new version: tracked rides, slides with their flume platform, flat rides.
local function removeUnit(h, entity, state)
    local flat, tracked, platforms = {}, {}, {}
    if state and state.slides then platforms, tracked = {entity}, state.slides
    elseif isTracked(entity) then tracked = {entity}
    else flat = {entity} end
    local selection = {SelectionCategories_Buildings = "b", SelectionCategories_Facilities = "f",
        SelectionCategories_Scenery = "s", SelectionCategories_FlatRides = "r", SelectionCategories_TrackedRides = "t",
        SelectionCategories_FlumePlatforms = "p"}
    local counts = {r = #flat, t = #tracked, p = #platforms}
    function selection:CountCategory(c) return counts[c] or 0 end
    function selection:GetFlatRide(i) return flat[i] end
    function selection:GetTrackRide(i) return tracked[i] end
    function selection:GetFlumePlatform(i) return platforms[i] end
    function selection:GetVolumeChunksTable() return {} end
    function selection:GetTrackRidesTable() return tracked end
    function selection:GetBuildingsTable() return {} end
    local scenario = {HandlePreventDeletingRidesScenarioParam = function() return false end}
    global.require("Editors.Scenery.Utils.SceneryUtils").DeleteMultiSelection_Core(selection, apis(), scenario, h)
end

-- Remote change, inside the sync task (ours() is true there). tools: waitFor(fn, label),
-- commit(changeList) previews and commits like every other remote change.
function Rides.Apply(old, new, file, tools)
    global.assert(Rides.ValidKey(old) and Rides.ValidKey(new) and Rides.ValidFile(file), "bad-ride-line")
    if file ~= "-" then tools.waitFor(function() return ready[file] == true end, "ride-file") end
    local w = apis()
    local oldRide, oldState
    if old ~= "-" then oldRide, oldState = findUnit(old) end
    if file == "-" and not oldRide then emit("rides:gone|" .. old); return end
    if oldRide and oldState and oldState.slides and file ~= "-" then
        -- A flume platform only makes room for the new one once its removal is committed
        -- (one change list: bObstructed, checked in game). Two steps for platforms.
        local first = w.editors:CreateUndoOperationsHierarchy()
        removeUnit(first, oldRide, oldState)
        tools.commit(first:GetFullUndoChangeList())
        oldRide = nil
    end
    if file ~= "-" then
        local ok, failure = manager():LoadBlueprintFromFile("/run/" .. file)
        global.assert(ok, "ride-load:" .. global.tostring(failure))
    end
    local h = w.editors:CreateUndoOperationsHierarchy()
    if file ~= "-" then tools.waitFor(function() return h:IsLoadedBlueprintReadyForEditing() end, "ride-ready") end
    if oldRide then removeUnit(h, oldRide, oldState) end
    if file ~= "-" then
        local composite = h:CreateCompositeObject({})
        h:AddBlueprintToCompositeObject(composite)
    end
    local before = {}
    for _, s in global.ipairs(stations()) do
        global.pcall(function() before[w.ridestation:GetRideEntityIDFromStationEntityID(s)] = true end)
    end
    tools.commit(h:GetFullUndoChangeList())
    if file ~= "-" then
        -- As the game's blueprint placement does after its commit.
        global.pcall(function() w.trackedrides:CompleteBlueprintSerialisationLoad() end)
        for _, s in global.ipairs(stations()) do
            global.pcall(function()
                local ride = w.ridestation:GetRideEntityIDFromStationEntityID(s)
                if not before[ride] and w.ridestation:IsWaterSlide(ride) then w.flumes:AttachFlumeToPlatform(ride) end
            end)
        end
    end
    -- What everyone has now: not a local change to send back.
    local now = current()
    for ride in global.pairs(editing) do now[ride] = known and known[ride] end
    known = now
    knownFlat = flats()
    -- The new ride may still settle for a few frames (size, entity): not a local change.
    if old ~= "-" then settle[old] = frames + SETTLE_FRAMES end
    if new ~= "-" then settle[new] = frames + SETTLE_FRAMES end
    emit("rides:applied|" .. old .. "|" .. new)
end

function Rides.Stop()
    for _, file in global.ipairs(mine) do emit("sync:ridedel|" .. file) end
    known, editing, jobs, job, ready, mine, settle = nil, {}, {}, nil, {}, {}, {}
    knownFlat, blueprintAt = nil, -100000
end

function Rides._State() return {known = known, editing = editing, jobs = jobs, tag = tag, files = mine} end

return Rides
