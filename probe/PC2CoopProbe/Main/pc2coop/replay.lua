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
--   @cl (the change list of the hierarchy, for builders that take it instead of the hierarchy)
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
local MAX_BATCH = 3500

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

encode = function(value, ctx, position)
    if ctx.hierarchyAt and position == ctx.hierarchyAt then return "@h" end
    if ctx.changeListAt and position == ctx.changeListAt then return "@cl" end
    if ctx.operation ~= nil and value == ctx.operation then return "@op" end
    if global.type(value) == "table" and not (ctx.refs and ctx.refs[value])
        and global.rawget(value, "GetX") == nil and global.rawget(value, "GetPos") == nil then
        local parts = {}
        for k, v in global.pairs(value) do
            global.assert(global.type(k) == "number" or global.string.match(k, "^[%w_]+$"), "bad table key")
            global.assert(global.type(v) ~= "table", "nested table")
            parts[#parts+1] = global.tostring(k) .. "=" .. encodeScalar(v, ctx)
            global.assert(#parts <= 16, "table too large")
        end
        return "{" .. global.table.concat(parts, "/") .. "}"
    end
    return encodeScalar(value, ctx)
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
    if tag == "v" and #numbers == 3 then return global.require("Vector3"):new(numbers[1], numbers[2], numbers[3]) end
    if tag == "t" and #numbers == 7 then
        local q = global.require("Quaternion").Identity:WithX(numbers[4]):WithY(numbers[5]):WithZ(numbers[6]):WithW(numbers[7])
        return global.require("TransformQ").FromOrPos(q, global.require("Vector3"):new(numbers[1], numbers[2], numbers[3]))
    end
    global.error("bad argument " .. text)
end

decode = function(text, ctx)
    if global.string.sub(text, 1, 1) == "{" then
        global.assert(global.string.sub(text, -1) == "}", "bad table")
        local out = {}
        for entry in global.string.gmatch(global.string.sub(text, 2, -2), "[^/]+") do
            local k, v = global.string.match(entry, "^([%w_]+)=(.+)$")
            global.assert(k, "bad table entry")
            out[global.tonumber(k) or k] = decodeScalar(v, ctx)
        end
        return out
    end
    return decodeScalar(text, ctx)
end

local function encodeCall(name, args, ctx, entities)
    local parts = {}
    for i = 1, args.n do
        if entities and entities[i] then
            local gid = entityToGid(args[i])
            global.assert(gid, "object not shared")
            parts[i] = "e" .. gid
        else
            parts[i] = encode(args[i], ctx, i)
        end
    end
    return name .. "(" .. global.table.concat(parts, ",") .. ")"
end

local function onCall(name, s, self, args, results)
    if s.kind == "immediate" then
        send("!" .. encodeCall(name, args, {}, s.entities))
        return
    end
    if s.starts then record = newRecord() end
    local composite = s.composite and args[s.composite]
    if composite ~= nil and not record.refs[composite] then
        -- Created by the hierarchy itself (not an API call): recreate it on replay.
        record.n = record.n + 1
        record.refs[composite], record.objects[record.n] = record.n, composite
        record.composites = record.composites or {}
        record.composites[record.n] = true
        record.calls[#record.calls+1] = "r" .. record.n .. "=@composite"
    end
    local ctx = {refs = record.refs, hierarchyAt = s.hierarchy, changeListAt = s.changelist}
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
                changelist = s.changelist, keep = s.keep, entities = set})
        end
    end
    for key, methods in global.pairs(IMMEDIATE_METHODS) do
        for method, entities in global.pairs(methods) do
            local set = {}
            for _, i in global.ipairs(entities) do set[i] = true end
            try(key, method, {kind = "immediate", entities = set})
        end
    end
    installed = true
    emit("replay:installed|" .. count)
end

-- Local preview started: the current record (and later calls to it) belong to it.
function Replay.OnPreview(changeList, token)
    if token == nil then return end
    local direct = byChangeList[changeList]
    if direct then byToken[token] = direct
    elseif #record.calls > 0 then
        byToken[token] = record
        -- Calls after this point were made while the preview ran (paths reshape live).
        record.previewAt = record.previewAt or #record.calls
    end
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
        if rec.composites and rec.composites[n] then
            -- Composites (rides) are placed with their rotation, after their content is added.
            local ok, transform = global.pcall(function() return object:GetTransform() end)
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
    for _, batch in global.ipairs(batches) do
        local ctx = {refs = {}, hierarchy = getHierarchy, operation = getOperation}
        for text in global.string.gmatch(batch, "[^;]+") do
            local objectRef, objectMethod, objectArgs = global.string.match(text, "^@r(%d+)%.([%w_]+)%((.*)%)$")
            local compositeRef = global.string.match(text, "^r(%d+)=@composite$")
            if compositeRef then
                ctx.refs[global.tonumber(compositeRef)] = getHierarchy():CreateCompositeObject({})
            elseif text == "@preview" then
                global.assert(begin and not livePreview, "unexpected preview marker")
                if volumeBlock then getHierarchy():EndVolumeModificationsBlock(); volumeBlock = false end
                livePreview = begin(getHierarchy():GetFullUndoChangeList())
            elseif objectRef then
                global.assert(objectMethod == "SetPosition" or objectMethod == "SetTransform", "object method")
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
                if global.string.sub(name, 1, 8) == "volumes." and not volumeBlock and not livePreview then
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
