-- Original MIT code. What the co-op session needs to know about, and set in, the running
-- park besides its objects: pause and speed, the park's numbers, its notifications, and
-- what the local player is doing in the editor right now.
local global = _G
local World = {}
local shared = global.require("pc2coop.shared")

local function pack(...) return {n = global.select("#", ...), ...} end

-- Hooks (installed once per loaded game module, from the database) -----------------------

-- Windows.MainHUDGameface: the HUD owns pause and speed (ChangeSimulationSpeedSettings).
function World.HookHUD(module, trace)
    if module.__PC2CoopHUD then return end
    local init, shutdown, change = module.Init, module.Shutdown, module.ChangeSimulationSpeedSettings
    if global.type(init) ~= "function" or global.type(change) ~= "function" then
        trace("world:hud-hook-unavailable")
        return
    end
    module.Init = function(self, ...)
        local results = pack(init(self, ...))
        shared.hud = self
        return global.table.unpack(results, 1, results.n)
    end
    if global.type(shutdown) == "function" then
        module.Shutdown = function(self, ...)
            if shared.hud == self then shared.hud = nil end
            return shutdown(self, ...)
        end
    end
    module.ChangeSimulationSpeedSettings = function(self, ...)
        local results = pack(change(self, ...))
        shared.hud = self
        if not shared.applyingTime and shared.onTime then
            global.pcall(shared.onTime, self.bPaused == true, global.tonumber(self.nTimeScaleIndex) or 1)
        end
        return global.table.unpack(results, 1, results.n)
    end
    -- Undo/redo button and hotkey: only for the player's own newest step (sync decides).
    local request = module.RequestUndoRedo
    if global.type(request) == "function" then
        module.RequestUndoRedo = function(self, isUndo, ...)
            if shared.undoGuard then
                local ok, allowed = global.pcall(shared.undoGuard, isUndo == true)
                if ok and allowed == false then return end
            end
            return request(self, isUndo, ...)
        end
    end
    module.__PC2CoopHUD = true
    trace("world:hud-hook-installed")
end

-- Managers.NotificationManager: breakdowns, services due, protests ... as the game words them.
function World.HookNotifications(module, trace)
    if module.__PC2CoopNotes then return end
    local queue = module.QueueNotification
    if global.type(queue) ~= "function" then trace("world:notification-hook-unavailable"); return end
    module.QueueNotification = function(self, kind, context, contextType, ...)
        local results = pack(queue(self, kind, context, contextType, ...))
        if shared.onNotification then
            global.pcall(function()
                local text = self:GetNotificationString(kind, context, contextType)
                local okE, entity = global.pcall(function() return self:GetEntityFromContext(context, contextType) end)
                if global.type(text) == "string" and text ~= "" then shared.onNotification(text, okE and entity or nil) end
            end)
        end
        return global.table.unpack(results, 1, results.n)
    end
    module.__PC2CoopNotes = true
    trace("world:notification-hook-installed")
end

-- Time ------------------------------------------------------------------------------------

-- paused, speed index (1..3 = x1, x2, x5); nil when the HUD is not up yet.
function World.Time()
    local hud = shared.hud
    if not hud then return nil end
    return hud.bPaused == true, global.tonumber(hud.nTimeScaleIndex) or 1
end

-- Applies pause/speed that another player chose; does not report it back.
function World.SetTime(paused, index)
    local hud = shared.hud
    if not hud then return false end
    local nowPaused, nowIndex = World.Time()
    shared.applyingTime = true
    local ok, failure = global.pcall(function()
        if paused ~= nowPaused then hud:ChangeSimulationSpeedSettings(paused, nil) end
        if index ~= nowIndex and index >= 1 and index <= 3 then hud:ChangeSimulationSpeedSettings(nil, index) end
    end)
    shared.applyingTime = false
    return ok, failure
end

-- Park numbers (the HUD keeps them in the "simulation" data store) ------------------------

function World.Numbers()
    local ok, result = global.pcall(function()
        local ui2 = global.api.ui2
        local ctx = ui2.GetDataStoreContext("simulation")
        local numbers = {
            guests = global.tonumber(ui2.GetDataStoreElement(ctx, "numGuests")),
            cash = global.tonumber(ui2.GetDataStoreElement(ctx, "cash")),
            unlimited = ui2.GetDataStoreElement(ctx, "hasUnlimitedCash") == true,
        }
        return numbers
    end)
    return ok and result or nil
end

-- What the local player does in the editor ---------------------------------------------------

local MODE_TEXT = {
    {"Blueprint", "platziert einen Bauplan"}, {"FlatRide", "platziert ein Fahrgeschäft"},
    {"EntranceExit", "setzt Ein- und Ausgang"}, {"Track", "baut eine Strecke"}, {"Coaster", "baut eine Achterbahn"},
    {"Path", "baut Wege"}, {"Queue", "baut Wege"}, {"Terrain", "formt das Gelände"}, {"Water", "bearbeitet Wasser"},
    {"Pool", "baut einen Pool"}, {"Flume", "baut eine Rutsche"}, {"Scenery", "baut"}, {"Staff", "verwaltet Personal"},
    {"Park", "verwaltet den Park"},
}

local function modeHelper(apis)
    local okE, BaseEditMode = global.pcall(global.require, "Editors.Shared.BaseEditMode")
    local okU, BaseUIMode = global.pcall(global.require, "Editors.Shared.BaseUIMode")
    return okE and BaseEditMode or nil, okU and BaseUIMode or nil
end

-- Returns {ui = UI mode name, edit = edit mode name, text = activity in words,
--          held = {label, resource, x, y, z, qx, qy, qz, qw, scale, parts = {...}}} (held may be nil)
function World.Activity()
    local info = {}
    global.pcall(function()
        local apis = global.api.world.GetWorldAPIs()
        local BaseEditMode, BaseUIMode = modeHelper(apis)
        if not BaseEditMode or not BaseUIMode then return end
        local editEntity, uiEntity = BaseEditMode.GetModeHelperEntity(), BaseUIMode.GetModeHelperEntity()
        info.edit = global.tostring(apis.GameModeHelperComponent:GetCurrentModeName(editEntity))
        info.ui = global.tostring(apis.UIModeHelperComponent:GetCurrentModeName(uiEntity))
        for _, entry in global.ipairs(MODE_TEXT) do
            if global.string.find(info.ui, entry[1], 1, true) or global.string.find(info.edit, entry[1], 1, true) then
                info.text = entry[2]
                break
            end
        end
        local mode = apis.GameModeHelperComponent:GetCurrentMode(editEntity)
        if global.type(mode) ~= "table" then return end
        -- Scenery: the sub mode holds the object; single-feature modes (rides, blueprints) hold it themselves.
        local holder = global.rawget(mode, "subMode") or mode
        local object = global.rawget(holder, "moveObject") or global.rawget(holder, "cMoveObject")
            or global.rawget(mode, "cMoveObject")
        if object == nil then return end
        local okT, transform = global.pcall(function() return object:GetTransform() end)
        if not okT or transform == nil then return end
        local p, q = transform:GetPos(), transform:GetOr()
        local held = {x = p:GetX(), y = p:GetY(), z = p:GetZ(), qx = q:GetX(), qy = q:GetY(), qz = q:GetZ(), qw = q:GetW()}
        local okS, scale = global.pcall(function() return object:GetScale() end)
        held.scale = okS and global.tonumber(scale) or 1
        held.resource = global.rawget(holder, "sPropToMake") or global.rawget(mode, "sFlatRideName")
        if global.type(held.resource) ~= "string" then held.resource = nil end
        local okP, parts = global.pcall(function() return apis.scenery:GetMoveObjectPartIDs(object) end)
        held.parts = okP and global.type(parts) == "table" and parts or {}
        info.held = held
    end)
    return info
end

-- A guest's game shows the host's park: nothing breaks down here on its own and building
-- costs nothing here (the host's park keeps the books). Only works in sandbox mode, which
-- is how a transferred park is opened.
function World.ApplyGuestProfile()
    return global.pcall(function()
        local environment = global.api.world.GetScript(global.api.world.GetActive()).tEnvironment
        local sandbox = environment:RequireInterface("Interfaces.ISandboxSettingsManager")
        local settings = sandbox:GetCurrentSandboxSettings()
        settings.bEnabledBreakdowns = false
        settings.bEnabledServiceBadges = false
        settings.bEnabledLightningConsequences = false
        settings.bEnablePlayerCash = false
        sandbox:SetSandboxSettings(settings)
    end)
end

-- The point on the ground under the mouse cursor (falls back to the camera's focus point).
function World.CursorPoint()
    local ok, x, y, z = global.pcall(function()
        local Vector3 = global.require("Vector3")
        local _, start, direction = global.api.input.GetMouseRay()
        local terrain = global.api.world.GetWorldAPIs().voxelterrain
        local distance = start and direction and terrain:RayCast(terrain:GetPrimaryVoxelTerrainEntityID(), start, direction, 2000)
        -- A ray of length 0 (cursor outside the window) means: no point under the cursor.
        if distance and distance > 0.5 then
            local hit = start + direction * distance
            return hit:GetX(), hit:GetY(), hit:GetZ()
        end
        -- The cursor points above the horizon: 40 m ahead in its direction, on the ground.
        local dx, dz = direction:GetX(), direction:GetZ()
        local length = global.math.sqrt(dx * dx + dz * dz)
        if length < 0.01 then return nil end
        local x, z = start:GetX() + dx / length * 40, start:GetZ() + dz / length * 40
        local top = Vector3:new(x, start:GetY() + 200, z)
        local down = terrain:RayCast(terrain:GetPrimaryVoxelTerrainEntityID(), top, Vector3:new(0, -1, 0), 1000)
        return x, down and (start:GetY() + 200 - down) or start:GetY(), z
    end)
    if ok and global.type(x) == "number" then return x, y, z end
    return nil
end

-- DLC bit mask a placed part needs (0: base game or unknown).
function World.RequiredDLC(part)
    if not part then return 0 end
    local ok, need = global.pcall(function()
        return global.api.world.GetWorldAPIs().scenery:GetRequiredDLCForPart(part)
    end)
    return ok and global.tonumber(need) or 0
end

-- The scenery part the player selected: the object whose info window is open in the
-- normal select mode, or the first of the selection in the scenery editor. Nil otherwise.
function World.SelectedPart()
    local ok, part = global.pcall(function()
        local apis = global.api.world.GetWorldAPIs()
        local BaseEditMode = global.require("Editors.Shared.BaseEditMode")
        local mode = apis.GameModeHelperComponent:GetCurrentMode(BaseEditMode.GetModeHelperEntity())
        if global.type(mode) ~= "table" then return nil end
        local entity = global.rawget(mode, "bEntitySelected") and global.rawget(mode, "nSelectedEntityID")
        if entity then return apis.placement:EntityIDToPlacementID(entity) end
        local context = global.rawget(mode, "editorContext")
        if not context then return nil end
        local selection = context:GetSelectionSet()
        if not selection or selection:CountParts() < 1 then return nil end
        return selection:GetOnePartID()
    end)
    return ok and part or nil
end

-- Camera: position and yaw/pitch, as presence reports them.
-- Where the middle of the view meets the ground. The game's placement focus is (0,0,0)
-- while no tool places anything (tested 1.12.0), so it is only used when it is set.
function World.FocusPoint()
    local ok, point = global.pcall(function()
        local Vector3 = global.require("Vector3")
        local apis = global.api.world.GetWorldAPIs()
        local cam = apis.CameraModeManager
        local okP, focus = global.pcall(function() return cam:GetPlacementFocusPos() end)
        if okP and focus and (global.math.abs(focus:GetX()) + global.math.abs(focus:GetZ())) > 0.01 then return focus end
        local pos, ypr = cam:GetPosYPRZoom()
        local yaw, pitch = ypr:GetX(), ypr:GetY()
        local dir = Vector3:new(global.math.sin(yaw) * global.math.cos(pitch), -global.math.sin(pitch), global.math.cos(yaw) * global.math.cos(pitch))
        local terrain = apis.voxelterrain
        local d = terrain:RayCast(terrain:GetPrimaryVoxelTerrainEntityID(), pos, dir, 2000)
        if d and d > 0.5 then return pos + dir * d end
        return Vector3:new(pos:GetX() + global.math.sin(yaw) * 40, pos:GetY(), pos:GetZ() + global.math.cos(yaw) * 40)
    end)
    if ok then return point end
end

function World.Camera()
    local ok, x, y, z, yaw, pitch = global.pcall(function()
        local position, ypr = global.api.world.GetWorldAPIs().CameraModeManager:GetPosYPRZoom()
        return position:GetX(), position:GetY(), position:GetZ(), ypr:GetX(), ypr:GetY()
    end)
    if ok then return x, y, z, yaw, pitch end
    return nil
end

function World.SetCamera(x, y, z, yaw, pitch)
    return global.pcall(function()
        local Vector3 = global.require("Vector3")
        global.api.world.GetWorldAPIs().CameraModeManager:SetPosYPR(Vector3:new(x, y, z), Vector3:new(yaw, pitch, 0))
    end)
end

-- True while the player moves the camera with mouse or keys (ends "follow").
function World.PlayerMovesCamera()
    local ok, moving = global.pcall(function()
        return global.api.world.GetWorldAPIs().CameraModeManager:IsPlayerTryingToMoveCamera()
    end)
    return ok and moving == true
end

-- Leaves the current editor tool, as a right click does (used when a lock is refused).
function World.LeaveTool()
    return global.pcall(function()
        global.require("Editors.Shared.BaseUIMode").SetNewMode("Select")
    end)
end

return World
