-- Original PC2Coop diagnostic source. No world/save mutations.
local global = _G
local api = global.api
local LuaDB = {}
local probeVersion = "1.7.0"
local diagnostic
local viewHookResult = "not-run"

function LuaDB.AddLuaManagers(add)
    add("Environments.CPTEnvironment", {["Managers.PC2CoopQA"]={}})
end

local function trace(message)
    if diagnostic and diagnostic.ready then
        diagnostic.Write("[PC2CoopProbe " .. probeVersion .. "] " .. message)
    end
    if api and api.debug and global.type(api.debug.Trace) == "function" then
        api.debug.Trace("[PC2CoopProbe " .. probeVersion .. "] " .. message)
    end
end

-- ACSE reports hook errors through api.debug.Error, which can end the game process.
-- Every hook therefore catches its own errors and only traces them.
local function guarded(name, install)
    return function(module)
        trace("hook-begin:" .. name)
        local ok, failure = global.pcall(install, module)
        trace(ok and ("hook-done:" .. name) or ("hook-error:" .. name .. ":" .. global.tostring(failure)))
    end
end

function LuaDB.AddLuaHooks(add)
    add("Editors.Scenery.SubModeBase", guarded("SubModeBase", function(module)
        global.require("pc2coop.capture").Install(module, trace)
    end))
    add("Editors.Scenery.SubModeSelect", guarded("SubModeSelect", function(module)
        global.require("pc2coop.capture").InstallSelect(module, trace)
    end))
    add("Managers.ParkLoadSaveManager", guarded("ParkLoadSaveManager", function(module)
        local qa = global.require("pc2coop.qa")
        qa.Init(trace)
        qa.HookManager(module)
    end))
    add("Windows.MainHUDGameface", guarded("MainHUD", function(module)
        global.require("pc2coop.world").HookHUD(module, trace)
    end))
    add("Managers.NotificationManager", guarded("NotificationManager", function(module)
        global.require("pc2coop.world").HookNotifications(module, trace)
    end))
    add("StartScreen.Shared.SandboxMenuHUD", guarded("SandboxMenuHUD", function(module)
        local qa = global.require("pc2coop.qa")
        qa.Init(trace)
        qa.HookFrontend(module)
    end))
end

local function fieldType(parent, field)
    if parent == nil then
        return "parent-missing"
    end
    local ok, value = global.pcall(function() return parent[field] end)
    if not ok then
        return "access-failed"
    end
    return global.type(value)
end

-- Compact, fixed-key capability display. Only reads field types; calls none.
-- f=function, t=table, u=userdata, n=nil, -=parent missing, !=access failed.
local function typeCode(parent, name)
    local kind = fieldType(parent, name)
    local codes = { ["function"]="f", ["table"]="t", ["userdata"]="u",
        ["nil"]="n", ["parent-missing"]="-", ["access-failed"]="!" }
    return codes[kind] or "?"
end

local function capabilityMarker()
    local undo = api and api.undo
    return " [P:" .. typeCode(undo, "PreviewChangeList")
        .. " C:" .. typeCode(undo, "CommitPreview")
        .. " O:" .. typeCode(undo, "IsOperationComplete")
        .. " io:" .. typeCode(global, "io")
        .. " open:" .. typeCode(global.io, "open")
        .. " L:" .. typeCode(global, "loadfile") .. "]"
end

function LuaDB.AddContentToCall(content)
    if not api or not api.acse then
        return
    end
    if global.type(api.acse.versionNumber) ~= "number" or api.acse.versionNumber < 0.7 then
        return
    end
    global.table.insert(content, global.require("database.pc2coopprobeluadatabase"))
end

function LuaDB.Init()
    -- Mount the mod's Gameface package (UI files) before any game view loads.
    if api and api.ui2 and global.type(api.ui2.MapResources) == "function" then
        global.pcall(api.ui2.MapResources, "PC2CoopUI")
        -- Remember every Gameface view the game creates (HUD, FrontEnd, ...), so the co-op
        -- layer inside them can be reached with view events.
        viewHookResult = global.select(2, global.pcall(function()
            if global.rawget(api.ui2, "__pc2coopViews") then return "present" end
            local views, create = {}, api.ui2.CreateView
            global.rawset(api.ui2, "__pc2coopViews", views)
            global.rawset(api.ui2, "CreateView", function(name, ...)
                local view = create(name, ...)
                views[#views+1] = {name = name, view = view}
                return view
            end)
            return "installed"
        end))
    end
    local loaded, value = global.pcall(global.require, "pc2coop.diagnostic")
    if loaded and global.type(value) == "table" then
        diagnostic = value
        diagnostic.Init()
        if diagnostic.ready then
            diagnostic.Write("channel-test:ASCII|UTF8:Grüße|NUL:\0:end")
        end
    end
    trace("begin; phase=database-init; world-api-not-tested")
    trace("acse.versionNumber=" .. global.tostring(api and api.acse and api.acse.versionNumber))
    local undo = api and api.undo
    for _, name in global.ipairs({
        "PreviewChangeList", "CanCommitPreview", "CommitPreview", "IsOperationComplete"
    }) do
        trace("api.undo." .. name .. "=" .. fieldType(undo, name))
    end
    trace("api.world=" .. fieldType(api, "world"))
    trace("api.game=" .. fieldType(api, "game"))
    for _, name in global.ipairs({
        "WriteStringToFile", "ReadStringFromFile", "CreateLog", "WriteLog", "GetListOfLoadedModuleNames"
    }) do
        trace("api.debug." .. name .. "=" .. fieldType(api and api.debug, name))
    end
    trace("diagnostic=" .. (diagnostic and diagnostic.reason or "unavailable"))
    trace("ui-view-hook=" .. global.tostring(viewHookResult))
    if diagnostic and diagnostic.ready then
        local ok,failure=global.pcall(function()
            local qa=global.require("pc2coop.qa")
            qa.Init(trace)
            qa.AttachLoaded()
            -- GameMain managers may bypass ACSE's late require hook.
            qa.HookManager(global.require("Managers.ParkLoadSaveManager"))
        end)
        if not ok then trace("qa:attach-error:" .. global.tostring(failure)) end
    end
    if diagnostic and diagnostic.ready then
        local ok, failure = global.pcall(function()
            return global.require("pc2coop.stringprobe").Run(trace)
        end)
        if not ok then trace("native-return:lua-error:" .. global.tostring(failure)) end
    end
    -- A visible version suffix can prove Init ran even without a trace logger.
    -- This changes diagnostic UI metadata only, never the park or save state.
    local suffixes = api and api.acse and api.acse.tAppendToVersionString
    if global.type(suffixes) == "table" then
        local marker = "PC2CoopProbe " .. probeVersion .. " Init OK"
            .. ((diagnostic and diagnostic.ready) and " DLL OK" or capabilityMarker())
        local found = false
        for _, item in global.ipairs(suffixes) do
            if item.text == marker then
                found = true
            end
        end
        if not found then
            global.table.insert(suffixes, { text = marker, sep = "\n" })
        end
    end
    trace("complete; world-mutations=0; editor-hooks=registered; save-calls=0")
end

return LuaDB
