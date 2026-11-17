-- Original MIT code. Bridge between the session and the PC2 Co-op layer that runs inside
-- the game's Gameface HUD (js/pc2coop/CoopLayer.js): publishes the state as JSON in the
-- DataStore context "pc2coop" and executes the layer's requests.
local global = _G
local Ui = {}

local emit = function() end
local session, sync, menu
local context
local lastState
local lastAvatars = nil
local lastRequest
local open = false
local canHost = true
local frontendMenu = nil  -- the main menu's sandbox HUD (park list, new parks); nil in a park
local parkList = {}       -- host: saved parks to choose from
local chosen = nil        -- host: {kind, id, biome, creative} picked in the lobby
local BIOME_NAMES = {Temperate = "Gemaessigt", Mediterranean = "Mediterran", Taiga = "Taiga", Tropical = "Tropisch"}
local frames = 0

local function quote(text)
    text = global.string.gsub(global.tostring(text), '[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        return global.string.format("\\u%04x", global.string.byte(c))
    end)
    return '"' .. text .. '"'
end

local function json(value)
    local kind = global.type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == global.math.huge or value == -global.math.huge then return "0" end
        -- Whole numbers exactly (DLC bit masks), the rest short.
        if value == global.math.floor(value) and global.math.abs(value) < 9007199254740992 then return global.string.format("%d", value) end
        return global.string.format("%.6g", value)
    end
    if kind == "string" then return quote(value) end
    if kind == "table" then
        if #value > 0 or global.next(value) == nil then
            local parts = {}
            for i = 1, #value do parts[i] = json(value[i]) end
            return "[" .. global.table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, v in global.pairs(value) do parts[#parts+1] = quote(k) .. ":" .. json(v) end
        global.table.sort(parts)
        return "{" .. global.table.concat(parts, ",") .. "}"
    end
    return "null"
end
Ui._json = json

local function ensureContext()
    if context then return context end
    local ui2 = global.api.ui2
    local ok, existing = global.pcall(ui2.GetDataStoreContext, "pc2coop")
    if ok and existing then
        context = existing
    else
        context = ui2.CreateDataStoreContext({state = "{}", avatars = "{}"}, "pc2coop")
    end
    return context
end

function Ui.Init(logger, sessionModule, syncModule, menuModule)
    emit, session, sync, menu = logger, sessionModule, syncModule, menuModule
end

local closedAt = -1000

function Ui.SetOpen(value)
    if value == true and not open and choosing() then global.pcall(refreshParks) end
    if open and value ~= true then closedAt = frames end
    if open ~= (value == true) then emit("ui:open|" .. global.tostring(value == true) .. "|" .. frames) end
    open = value == true
    if open and session.Available() then session.RefreshFriends() end
    lastState = nil
end

function Ui.Toggle() Ui.SetOpen(not open) end

-- Hosting: a lobby in the main menu, or the loaded park.
function Ui.SetCanHost(value) canHost = value == true end

function Ui.SetFrontend(value) frontendMenu = value end

local function choosing()
    local view = session.View()
    return frontendMenu ~= nil and view.role == "host" and view.stage == "lobby"
end

local function refreshParks()
    local Parks = global.require("pc2coop.parks")
    parkList = choosing() and Parks.List(frontendMenu.parkLoadSaveManager) or {}
end

-- The newest lines of the session log, oldest first.
local function recentLog(feed)
    local out = {}
    feed = feed or {}
    for i = global.math.max(1, #feed - 11), #feed do out[#out+1] = feed[i] end
    return out
end

local function statsList(stats)
    local out = {}
    for name, v in global.pairs(stats or {}) do
        out[#out+1] = {name = name, created = v.created or 0, edited = v.edited or 0, deleted = v.deleted or 0}
    end
    global.table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function buildState()
    local view = session.View()
    local players = {}
    for _, p in global.pairs(view.players or {}) do
        players[#players+1] = {sid = p.sid, name = p.name, color = p.color, act = p.act or "-", x = p.x,
            me = p.sid == view.me, host = p.sid == view.host, hold = p.hold and p.hold.label or false,
            dlc = p.dlc, mods = p.mods or {}}
    end
    global.table.sort(players, function(a, b) return (a.host and 0 or 1) < (b.host and 0 or 1) end)
    local friends = {}
    for _, f in global.ipairs(session.Friends()) do
        friends[#friends+1] = {sid = f.sid, name = f.name, state = f.state, pc2 = f.pc2, invited = f.invited, lobby = f.lobby ~= nil}
    end
    local franchise = false
    if menu and menu.FranchiseInfo then
        local ok, info = global.pcall(menu.FranchiseInfo)
        franchise = ok and info ~= nil
    end
    return {
        available = session.Available() == true, role = view.role or false, me = view.me, open = open,
        canHost = canHost, franchise = franchise, players = players, friends = friends,
        join = session.JoinState and session.JoinState() or false,
        desync = session.Desync and session.Desync() or false,
        park = view.park or false, log = recentLog(view.feed), stats = statsList(view.stats),
        requests = session.Requests and session.Requests() or {},
        following = session.Following and session.Following() or false,
        chat = session.Chat(), toasts = session.Toasts(),
        stage = view.stage or false, parkTitle = view.parkTitle or "", guard = view.guard ~= false,
        context = view.context or false, dlc = view.dlc,
        choice = view.choice or false, canChoose = choosing(), parks = choosing() and parkList or {},
        chosen = chosen and (chosen.kind .. ":" .. global.tostring(chosen.id or chosen.biome or "")) or false,
    }
end

local actions = {
    hello = function() lastState = nil end,
    -- A menu tile can report a select right after the panel closed (focus comes back to it).
    open = function() if frames - closedAt > 45 then Ui.SetOpen(true) end end,
    close = function() Ui.SetOpen(false) end,
    host = function() if canHost then session.Host() end end,
    invite_overlay = function() session.Invite() end,
    invite = function(arg) session.InviteFriend(arg) end,
    leave = function() session.Leave() end,
    resync = function() session.Resync() end,
    retry_join = function() session.Resync() end,
    cancel_join = function() session.DismissJoin() end,
    confirm_join = function() session.ConfirmJoin() end,
    approve = function(arg) session.Answer(arg, true) end,
    deny = function(arg) session.Answer(arg, false) end,
    chat = function(arg) session.SendChat(arg) end,
    jump = function(arg)
        -- To the player's recent ping when there is one, else to their camera.
        for _, ping in global.ipairs(session.Pings()) do
            if ping.sid == arg then
                -- The game's pitch is positive downwards.
                sync.Receive("C|" .. ping.x .. "|" .. (ping.y + 30) .. "|" .. (ping.z - 30) .. "|0|0.75")
                return
            end
        end
        for _, p in global.pairs(session.View().players or {}) do
            if p.sid == arg and p.x then
                sync.Receive("C|" .. p.x .. "|" .. p.y .. "|" .. p.z .. "|" .. (p.yaw or 0) .. "|" .. (p.pitch or 0.5))
            end
        end
    end,
    follow = function(arg)
        if session.Following() == arg then session.SetFollow(nil) else session.SetFollow(arg); Ui.SetOpen(false) end
    end,
    ping = function() session.Ping() end,
    dlc = function(arg) session.SetDlc(arg) end,
    parks = function() refreshParks() end,
    -- "save|<id>", "new|<biome>|<1 creative>", "franchise" or "" (nothing picked)
    choose = function(arg)
        if not choosing() then return end
        local kind, a, b = global.string.match(arg or "", "^(%a*)|?([^|]*)|?(.*)$")
        if kind == "save" then
            for _, park in global.ipairs(parkList) do
                if park.id == a then
                    chosen = {kind = "save", id = a}
                    session.SetChoice("save", park.name, "Gespeicherter Park" .. (BIOME_NAMES[park.world] and " - " .. BIOME_NAMES[park.world] or ""))
                end
            end
        elseif kind == "new" and BIOME_NAMES[a] then
            chosen = {kind = "new", biome = a, creative = b == "1"}
            session.SetChoice("new", "Neuer Sandbox-Park", BIOME_NAMES[a] .. (b == "1" and " - Kreativ" or " - mit Budget"))
        elseif kind == "franchise" then
            chosen = {kind = "franchise"}
            session.SetChoice("franchise", "Franchise", "Park im Franchise-Menue")
        else
            chosen = nil
            session.SetChoice(nil)
        end
    end,
    -- Host opens the chosen park; everyone in the lobby then loads it.
    start = function()
        if not choosing() or not chosen then return end
        local Parks = global.require("pc2coop.parks")
        local ok, failure
        if chosen.kind == "save" then ok, failure = Parks.Load(frontendMenu.parkLoadSaveManager, chosen.id)
        elseif chosen.kind == "new" then ok, failure = Parks.New(frontendMenu, chosen.biome, chosen.creative, "PC2Coop Park")
        else return end
        emit("ui:start|" .. chosen.kind .. "|" .. global.tostring(ok) .. "|" .. global.tostring(failure))
        if ok then
            session.MarkStarting()
            Ui.SetOpen(false)
        else
            session.Notice("Der Park konnte nicht geoeffnet werden (" .. global.tostring(failure) .. ").", "ff922b")
        end
    end,
    guard = function(arg) session.SetContentGuard(arg ~= "0") end,
    join_friend = function(arg) session.JoinFriend(arg) end,
    rejoin = function() session.Rejoin() end,
    forget_rejoin = function() session.ForgetRejoin() end,
}

-- Events from the Gameface layer arrive as global UI events; Lua listens through an
-- invisible view of its own (only a view can register listeners).
local bridge, bridgeReady = nil, false

local function onRequest(_, raw)
    if global.type(raw) ~= "string" or raw == lastRequest then return end
    lastRequest = raw
    local _, command, argument = global.string.match(raw, "^(%d+)|([%w_]+)|(.*)$")
    local action = command and actions[command]
    if action then
        if command ~= "chat" and command ~= "hello" then emit("ui:request|" .. command .. "|" .. frames) end
        local okAction, failure = global.pcall(action, argument)
        if not okAction then emit("ui:request-error|" .. command .. "|" .. global.tostring(failure)) end
        lastState = nil
    end
end

local function onLog(_, text) emit("js|" .. global.tostring(text)) end

-- Listen on every game view for the layer's events (the layer lives in HUD/FrontEnd).
local registered = global.setmetatable({}, {__mode = "k"})

local function ensureBridge()
    local views = global.api.ui2.__pc2coopViews
    if global.type(views) ~= "table" then return end
    for _, entry in global.ipairs(views) do
        if entry.view ~= nil and not registered[entry.view] then
            registered[entry.view] = true
            global.pcall(global.api.ui2.RequestRegisterForEvent, entry.view, "PC2Coop_Request", 1, onRequest, Ui)
            global.pcall(global.api.ui2.RequestRegisterForEvent, entry.view, "PC2Coop_Log", 1, onLog, Ui)
            bridgeReady = true
        end
    end
end

function Ui.Tick()
    frames = frames + 1
    local ok, failure = global.pcall(function()
        ensureBridge()
        local ctx = ensureContext()
        if frames % 10 == 0 or lastState == nil then
            local state = json(buildState())
            if state ~= lastState then
                global.api.ui2.SetDataStoreElement(ctx, "state", state)
                lastState = state
            end
            if frames % 30 == 0 then
                local pictures = json(session.Avatars())
                if pictures ~= lastAvatars then
                    lastAvatars = pictures
                    global.pcall(global.api.ui2.SetDataStoreElement, ctx, "avatars", pictures)
                end
            end
        end
    end)
    if not ok and frames % 600 == 1 then emit("ui:error|" .. global.tostring(failure)) end
end

function Ui.Shutdown()
    open = false
    bridgeReady = false
    context, lastState, lastRequest, lastAvatars = nil, nil, nil, nil
end

return Ui
