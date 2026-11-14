-- Original MIT code. Read-only API survey: lists names and types, calls no game method
-- except CreateUndoOperationsHierarchy (an empty, never-previewed change list).
local global = _G
local Introspect = {}
local LIMIT = 400

local function names(value)
    local result = {}
    local function collect(t)
        if global.type(t) ~= "table" then return end
        for k, v in global.pairs(t) do
            if #result >= LIMIT then return end
            if global.type(k) == "string" then result[#result+1] = k .. ":" .. global.string.sub(global.type(v), 1, 1) end
        end
    end
    if global.type(value) == "table" then collect(value) end
    local ok, meta = global.pcall(global.getmetatable, value)
    if ok and global.type(meta) == "table" then
        collect(meta)
        if global.type(meta.__index) == "table" then collect(meta.__index) end
    end
    global.table.sort(result)
    return result
end

local function dump(emit, label, value)
    local list = names(value)
    emit("introspect:" .. label .. ":type=" .. global.type(value) .. ":count=" .. #list)
    -- Chunked so each log record stays below the 4096-byte diagnostic limit.
    for i = 1, #list, 40 do
        emit("introspect:" .. label .. ":" .. global.table.concat(list, ",", i, global.math.min(i + 39, #list)))
    end
end

function Introspect.Run(emit)
    local api = global.api
    dump(emit, "api", api)
    for _, key in global.ipairs({"undo", "camera", "ui", "world", "entity", "transform", "spatial", "messaging",
        "time", "input", "game", "debug", "audio", "render", "network", "online", "steam", "platform", "content"}) do
        if api[key] ~= nil then dump(emit, "api." .. key, api[key]) end
    end
    local apis = api.world.GetWorldAPIs()
    dump(emit, "worldapis", apis)
    for _, key in global.ipairs({"CameraModeManager", "editors", "placement", "scenery", "park", "camera",
        "player", "worldserialisation", "transform", "ui", "hud", "notification", "messaging"}) do
        if apis and apis[key] ~= nil then dump(emit, "worldapis." .. key, apis[key]) end
    end
    local ok, hierarchy = global.pcall(function() return apis.editors:CreateUndoOperationsHierarchy() end)
    if ok then dump(emit, "hierarchy", hierarchy) else emit("introspect:hierarchy:error=" .. global.tostring(hierarchy)) end
    if ok then
        local meta = global.getmetatable(hierarchy)
        local writable = global.pcall(function()
            local index = meta.__index
            local original = index.CreateNewPart
            index.CreateNewPart = original
        end)
        emit("introspect:hierarchy-index-writable=" .. global.tostring(writable)
            .. ";shared=" .. global.tostring(global.getmetatable(apis.editors:CreateUndoOperationsHierarchy()) == meta))
    end
    for _, key in global.ipairs({"inworldtext", "WorldBasedGUIProvider", "debugimgui", "camerahelper",
        "PlayerInteractionHandler", "SelectAndEditComponent", "billboardwidgets", "HUDPopUpManager"}) do
        if apis and apis[key] ~= nil then dump(emit, "worldapis." .. key, apis[key]) end
    end
    for _, key in global.ipairs({"debugui", "player", "presence", "json", "ui2", "cursor", "math"}) do
        if api[key] ~= nil then dump(emit, "api." .. key, api[key]) end
    end
    for _, name in global.ipairs({"Quaternion", "Vector3", "TransformQ"}) do
        local okModule, module = global.pcall(global.require, name)
        if okModule then dump(emit, "module." .. name, module) end
    end
    global.pcall(function()
        local q = global.require("Quaternion").Identity
        dump(emit, "instance.Quaternion", q)
        local t = global.require("TransformQ").FromOrPos(q, global.require("Vector3"):new(1, 2, 3))
        dump(emit, "instance.TransformQ", t)
        dump(emit, "instance.Vector3", global.require("Vector3"):new(1, 2, 3))
    end)
    global.pcall(function()
        local results = {apis.CameraModeManager:GetPosYPRZoom()}
        local parts = {}
        for i = 1, #results do parts[#parts+1] = global.type(results[i]) .. "=" .. global.tostring(results[i]) end
        emit("introspect:camera-posyprzoom:" .. global.table.concat(parts, ";"))
        emit("introspect:camera-mode:" .. global.tostring(apis.CameraModeManager:GetCurrentModeName()))
    end)
    local okImGui, ImGui = global.pcall(global.require, "ImGui")
    if okImGui then dump(emit, "ImGui", ImGui) end
    local loaded = {}
    for name in global.pairs(global.package.loaded) do
        if global.type(name) == "string" and (global.string.find(name, "Camera") or global.string.find(name, "Editors%.")
            or global.string.find(name, "Gameface") or global.string.find(name, "HUD")) then
            loaded[#loaded+1] = name
        end
    end
    global.table.sort(loaded)
    for i = 1, #loaded, 30 do
        emit("introspect:loaded:" .. global.table.concat(loaded, ",", i, global.math.min(i + 29, #loaded)))
    end
    emit("introspect:done")
end

return Introspect
