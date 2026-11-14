-- Original MIT code. In-game co-op menu (F7) built on the game's own dialog stack.
-- Titles and button labels are translated by the UI, so they use STRING_LITERAL; the
-- description is shown as plain text (DialogApp.js).
local global = _G
local Menu = {}

local emit = function() end
local environment, session, sync, labels
local dialogId
local page = "main"
Menu.labelsEnabled = true
Menu.syncPaused = false

local function literal(text)
    return "[STRING_LITERAL:Value=|" .. global.string.gsub(global.tostring(text), "[|%[%]]", "") .. "|]"
end

local function dialogs() return environment:RequireInterface("Interfaces.IDialogStack") end

local function scenario()
    local ok, manager = global.pcall(function() return environment:RequireInterface("Interfaces.IScenarioManager") end)
    return ok and manager or nil
end

-- Franchise parks are stored by Frontier; the host's normal saves upload them.
function Menu.FranchiseInfo()
    local manager = scenario()
    if not manager then return nil end
    local ok, isFranchise = global.pcall(function() return manager:IsFranchiseMode() end)
    if not ok or not isFranchise then return nil end
    local data = manager:GetFranchiseData() or {}
    return {id = data.nFranchiseID, node = data.nNodeID}
end

local ACT = {baut = "baut gerade", schaut = "schaut sich um", empfaengt = "uebernimmt Aenderungen"}

local function statusText()
    local view = session.View()
    local lines = {}
    if not session.Available() then
        lines[#lines+1] = "Steam-Verbindung nicht verfuegbar (DLL fehlt oder Steam laeuft nicht)."
    elseif not view.role then
        lines[#lines+1] = "Keine Sitzung. Hoste einen Raum und lade Freunde ueber Steam ein."
    elseif view.role == "host" then
        lines[#lines+1] = "Du bist Host. Freunde treten ueber die Steam-Einladung bei und bekommen deinen Park."
    else
        lines[#lines+1] = "Verbunden mit dem Host."
    end
    local franchise = Menu.FranchiseInfo()
    if franchise then
        lines[#lines+1] = "Franchise-Park: Speichern laedt den gemeinsamen Stand ins Franchise hoch; danach kann jeder dort weiterbauen."
    end
    if view.role then
        lines[#lines+1] = ""
        lines[#lines+1] = "Spieler:"
        for _, p in global.pairs(view.players) do
            local me = p.sid == view.me and " (du)" or ""
            lines[#lines+1] = "  " .. p.name .. me .. " - " .. (ACT[p.act] or "laedt / wartet")
        end
        lines[#lines+1] = ""
        lines[#lines+1] = "Gebaut / bearbeitet / geloescht:"
        for name, s in global.pairs(view.stats or {}) do
            lines[#lines+1] = "  " .. name .. ": " .. (s.created or 0) .. " / " .. (s.edited or 0) .. " / " .. (s.deleted or 0)
        end
        if (view.conflicts or 0) > 0 then
            lines[#lines+1] = "Aufgeloeste gleichzeitige Bearbeitungen: " .. view.conflicts
        end
        local feed = view.feed or {}
        if #feed > 0 then
            lines[#lines+1] = ""
            lines[#lines+1] = "Zuletzt:"
            for i = global.math.max(1, #feed - 4), #feed do lines[#lines+1] = "  " .. feed[i] end
        end
    end
    return global.table.concat(lines, "\n")
end

local function devText()
    local view = session.View()
    local s = sync.Stats and sync.Stats() or {}
    local lines = {
        "Rolle: " .. global.tostring(view.role or "-") .. "   Steam-ID: " .. global.tostring(view.me or "-"),
        "Lobby: " .. global.tostring(view.lobby or "-"),
        "Sync aktiv: " .. global.tostring(s.active) .. "   pausiert: " .. global.tostring(Menu.syncPaused),
        "Bekannte Objekte: " .. global.tostring(s.known) .. "   Startpark-Objekte: " .. global.tostring(s.baseline),
        "Warteschlange: " .. global.tostring(s.inbound) .. "   letzte Op: " .. global.tostring(s.lastSeq),
        "Namensschilder: " .. (Menu.labelsEnabled and "an" or "aus") .. "   API-Rekorder: "
            .. (global.require("pc2coop.recorder").IsEnabled() and "AN (baue Wege/Fahrgeschaefte/Achterbahnen)" or "aus"),
        "Log: Win64/ovldata/PC2CoopProbe, Datei pc2coop-diagnostic-PROZESSNUMMER.log",
    }
    return global.table.concat(lines, "\n")
end

local function hide()
    if dialogId then global.pcall(function() dialogs():HideDialog(dialogId) end) end
    dialogId = nil
end

local show

local actions = {
    host = function() session.Host(); emit("menu:host") end,
    invite = function() session.Invite(); emit("menu:invite") end,
    leave = function() session.Leave(); emit("menu:leave") end,
    dev = function() page = "dev"; return true end,
    back = function() page = "main"; return true end,
    recorder = function()
        local recorder = global.require("pc2coop.recorder")
        recorder.SetEnabled(not recorder.IsEnabled())
        return true
    end,
    labels = function() Menu.labelsEnabled = not Menu.labelsEnabled; if not Menu.labelsEnabled then labels.Clear() end; return true end,
    pause = function() Menu.syncPaused = not Menu.syncPaused; sync.SetPaused(Menu.syncPaused); return true end,
    refresh = function() return true end,
    dump = function() emit("menu:state|" .. global.string.gsub(statusText() .. "\n" .. devText(), "\n", " / ")); return true end,
}

local function jumpTo(sid)
    for _, p in global.pairs(session.View().players) do
        if p.sid == sid and p.x then
            sync.Receive("C|" .. p.x .. "|" .. p.y .. "|" .. p.z .. "|" .. (p.yaw or 0) .. "|-0.5")
        end
    end
end

local function onSelect(_, id)
    hide()
    local reopen = false
    if actions[id] then
        local ok, result = global.pcall(actions[id])
        if not ok then emit("menu:error|" .. global.tostring(result)) end
        reopen = ok and result == true
    elseif global.string.sub(id, 1, 5) == "jump:" then
        jumpTo(global.string.sub(id, 6))
    end
    if reopen then show() end
end

local function button(id, label) return {id = id, label = literal(label), inputName = id == "close" and "UI_Cancel" or nil} end

show = function()
    hide()
    local view = session.View()
    local buttons, title, content = {}, "PC2 Co-op", statusText()
    if page == "dev" then
        title = "PC2 Co-op - Entwickler"
        content = devText()
        buttons = {button("recorder", "API-Rekorder an/aus"), button("labels", "Namensschilder an/aus"),
            button("pause", "Sync pausieren/fortsetzen"), button("back", "Zurueck")}
    else
        if not view.role then
            buttons[#buttons+1] = button("host", "Raum hosten")
        elseif view.role == "host" then
            buttons[#buttons+1] = button("invite", "Freunde einladen")
            buttons[#buttons+1] = button("leave", "Sitzung beenden")
        else
            buttons[#buttons+1] = button("leave", "Sitzung verlassen")
        end
        local jumps = 0
        for _, p in global.pairs(view.players or {}) do
            if p.sid ~= view.me and p.x and jumps < 2 then
                jumps = jumps + 1
                buttons[#buttons+1] = button("jump:" .. p.sid, "Zu " .. p.name)
            end
        end
        buttons[#buttons+1] = button("dev", "Entwickler")
        buttons[#buttons+1] = button("close", "Schliessen")
    end
    -- Content given as a list is wrapped by the UI into a string literal (no markup parsing).
    local data = {title = literal(title), content = {{label = content, translate = false}}, buttons = buttons}
    dialogId = dialogs():ShowDialog(0, data, Menu, onSelect)
    emit("menu:shown|" .. page)
end

function Menu.Init(logger, env, sessionModule, syncModule, labelsModule)
    emit, environment, session, sync, labels = logger, env, sessionModule, syncModule, labelsModule
end

function Menu.Toggle()
    if dialogId then hide(); return end
    page = "main"
    local ok, failure = global.pcall(show)
    if not ok then emit("menu:error|" .. global.tostring(failure)) end
end

function Menu.Shutdown() hide() end

return Menu
