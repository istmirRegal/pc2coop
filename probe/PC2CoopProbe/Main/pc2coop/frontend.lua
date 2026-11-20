-- Original MIT code. Multiplayer while the main menu is open: the same session and Gameface
-- layer as in a park: the host opens a lobby here, friends join it, and everyone loads the
-- park the host then opens.
local global = _G
local Frontend = {}

local state

-- No world in the menu: nothing to sync until the host's park is loaded.
local idleSync = {Receive = function() end, LocalPart = function() return nil end}

function Frontend.Tick(menu)
    if not state then
        local diagnostic = global.require("pc2coop.diagnostic")
        local session = global.require("pc2coop.session")
        local ui = global.require("pc2coop.ui")
        local write = function(tag) return function(message) diagnostic.Write(tag .. message) end end
        session.SetContext("menu")
        session.Init(write("[PC2CoopSession] "), diagnostic, idleSync, menu.parkLoadSaveManager)
        ui.Init(write("[PC2CoopUI] "), session, idleSync, nil)
        ui.SetCanHost(true)
        ui.SetFrontend(menu)
        session.OnMenuKey = function() ui.Toggle() end
        session.OnChatKey = function() ui.ChatKey() end
        state = {session = session, ui = ui, menu = menu, diagnostic = diagnostic}
        diagnostic.Write("[PC2CoopSession] frontend-init")
    elseif state.menu ~= menu then
        state.menu = menu
        local diagnostic = state.diagnostic
        state.session.Init(function(message) diagnostic.Write("[PC2CoopSession] " .. message) end, diagnostic,
            idleSync, menu.parkLoadSaveManager)
        state.ui.SetFrontend(menu)
    end
    local ok, failure = global.pcall(state.session.Tick)
    if not ok then state.diagnostic.Write("[PC2CoopSession] frontend-tick-error|" .. global.tostring(failure)) end
    global.pcall(state.ui.Tick)
end

-- The menu's session instance (the menu's require does not cache modules).
function Frontend.Session() return state and state.session end
function Frontend.Ui() return state and state.ui end

function Frontend.Shutdown()
    if not state then return end
    global.pcall(state.ui.Shutdown)
    global.pcall(state.ui.SetCanHost, true)
    global.pcall(state.ui.SetFrontend, nil)
    state = nil
end

return Frontend
