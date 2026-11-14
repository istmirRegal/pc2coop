-- Original MIT code. Diagnostic byte channel, independent of custom Lua layouts.
local global = _G
local Diagnostic = { ready = false, reason = "not-started" }
local callbacks

function Diagnostic.Init()
    if callbacks then return Diagnostic.ready end
    callbacks = {}
    local package = global.package
    if not package or global.type(package.loadlib) ~= "function" then
        Diagnostic.reason = "loadlib-missing"
        return false
    end
    local path = ".\\Win64\\ovldata\\PC2CoopProbe\\PC2CoopDiagnostic.dll"
    local function load(name)
        local fn, err = package.loadlib(path, name)
        if global.type(fn) ~= "function" then
            Diagnostic.reason = "missing:" .. name .. ":" .. global.tostring(err)
            return nil
        end
        return fn
    end
    callbacks.bootstrap = load("pc2_bootstrap")
    callbacks.begin = load("pc2_log_begin")
    callbacks.finish = load("pc2_log_end")
    for n = 0, 15 do
        callbacks[n] = load("pc2_nibble_" .. global.string.format("%x", n))
        if not callbacks[n] then return false end
    end
    if not callbacks.bootstrap or not callbacks.begin or not callbacks.finish then return false end
    -- Optional Steam transport (PC2Coop 1.0 DLL); absent in older diagnostic builds.
    callbacks.netEnd = package.loadlib(path, "pc2_net_end")
    callbacks.netPoll = package.loadlib(path, "pc2_net_poll")
    callbacks.bootstrap()
    Diagnostic.ready = true
    Diagnostic.reason = "callbacks-loaded" -- File existence is checked externally.
    return true
end

local function record(text, finish)
    text = global.string.sub(global.tostring(text), 1, 4096)
    callbacks.begin()
    for i = 1, #text do
        local byte = global.string.byte(text, i)
        callbacks[global.math.floor(byte / 16)]()
        callbacks[byte % 16]()
    end
    finish()
end

function Diagnostic.Write(text)
    if not Diagnostic.ready then return end
    record(text, callbacks.finish)
end

function Diagnostic.NetStatus()
    return "ready=" .. global.tostring(Diagnostic.ready) .. ";reason=" .. global.tostring(Diagnostic.reason)
        .. ";netEnd=" .. global.type(callbacks and callbacks.netEnd) .. ";netPoll=" .. global.type(callbacks and callbacks.netPoll)
end

function Diagnostic.HasNet()
    return Diagnostic.ready and global.type(callbacks.netEnd) == "function" and global.type(callbacks.netPoll) == "function"
end

-- One Steam transport command (see native/steam_net.cpp), at most 4096 bytes.
function Diagnostic.NetCommand(text)
    if Diagnostic.HasNet() then record(text, callbacks.netEnd) end
end

-- Next transport event string, or nil.
function Diagnostic.NetPoll()
    if not Diagnostic.HasNet() then return nil end
    local event = callbacks.netPoll()
    if global.type(event) == "string" then return event end
    return nil
end

return Diagnostic
