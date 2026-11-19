-- Original MIT code. Operation replay for edits that are built from world-API calls
-- (terrain, lakes, paths, park management), as opposed to scenery parts, whose final
-- state can be read back. Calls on registered builder methods are recorded with their
-- arguments into a record; a local preview takes the record, later calls that belong to
-- it are still added, and the record is sent only when that preview is committed.
-- A remote batch is replayed into a fresh change list and committed.
--
-- Batch: calls separated by ";". Call forms:
--   api.Method(args)         rN=api.Method(args) (result kept as @rN)
--   @rN.Method(args)         (method on a kept object)      !api.Method(args) (immediate)
-- Args: n<number> b1/b0 s<word> x<hex text> v<x>:<y>:<z> t<x>:<y>:<z>:<qx>:<qy>:<qz>:<qw>
--   {k=arg/k=arg} (flat table) @op (terrain op) @h (change list) @rN e<gid> (shared object) _ (nil)
--   rN=@composite            (new composite object of the change list, e.g. a flat ride)
--   rN=@demolish             (composite that only removes what is moved into it: deleting rides)
--   @cl (the change list of the hierarchy, for builders that take it instead of the hierarchy)
--   {k={k=arg}} nested tables (volume outlines of stamps and pools)
--   y<x>:<y>:<z>:<dx>:<dy>:<dz> a path/pool volume, found again with volumes:Raycast
--   k<x>:<y>:<z> a volume chunk, found again with a physics ray down at that point
--   rN=@table   a Lua table the editor fills through calls (the path brush's handles)
--   hier.Method(@h, ...) a method of the change-list hierarchy itself (RemoveVolume ...)
-- Long batches travel in parts: ~<id>.<i>.<n>~<text> (put together before replay).
local global = _G
local Replay = {}

local emit = function() end
local isOurs = function() return false end
local send = function() end
local entityToGid = function() return nil end
local gidToEntity = function() return nil end
local raw = {}                  -- "api.Method" -> original function
local spec = {}                 -- "api.Method" -> {kind, ...}
local byToken = {}              -- preview token -> record
local byChangeList = global.setmetatable({}, {__mode = "k"})
local installed = false
local demolishing = false       -- inside the game's delete of a selection (SceneryUtils)
local MAX_BATCH = 60000       -- sent in parts of PART_SIZE (the session caps one line)
local PART_SIZE = 2800
local brushHistory = global.setmetatable({}, {__mode = "k"})  -- brush selection -> its calls
local rays = {}                 -- volume id -> {start, dir} of the editor's last raycast hitting it
local rayCount = 0
local partsIn = {}              -- incoming batch parts by id
local partSerial = 0
local hierWrapped = global.setmetatable({}, {__mode = "k"})  -- hierarchy method tables we wrapped

local function newRecord() return {calls = {}, refs = {}, objects = {}, n = 0} end
local record = newRecord()

-- Builders whose first argument is the terrain operation of a change-list hierarchy.
local OPERATION_METHODS = {
    gameterrain = {"SetTerrainEditOpCollisionFlags", "AddPushPullToChangeList", "AddPlaneFlattenToChangeList",
        "AddLowerToPlaneToChangeList", "AddSmoothToChangeList", "AddRoughenToChangeList", "AddSkirtRevealToChangeList",
        "AddSkirtRevealFillToChangeList", "AddPaintVoxelColoursToChangeList",
        "AddPaintVoxelColoursTowardsDataToChangeList", "AddAutoPaintVoxelColoursToChangeList"},
}
-- Builders that return a ready change list.
local CHANGELIST_METHODS = {
    gameterrain = {"CreateLake", "CreateWaterfall"},
}
-- Builders working on objects they create inside a change list (paths and pools).
-- hierarchy = position of the change-list argument; starts = begins a new record.
local OBJECT_METHODS = {
    volumes = {
        CreateMoveObjectForVolumeSpline = {hierarchy = 1, starts = true},
        SetSplinePathData = {}, SetSplineBorderData = {}, SetSplineBuildingOptions = {},
        SetSplineControlPoint = {}, ClearSplineControlPoint = {},
    },
    -- Flat rides (FlatRidePlacementMode.CreateNew): token from the ride name, then the ride
    -- is added to a composite object the editor creates on the hierarchy and positions.
    flatrides = {
        CreateFlatRideEditToken = {starts = true},
        AddFlatRide = {hierarchy = 1, composite = 2},
        GetFlatRideEditToken = {starts = true, entities = {1}},
        MoveFlatRide = {hierarchy = 1, composite = 2},
        -- Deleting one ride (radial menu, demolish tool): SelectAndEditComponent.DeleteFlatRide.
        RemoveFlatRide = {hierarchy = 1},
    },
    -- Ride entrances and exits (EntranceExitPlacementMode): the gate is previewed through a
    -- path join object and placed relative to the station with UpdatePreviewTransform.
    ridestation = {
        GetRideStationEditToken = {starts = true, entities = {1}},
        GetPathJoinPartGroupIDForToken = {keep = true},
        CreateEntranceExitEditToken = {}, GetEntranceExitEditToken = {},
        AddEntranceExit = {changelist = 1}, MoveEntranceExit = {changelist = 1}, RemoveEntranceExit = {changelist = 1},
    },
    placement = {UpdatePreviewTransform = {}},
}
-- Paths and pools beyond the line tool. The brush appends handles to a Lua table every frame
-- and previews anew; the table's calls are kept and go out with the committed preview.
-- Stamps and new pools add whole outlines; the composite is placed with its transform.
OBJECT_METHODS.volumes.AppendBrushHandles = {brush = true, tables = {6}}
OBJECT_METHODS.volumes.CreateMoveObjectsForControlHandles = {composite = 1, hierarchy = 2, tables = {3}}
OBJECT_METHODS.volumes.CreateMoveObjectForVolumeOutline = {composite = 1, hierarchy = 2, outline = true}
OBJECT_METHODS.volumes.CreateMoveObjectHeightStick = {composite = 1, hierarchy = 2}
-- Not recorded yet: the widget tool's selections. The author is told instead of drifting apart.
OBJECT_METHODS.volumes.CreateMoveObjectsForSelection = {unsupported = "Wege mit dem Widget bearbeiten"}
-- Methods of the change-list hierarchy (userdata; wrapped on its shared method table).
local HIER_METHODS = {
    -- Path tool, delete under the cursor (VolumeEditHelper.TryDeleteUnderCursor).
    RemoveVolume = {hierarchy = 1, volumes = {2}, starts = true},
    -- Delete of a selection with paths or pools (SceneryUtils._StartDeletePools).
    AddVolumeChunkToCompositeObject = {hierarchy = 1, composite = 2, chunks = {3}},
}
-- Path joins of ride gates live in the volumes API next to the path builders.
OBJECT_METHODS.volumes.CreateMoveObjectPlatformGateJoin = {hierarchy = 1}
OBJECT_METHODS.volumes.SetPlatformGateJoinRaycastToGround = {}
-- Park management: immediate effect, no preview. Value = argument positions that are
-- entity ids, translated through the stable part id to the shared object id.
local IMMEDIATE_METHODS = {
    facilities = {SetOpen = {1}, SetShopItemPrice = {1}, SetShopInventorySync = {1}, SetShopItemExtraUsed = {1}},
    pools = {SetPoolName = {1}, SetPoolOpen = {1}},
    attractions = {OpenAttraction = {1}, CloseAttraction = {1}},
    ridestation = {SetTicketPrice = {1}, SetSelectedTicketType = {1}, SetTicketCustomMinPrice = {1},
        SetTicketCustomMaxPrice = {1}, SetTicketCustomMinQueue = {1}, SetTicketCustomMaxQueue = {1}},
    park = {SetParkName = {}, SetParkEntranceAdultTicketPrice = {}, SetParkEntrancePriceState = {},
        SetFastPassTicketPrice = {}, SetFastPassTicketPriceState = {}, SetPoolPassPrice = {},
        SetPoolPassPriceState = {}, SetLightingStartProp = {}, SetLightingEndProp = {}},
    techtree = {PurchaseNode = {}},
    money = {TakeLoan = {}, PayLoan = {}, SetLoanStage = {}},
}

local function fmt(n) return global.string.format("%.9g", n) end

local function hex(text)
    return (global.string.gsub(text, ".", function(c) return global.string.format("%02x", global.string.byte(c)) end))
end

local encode

local function encodeScalar(value, ctx)
    local kind = global.type(value)
    if value == nil then return "_" end
    if ctx.refs and ctx.refs[value] then return "@r" .. ctx.refs[value] end
    if ctx.operation ~= nil and value == ctx.operation then return "@op" end
    if kind == "number" then return "n" .. fmt(value) end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "string" then
        global.assert(#value <= 128, "string too long")
        if global.string.match(value, "^[%w_]+$") then return "s" .. value end
        return "x" .. hex(value)
    end
    local okT, p, q = global.pcall(function() return value:GetPos(), value:GetOr() end)
    if okT and p ~= nil and q ~= nil then
        return "t" .. fmt(p:GetX()) .. ":" .. fmt(p:GetY()) .. ":" .. fmt(p:GetZ()) .. ":" .. fmt(q:GetX()) .. ":"
            .. fmt(q:GetY()) .. ":" .. fmt(q:GetZ()) .. ":" .. fmt(q:GetW())
    end
    local ok, x, y, z = global.pcall(function() return value:GetX(), value:GetY(), value:GetZ() end)
    if ok and global.type(x) == "number" then return "v" .. fmt(x) .. ":" .. fmt(y) .. ":" .. fmt(z) end
    global.error("unsupported argument " .. kind)
end

local function plainTable(value, ctx)
    return global.type(value) == "table" and not (ctx.refs and ctx.refs[value])
        and global.rawget(value, "GetX") == nil and global.rawget(value, "GetPos") == nil
end

-- Tables nest (outlines: points with positions); at most 600 values in all.
local function encodeTable(value, ctx, budget)
    local parts = {}
    for k, v in global.pairs(value) do
        global.assert(global.type(k) == "number" or global.string.match(k, "^[%w_]+$"), "bad table key")
        budget.n = budget.n + 1
        global.assert(budget.n <= 600, "table too large")
        parts[#parts+1] = global.tostring(k) .. "=" .. (plainTable(v, ctx) and encodeTable(v, ctx, budget) or encodeScalar(v, ctx))
    end
    return "{" .. global.table.concat(parts, "/") .. "}"
end

encode = function(value, ctx, position)
    if ctx.hierarchyAt and position == ctx.hierarchyAt then return "@h" end
    if ctx.changeListAt and position == ctx.changeListAt then return "@cl" end
    if ctx.operation ~= nil and value == ctx.operation then return "@op" end
    if plainTable(value, ctx) then return encodeTable(value, ctx, {n = 0}) end
    return encodeScalar(value, ctx)
end

-- A volume (path, pool) by a ray of the editor that hit it; the same ray hits it everywhere.
local function encodeVolume(volume)
    local ray = rays[volume]
    global.assert(ray, "volume without ray")
    return "y" .. fmt(ray[1]) .. ":" .. fmt(ray[2]) .. ":" .. fmt(ray[3]) .. ":" .. fmt(ray[4]) .. ":" .. fmt(ray[5]) .. ":" .. fmt(ray[6])
end

local physicsWorld
local function chunkAt(x, y, z)
    physicsWorld = physicsWorld or global.api.entity.FindEntityByName("MainPhysicsWorld")
    local V = global.require("Vector3")
    local hits = global.api.physics.RayCast(physicsWorld, V:new(x, y + 4, z), V:new(x, y - 4, z), global.api.physics.Flag_Volume, 4) or {}
    local volumes = global.api.world.GetWorldAPIs().volumes
    -- The ray hits the chunk's collision entity; the chunk the editors hand around (multi
    -- select, delete) is the ancestor that carries its own volume id (2 levels up in 26255360).
    for _, hit in global.ipairs(hits) do
        local entity = hit.nEntityID
        for _ = 1, 4 do
            if entity == nil then break end
            local okV, id = global.pcall(function() return volumes:GetVolumeIDFromEntityID(entity, false) end)
            if okV and id ~= nil then return entity end
            local okP, parent = global.pcall(function() return global.api.transform.GetParent(entity) end)
            entity = okP and parent or nil
        end
    end
end

-- A volume chunk by a point where a ray straight down hits exactly this chunk.
local function encodeChunk(chunk)
    local p = global.api.transform.CalculateWorldTransform(chunk):GetPos()
    for _, d in global.ipairs({{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {2, 2}, {-2, -2}, {2, -2}, {-2, 2}}) do
        local x, z = p:GetX() + d[1], p:GetZ() + d[2]
        if chunkAt(x, p:GetY(), z) == chunk then return "k" .. fmt(x) .. ":" .. fmt(p:GetY()) .. ":" .. fmt(z) end
    end
    global.error("chunk without probe")
end

local decode

local function decodeScalar(text, ctx)
    local tag, body = global.string.sub(text, 1, 1), global.string.sub(text, 2)
    if text == "_" then return nil end
    if text == "@op" then return ctx.operation() end
    if text == "@h" then return ctx.hierarchy() end
    if text == "@cl" then return ctx.hierarchy():GetFullUndoChangeList() end
    if global.string.sub(text, 1, 2) == "@r" then
        local object = ctx.refs[global.tonumber(global.string.sub(text, 3))]
        global.assert(object ~= nil, "unknown reference " .. text)
        return object
    end
    if tag == "n" then
        local n = global.tonumber(body)
        global.assert(n and n == n and global.math.abs(n) < 1e7, "bad number")
        return n
    end
    if tag == "b" then return body == "1" end
    if tag == "s" then global.assert(global.string.match(body, "^[%w_]+$"), "bad word"); return body end
    if tag == "x" then
        global.assert(#body % 2 == 0 and #body <= 256 and global.string.match(body, "^%x*$"), "bad text")
        return (global.string.gsub(body, "%x%x", function(h) return global.string.char(global.tonumber(h, 16)) end))
    end
    if tag == "e" then
        local entity = gidToEntity(body)
        global.assert(entity, "unknown object " .. body)
        return entity
    end
    local numbers = {}
    for field in global.string.gmatch(body, "[^:]+") do numbers[#numbers+1] = global.tonumber(field) end
    if tag == "y" and #numbers == 6 then
        local V = global.require("Vector3")
        local _, volume = global.api.world.GetWorldAPIs().volumes:Raycast(V:new(numbers[1], numbers[2], numbers[3]),
            V:new(numbers[4], numbers[5], numbers[6]))
        global.assert(volume ~= nil, "volume not found")
        return volume
    end
    if tag == "k" and #numbers == 3 then
        local chunk = chunkAt(numbers[1], numbers[2], numbers[3])
        global.assert(chunk ~= nil, "chunk not found")
        return chunk
    end
    if tag == "v" and #numbers == 3 then return global.require("Vector3"):new(numbers[1], numbers[2], numbers[3]) end
    if tag == "t" and #numbers == 7 then
        local q = global.require("Quaternion").Identity:WithX(numbers[4]):WithY(numbers[5]):WithZ(numbers[6]):WithW(numbers[7])
        return global.require("TransformQ").FromOrPos(q, global.require("Vector3"):new(numbers[1], numbers[2], numbers[3]))
    end
    global.error("bad argument " .. text)
end

-- Splits at "/" outside of nested braces.
local function splitEntries(text)
    local out, depth, start = {}, 0, 1
    for i = 1, #text do
        local c = global.string.sub(text, i, i)
        if c == "{" then depth = depth + 1
        elseif c == "}" then depth = depth - 1; global.assert(depth >= 0, "bad table")
        elseif c == "/" and depth == 0 then out[#out+1] = global.string.sub(text, start, i - 1); start = i + 1 end
    end
    global.assert(depth == 0, "bad table")
    if start <= #text then out[#out+1] = global.string.sub(text, start) end
    return out
end

decode = function(text, ctx)
    if global.string.sub(text, 1, 1) == "{" then
        global.assert(global.string.sub(text, -1) == "}", "bad table")
        local out = {}
        for _, entry in global.ipairs(splitEntries(global.string.sub(text, 2, -2))) do
            local k, v = global.string.match(entry, "^([%w_]+)=(.+)$")
            global.assert(k, "bad table entry")
            out[global.tonumber(k) or k] = decode(v, ctx)
        end
        return out
    end
    return decodeScalar(text, ctx)
end

local function encodeCall(name, args, ctx, entities)
    local parts = {}
    for i = 1, args.n do
        if ctx.volumesAt and ctx.volumesAt[i] then
            parts[i] = encodeVolume(args[i])
        elseif ctx.chunksAt and ctx.chunksAt[i] then
            parts[i] = encodeChunk(args[i])
        elseif entities and entities[i] then
            local gid = entityToGid(args[i])
            global.assert(gid, "object not shared")
            parts[i] = "e" .. gid
        else
            parts[i] = encode(args[i], ctx, i)
        end
    end
    return name .. "(" .. global.table.concat(parts, ",") .. ")"
end

-- A table filled by recorded calls (brush handles): created on replay, then its calls.
local function tableRef(t)
    if not brushHistory[t] then
        -- Handles picked in the select/pinpoint/widget tools: not recorded (yet). Say so.
        emit("sync:unsupported|Wege mit Anfassern bearbeiten")
        global.error("selection not recorded")
    end
    record.n = record.n + 1
    record.refs[t], record.objects[record.n] = record.n, t
    record.calls[#record.calls+1] = "r" .. record.n .. "=@table"
    for _, call in global.ipairs(brushHistory[t] or {}) do
        record.calls[#record.calls+1] = global.string.format(call, "@r" .. record.n)
    end
end

local function onCall(name, s, self, args, results)
    if s.kind == "immediate" then
        send("!" .. encodeCall(name, args, {}, s.entities))
        return
    end
    if s.unsupported then
        emit("sync:unsupported|" .. s.unsupported)
        global.error("not recorded")
    end
    if s.brush then
        -- Every frame of a stroke: kept with its table, recorded when a preview uses it.
        local t = args[s.tables[1]]
        if global.type(t) ~= "table" then return end
        local fields = {}
        for i = 1, args.n do fields[i] = i == s.tables[1] and "%s" or encode(args[i], {}, i) end
        local text = name .. "(" .. global.table.concat(fields, ",") .. ")"
        local history = brushHistory[t] or {}
        brushHistory[t] = history
        if history[#history] ~= text and #history < 2000 then history[#history+1] = text end
        return
    end
    -- A delete takes all selected rides into one record; otherwise each ride starts its own.
    if s.starts and not demolishing then record = newRecord() end
    local composite = s.composite and args[s.composite]
    if composite ~= nil and not record.refs[composite] then
        -- Created by the hierarchy itself (not an API call): recreate it on replay.
        record.n = record.n + 1
        record.refs[composite], record.objects[record.n] = record.n, composite
        if demolishing then
            record.demolish = record.demolish or {}
            record.demolish[record.n] = true
            record.calls[#record.calls+1] = "r" .. record.n .. "=@demolish"
        else
            record.composites = record.composites or {}
            record.composites[record.n] = true
            record.calls[#record.calls+1] = "r" .. record.n .. "=@composite"
        end
    end
    for _, i in global.ipairs(s.tables or {}) do
        local t = args[i]
        if global.type(t) == "table" and not record.refs[t] then tableRef(t) end
    end
    if s.outline and composite ~= nil then
        record.outline = record.outline or {}
        record.outline[record.refs[composite]] = true
    end
    local ctx = {refs = record.refs, hierarchyAt = s.hierarchy, changeListAt = s.changelist,
        volumesAt = s.volumesAt, chunksAt = s.chunksAt}
    if s.kind == "operation" then ctx.operation = args[1] end
    local text = encodeCall(name, args, ctx, s.entities)
    local resultType = global.type(results[1])
    -- keep: plain results (ids) that later calls take back, e.g. a ride's path join group.
    if s.kind == "object" and (resultType == "userdata" or resultType == "table" or (s.keep and results[1] ~= nil)) then
        record.n = record.n + 1
        record.refs[results[1]], record.objects[record.n] = record.n, results[1]
        text = "r" .. record.n .. "=" .. text
    end
    if s.kind == "changelist" then
        local entry = {calls = {text}, objects = {}}
        if results[1] ~= nil then byChangeList[results[1]] = entry end
        return
    end
    -- Editors repeat setters on the same object every frame; only the latest counts.
    local target = args[1] ~= nil and record.refs[args[1]]
    if s.kind == "object" and target and not s.starts then
        record.slots = record.slots or {}
        local slot = name .. "@" .. target
        if record.slots[slot] then record.calls[record.slots[slot]] = text; return end
        record.slots[slot] = #record.calls + 1
    end
    record.calls[#record.calls+1] = text
end

local function wrap(apis, key, method, s)
    local target = apis[key]
    local original = target and target[method]
    if global.type(original) ~= "function" then return false end
    local name = key .. "." .. method
    raw[name], spec[name] = original, s
    target[method] = function(self, ...)
        local results = global.table.pack(original(self, ...))
        if not isOurs() then
            local ok, failure = global.pcall(onCall, name, s, self, global.table.pack(...), results)
            if not ok then emit("replay:skip|" .. name .. "|" .. global.tostring(failure)) end
        end
        return global.table.unpack(results, 1, results.n)
    end
    return true
end

function Replay.Init(logger, oursFunction, sender, toGid, fromGid)
    emit = logger
    isOurs = oursFunction or isOurs
    send = sender or send
    entityToGid = toGid or entityToGid
    gidToEntity = fromGid or gidToEntity
end

function Replay.Install()
    if installed then return end
    local apis = global.api.world.GetWorldAPIs()
    local count = 0
    local function try(key, method, s)
        local ok, wrapped = global.pcall(wrap, apis, key, method, s)
        if ok and wrapped then count = count + 1 end
    end
    for key, methods in global.pairs(OPERATION_METHODS) do
        for _, method in global.ipairs(methods) do try(key, method, {kind = "operation"}) end
    end
    for key, methods in global.pairs(CHANGELIST_METHODS) do
        for _, method in global.ipairs(methods) do try(key, method, {kind = "changelist"}) end
    end
    for key, methods in global.pairs(OBJECT_METHODS) do
        for method, s in global.pairs(methods) do
            local set
            if s.entities then set = {}; for _, i in global.ipairs(s.entities) do set[i] = true end end
            try(key, method, {kind = "object", hierarchy = s.hierarchy, starts = s.starts, composite = s.composite,
                changelist = s.changelist, keep = s.keep, entities = set, tables = s.tables, brush = s.brush,
                outline = s.outline, unsupported = s.unsupported})
        end
    end
    for key, methods in global.pairs(IMMEDIATE_METHODS) do
        for method, entities in global.pairs(methods) do
            local set = {}
            for _, i in global.ipairs(entities) do set[i] = true end
            try(key, method, {kind = "immediate", entities = set})
        end
    end
    -- The path tool finds the volume under the cursor with volumes:Raycast; keep the ray.
    global.pcall(function()
        local volumes = apis.volumes
        local original = volumes.Raycast
        if global.type(original) ~= "function" then return end
        volumes.Raycast = function(self, start, dir, ...)
            local results = global.table.pack(original(self, start, dir, ...))
            local volume = results[2]
            if volume ~= nil and not isOurs() then
                global.pcall(function()
                    if not rays[volume] then rayCount = rayCount + 1 end
                    if rayCount > 4000 then rays, rayCount = {}, 1 end
                    rays[volume] = {start:GetX(), start:GetY(), start:GetZ(), dir:GetX(), dir:GetY(), dir:GetZ()}
                end)
            end
            return global.table.unpack(results, 1, results.n)
        end
        count = count + 1
    end)
    -- Hierarchy methods: userdata methods on a table all hierarchies share. The game swaps
    -- that table after a park finished loading (seen in game: wrappers made at our install
    -- were gone later), so every new hierarchy is checked and gets the wrappers if needed.
    local set = function(list)
        if not list then return nil end
        local out = {}
        for _, i in global.ipairs(list) do out[i] = true end
        return out
    end
    for method, s in global.pairs(HIER_METHODS) do
        local name = "hier." .. method
        spec[name] = {kind = "object", hierarchy = s.hierarchy, composite = s.composite, starts = s.starts,
            volumesAt = set(s.volumes), chunksAt = set(s.chunks)}
        -- Replay calls the method on its own hierarchy (our wrapper skips it there: ours()).
        raw[name] = function(_, h, ...) return h[method](h, ...) end
        count = count + 1
    end
    local function installHier(index)
        if global.type(index) ~= "table" or hierWrapped[index] then return end
        hierWrapped[index] = true
        for method in global.pairs(HIER_METHODS) do
            local original = index[method]
            if global.type(original) == "function" then
                local name, full = "hier." .. method, spec["hier." .. method]
                index[method] = function(self, ...)
                    local results = global.table.pack(original(self, ...))
                    if not isOurs() then
                        local ok, failure = global.pcall(onCall, name, full, nil, global.table.pack(self, ...), results)
                        if not ok then emit("replay:skip|" .. name .. "|" .. global.tostring(failure)) end
                    end
                    return global.table.unpack(results, 1, results.n)
                end
            end
        end
        emit("replay:hierarchy-hooks")
    end
    global.pcall(function()
        local editors = apis.editors
        local create = editors.CreateUndoOperationsHierarchy
        editors.CreateUndoOperationsHierarchy = function(self, ...)
            local results = global.table.pack(create(self, ...))
            global.pcall(function() installHier(global.getmetatable(results[1]).__index) end)
            return global.table.unpack(results, 1, results.n)
        end
        installHier(global.getmetatable(editors:CreateUndoOperationsHierarchy()).__index)
    end)
    -- Deleting a selection (select mode, multi-select, Delete key in a placement mode): the
    -- game moves each flat ride into a "demolish only" composite. Mark that time so the
    -- composite is recreated as one on replay.
    local okU, SceneryUtils = global.pcall(global.require, "Editors.Scenery.Utils.SceneryUtils")
    if okU and global.type(SceneryUtils) == "table" and global.type(SceneryUtils.DeleteMultiSelection_Core) == "function" then
        local core = SceneryUtils.DeleteMultiSelection_Core
        -- No pcall here: the game's delete may wait for requests (coroutine yield). If it
        -- fails, the preview that follows any edit ends the demolition mark as well.
        local function done(...) demolishing = false; return ... end
        SceneryUtils.DeleteMultiSelection_Core = function(...)
            if not isOurs() then record, demolishing = newRecord(), true end
            return done(core(...))
        end
        count = count + 1
    end
    installed = true
    emit("replay:installed|" .. count)
end

-- Local preview started: the current record (and later calls to it) belong to it.
function Replay.OnPreview(changeList, token)
    demolishing = false
    if token == nil then return end
    local direct = byChangeList[changeList]
    if direct then byToken[token] = direct
    elseif #record.calls > 0 then
        byToken[token] = record
        -- Calls after this point were made while the preview ran (paths reshape live).
        record.previewAt = record.previewAt or #record.calls
    end
end

-- A batch longer than one session line goes as parts: ~<id>.<i>.<n>~<text>.
function Replay.Split(batch)
    if #batch <= PART_SIZE then return {batch} end
    partSerial = partSerial + 1
    local id = global.tostring(partSerial) .. "x" .. global.tostring(global.math.random(1, 999999))
    local out, n = {}, global.math.ceil(#batch / PART_SIZE)
    for i = 1, n do
        out[i] = "~" .. id .. "." .. i .. "." .. n .. "~" .. global.string.sub(batch, (i - 1) * PART_SIZE + 1, i * PART_SIZE)
    end
    return out
end

-- Puts parts together; returns the whole batch once the last part is in, else nil.
local function assemble(batch)
    local id, i, n, text = global.string.match(batch, "^~([%w]+)%.(%d+)%.(%d+)~(.*)$")
    if not id then return batch end
    i, n = global.tonumber(i), global.tonumber(n)
    global.assert(n and n >= 1 and n <= 40 and i >= 1 and i <= n, "bad part")
    local entry = partsIn[id] or {n = n, got = 0, parts = {}}
    partsIn[id] = entry
    if not entry.parts[i] then entry.parts[i], entry.got = text, entry.got + 1 end
    if entry.got < entry.n then return nil end
    partsIn[id] = nil
    return global.table.concat(entry.parts)
end

function Replay.Remap(oldToken, newToken)
    if byToken[oldToken] then byToken[newToken], byToken[oldToken] = byToken[oldToken], nil end
end

local function finish(token)
    local rec = byToken[token]
    byToken[token] = nil
    if rec == record then record = newRecord() end
    return rec
end

function Replay.OnCancel(token) finish(token) end

-- Local preview committed: returns the batch to send, or nil.
function Replay.OnCommit(token)
    local rec = finish(token)
    if not rec or #rec.calls == 0 then return nil end
    -- Objects positioned directly by the editor (path end point): the editor moves them
    -- before its setters recompute the shape, so the position goes right after creation.
    local positions, placed = {}, {}
    for n, object in global.pairs(rec.objects) do
        if rec.demolish and rec.demolish[n] then
            -- The game destroys the demolition composite once the rides are in it.
            placed[#placed+1] = "@r" .. n .. ".Destroy()"
        elseif rec.composites and rec.composites[n] then
            -- Composites (rides) are placed with their rotation, after their content is added.
            local ok, transform = global.pcall(function() return object:GetTransform() end)
            -- Stamps and pools: the editor puts the origin into the middle of the outline first.
            if rec.outline and rec.outline[n] then placed[#placed+1] = "@r" .. n .. ".SetCompositeOriginToOBBCentre()" end
            if ok and transform ~= nil then placed[#placed+1] = "@r" .. n .. ".SetTransform(" .. encodeScalar(transform, {}) .. ")" end
        else
            local ok, position = global.pcall(function() return object:GetPosition() end)
            if ok and position ~= nil then positions[n] = "@r" .. n .. ".SetPosition(" .. encodeScalar(position, {}) .. ")" end
        end
    end
    local calls = {}
    local live = rec.previewAt and global.next(positions) ~= nil
    for i, c in global.ipairs(rec.calls) do
        calls[#calls+1] = c
        local created = global.tonumber(global.string.match(c, "^r(%d+)="))
        if created and positions[created] and not live then calls[#calls+1] = positions[created] end
        if live and i == rec.previewAt then calls[#calls+1] = "@preview" end
    end
    if live then
        if rec.previewAt == 0 then global.table.insert(calls, 1, "@preview") end
        for _, p in global.pairs(positions) do calls[#calls+1] = p end
    end
    for _, p in global.ipairs(placed) do calls[#calls+1] = p end
    local batch = global.table.concat(calls, ";")
    if #batch > MAX_BATCH then emit("replay:batch-too-large|" .. #batch); return nil end
    return batch
end

local function splitArgs(text)
    local list = {}
    if text ~= "" then for field in global.string.gmatch(text, "[^,]+") do list[#list+1] = field end end
    return list
end

-- Replays one or more batches. commit(changeList) previews and commits a change list;
-- begin(changeList) only starts the preview and finish(preview) waits and commits it.
function Replay.Apply(batches, commit, begin, finish)
    local apis = global.api.world.GetWorldAPIs()
    local hierarchy, operation, livePreview, volumeBlock, usedVolumes
    local function getHierarchy()
        hierarchy = hierarchy or apis.editors:CreateUndoOperationsHierarchy()
        return hierarchy
    end
    local function getOperation()
        operation = operation or getHierarchy():GetTerrainEditOperation()
        return operation
    end
    local whole = {}
    for _, batch in global.ipairs(batches) do
        local done = assemble(batch)
        if done then whole[#whole+1] = done end
    end
    for _, batch in global.ipairs(whole) do
        local ctx = {refs = {}, hierarchy = getHierarchy, operation = getOperation}
        for text in global.string.gmatch(batch, "[^;]+") do
            local objectRef, objectMethod, objectArgs = global.string.match(text, "^@r(%d+)%.([%w_]+)%((.*)%)$")
            local compositeRef = global.string.match(text, "^r(%d+)=@composite$")
            local demolishRef = global.string.match(text, "^r(%d+)=@demolish$")
            local tableRefN = global.string.match(text, "^r(%d+)=@table$")
            if tableRefN then
                ctx.refs[global.tonumber(tableRefN)] = {}
            elseif compositeRef then
                ctx.refs[global.tonumber(compositeRef)] = getHierarchy():CreateCompositeObject({})
            elseif demolishRef then
                ctx.refs[global.tonumber(demolishRef)] = getHierarchy():CreateCompositeObject({bDemolishOnly = true})
            elseif text == "@preview" then
                global.assert(begin and not livePreview, "unexpected preview marker")
                if volumeBlock then getHierarchy():EndVolumeModificationsBlock(); volumeBlock = false end
                livePreview = begin(getHierarchy():GetFullUndoChangeList())
            elseif objectRef then
                global.assert(objectMethod == "SetPosition" or objectMethod == "SetTransform" or objectMethod == "Destroy"
                    or objectMethod == "SetCompositeOriginToOBBCentre", "object method")
                local object = ctx.refs[global.tonumber(objectRef)]
                global.assert(object ~= nil, "unknown reference")
                local values = {}
                for i, a in global.ipairs(splitArgs(objectArgs)) do values[i] = decode(a, ctx) end
                -- Live edits of volume objects (gate joins) happen inside a modifications block.
                local block = livePreview and usedVolumes
                if block then getHierarchy():BeginVolumeModificationsBlock() end
                object[objectMethod](object, global.table.unpack(values))
                if block then getHierarchy():EndVolumeModificationsBlock() end
            else
                local immediate = global.string.sub(text, 1, 1) == "!"
                if immediate then text = global.string.sub(text, 2) end
                local resultRef, rest = global.string.match(text, "^r(%d+)=(.+)$")
                if resultRef then text = rest end
                local name, argText = global.string.match(text, "^([%w_]+%.[%w_]+)%((.*)%)$")
                global.assert(name and raw[name], "unknown call " .. global.tostring(text))
                local key = global.string.match(name, "^([%w_]+)%.")
                local args = splitArgs(argText)
                if (global.string.sub(name, 1, 8) == "volumes." or global.string.sub(name, 1, 5) == "hier.")
                    and not volumeBlock and not livePreview then
                    -- Same frame the path editor builds around its calls (VolumeEditHelper.BeginPreview).
                    local h = getHierarchy()
                    h:BeginVolumeModificationsBlock()
                    h:SetPerformTerrainModificationsModifyVolumes(false)
                    raw["gameterrain.SetTerrainEditOpCollisionFlags"](apis.gameterrain, getOperation(), true, false, false, false, true, true)
                    volumeBlock, usedVolumes = true, true
                end
                local values = {}
                for i, a in global.ipairs(args) do values[i] = decode(a, ctx) end
                local block = livePreview and usedVolumes and not immediate
                if block then getHierarchy():BeginVolumeModificationsBlock() end
                local result = raw[name](apis[key], global.table.unpack(values, 1, #args))
                if block then getHierarchy():EndVolumeModificationsBlock() end
                if resultRef then ctx.refs[global.tonumber(resultRef)] = result end
                if name == "volumes.CreateMoveObjectForVolumeSpline" then
                    -- The editor sets this on the hierarchy directly (not an API call).
                    global.pcall(function() getHierarchy():SetErrorOnPathMergeUnchangedModifyVolumes(not values[6]) end)
                end
                if (spec[name] or {}).kind == "changelist" then commit(result) end
            end
        end
    end
    if volumeBlock then hierarchy:EndVolumeModificationsBlock() end
    -- Paths: the editor lets terrain follow the path only at commit (TryCommitPreview).
    if usedVolumes then hierarchy:SetPerformTerrainModificationsModifyVolumes(true) end
    if livePreview then finish(livePreview)
    elseif hierarchy then commit(hierarchy:GetFullUndoChangeList()) end
end

function Replay.Stop() record, byToken = newRecord(), {} end

Replay._encode, Replay._decode = encode, decode
return Replay
