-- Original MIT code. Visitor mode: a player walks through the park as a guest, with the
-- game's own cameras: "Walking" (first person, 1.65 m eye height, WASD) and the ride
-- camera of the ride settings screen (GamefaceCameraSettings -> FirstPersonRide).
-- The others see it through the normal presence: activity text and the marker at the
-- visitor's feet. Ratings and emotes travel through the session (session.lua).
local global = _G
local Visitor = {}

local EYE = 1.65               -- WalkingCamera.Height of the game
local active = false
local riding = nil             -- {key, name} while on a ride
local rideStarted = 0
local startedAt = 0
local frames = 0
local lastList, listFrame = {}, -1000

local function apis() return global.api.world.GetWorldAPIs() end
local function camera() return apis().CameraModeManager end
local function mode() return global.tostring(camera():GetCurrentModeName()) end

local function uiMode()
    local ok, name = global.pcall(function()
        local BaseUIMode = global.require("Editors.Shared.BaseUIMode")
        return apis().UIModeHelperComponent:GetCurrentModeName(BaseUIMode.GetModeHelperEntity())
    end)
    return ok and global.tostring(name) or "?"
end

local function walk()
    camera():RequestMode("Walking", {bCursor = false})
end

function Visitor.Active() return active end
function Visitor.Riding() return riding end

-- Leave every tool, then walk from where the camera looks.
function Visitor.Start()
    global.pcall(function() global.require("Editors.Shared.BaseUIMode").SetNewMode("Select") end)
    walk()
    active, riding, startedAt = true, nil, frames
    return true
end

function Visitor.Stop()
    if riding then global.pcall(function() global.require("Editors.Shared.BaseUIMode").SetNewMode("Select") end) end
    global.pcall(function() camera():RequestDefaultMode() end)
    active, riding = false, nil
end

local function stationsOf(ride)
    local ok, list = global.pcall(function() return apis().rides:GetStationsForRide(ride) end)
    return ok and global.type(list) == "table" and list or {}
end

-- Rides of the park with what a guest sees: {key, name, kind, e, f, n, queue, trains, dist}.
-- e/f/n are nil until the ride was tested. keyOf: shared ride id (sync.RideKey).
function Visitor.Rides(keyOf, cache)
    if cache and frames - listFrame < 60 then return lastList end
    local out, seen = {}, {}
    local w = apis()
    local okC, cam = global.pcall(function() return camera():GetPosYPRZoom() end)
    local stations = {}
    global.pcall(function() stations = w.ridestation:GetAllStations() or {} end)
    for _, station in global.ipairs(stations) do
        global.pcall(function()
            local ride = w.ridestation:GetRideEntityIDFromStationEntityID(station)
            if not ride or seen[ride] then return end
            seen[ride] = true
            local key = keyOf(ride)
            if not key then return end
            local info = w.rides:GetRideInfo(ride) or {}
            local entry = {key = key, name = global.tostring(w.rides:GetRideName(ride) or "?"),
                kind = info.type == "tracked" and (info.isWaterSlide and "Rutsche" or (info.isCoaster and "Achterbahn" or "Bahn"))
                    or "Fahrgeschaeft", trains = info.numTrains}
            local s = stationsOf(ride)[1]
            local okS, stats = global.pcall(function() return w.ridestats:GetStationStatsLastOnly(s) end)
            if okS and global.type(stats) == "table" then
                entry.e, entry.f, entry.n = stats.Excitement, stats.Fear, stats.Nausea
                entry.queue = stats.QueueLength
            end
            if okC and cam then
                local p = global.api.transform.CalculateWorldTransform(ride):GetPos()
                local dx, dz = p:GetX() - cam:GetX(), p:GetZ() - cam:GetZ()
                entry.dist = global.math.floor(global.math.sqrt(dx * dx + dz * dz) + 0.5)
            end
            out[#out+1] = entry
        end)
    end
    global.table.sort(out, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
    lastList, listFrame = out, frames
    return out
end

-- Ride along: the game's ride camera for that ride (first person in a seat).
function Visitor.Ride(key, findRide)
    local ride = findRide(key)
    if not ride then return false, "nicht gefunden" end
    local info = apis().rides:GetRideInfo(ride) or {}
    local kind = info.type == "tracked" and "TrackedRide" or "FlatRide"
    local name = global.tostring(apis().rides:GetRideName(ride) or "?")
    local GamefaceBaseUIMode = global.require("Editors.Gameface.GamefaceBaseUIMode")
    GamefaceBaseUIMode.SetNewMode("GamefaceCameraSettings", ride, kind)
    active, riding, rideStarted = true, {key = key, name = name}, frames
    return true
end

-- Every frame: notices when the player leaves the walk or the ride with the game's own
-- keys. After a ride the visitor walks on from there.
function Visitor.Tick()
    frames = frames + 1
    if not active or frames % 15 ~= 0 then return end
    local ok, current = global.pcall(mode)
    if not ok then return end
    if riding then
        if frames - rideStarted > 60 and uiMode() ~= "GamefaceCameraSettings"
            and current ~= "FirstPersonRide" and current ~= "ThirdPersonRide" then
            riding, startedAt = nil, frames
            global.pcall(walk)
        end
    elseif current ~= "Walking" and frames - startedAt > 60 then
        -- The game's keys left the walk (e.g. the camera reset key): stay a builder.
        active = false
    end
end

-- Activity text for the others, or nil when not a visitor.
function Visitor.Activity()
    if not active then return nil end
    if riding then return "faehrt " .. global.string.gsub(riding.name, "[|,;\n]", "") end
    return "geht als Besucher durch den Park"
end

-- Where the others draw the visitor: at the feet, not at the eyes.
function Visitor.Feet()
    if not active or riding then return nil end
    local ok, pos = global.pcall(function() return camera():GetPosYPRZoom() end)
    if not ok or not pos then return nil end
    return pos:WithY(pos:GetY() - EYE)
end

function Visitor._Reset() active, riding, frames, lastList, listFrame = false, nil, 0, {}, -1000 end

return Visitor
