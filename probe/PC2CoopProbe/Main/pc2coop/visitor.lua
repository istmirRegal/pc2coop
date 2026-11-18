-- Original MIT code. Visitor mode: a player walks through the park as a guest.
--
-- Third person (default): a figure (a guest statue of the park scenery) moved by
-- our own controller - WASD relative to the camera, Shift to run, a physics ray against
-- buildings/props/rides so the figure does not walk through things, the ground below from
-- terrain, paths and platforms. The game's "Avatar" camera follows it: it takes a change
-- source (GetFocusPoints, GetRotation ...) and smooths behind the figure.
-- First person (fallback, or when the figure prefab is missing): the game's "Walking" camera.
--
-- Keys come from the DLL while visitor mode is on (Tab back to building, T held: emote wheel,
-- E: ride the nearest ride, 1-6 in the wheel); with mouse look the DLL keeps the cursor in the
-- middle and sends its travel, which turns the camera.
-- Riding along uses the game's ride camera (GamefaceCameraSettings -> FirstPersonRide); the
-- guest view the game's VisitorCamera mode. The others see the visitor through presence:
-- activity text and, in their game, the same figure at the visitor's feet (viz.lua).
local global = _G
local Visitor = {}

-- A guest statue of the park scenery. NOT peep_avatar_startscreen: that one crashes the game
-- when it is created in a park (tested 1.12.0).
Visitor.FIGURE = "my_stoneguests_01_game"
Visitor.FIGURE_YAW = global.math.pi / 2   -- the statue looks along -x; turn it to the walking direction
Visitor.EMOTES = {"wave", "cheer", "laugh", "up", "down", "sick"}

local EYE = 1.65               -- WalkingCamera.Height of the game
local WALK, RUN = 3.2, 7.5     -- metres per second
local STEP = 0.6               -- highest step the figure climbs
local active = false
local mode = "third"           -- "third" or "first"
local preferred = "third"
local riding = nil             -- {key, name} while on a ride
local guestView = false        -- the game's visitor camera: looking over a guest's shoulder
local rideStarted = 0
local startedAt = 0
local frames = 0
local lastList, listFrame = {}, -1000
local net = function() end     -- DLL command
local onEmote = function() end
local pos = nil                -- feet of the figure (third person): {x, y, z}
local facing = 0               -- radians around Y
local figure = nil             -- {entity, token, ready}
local pendingYaw = 0
local wheel = nil              -- {x, y, selected} while T is held
local lastNet = -1000
local physicsWorld
local testKeys = nil           -- QA: {binding = true} instead of the keyboard

local function apis() return global.api.world.GetWorldAPIs() end
local function camera() return apis().CameraModeManager end
local function cameraMode() return global.tostring(camera():GetCurrentModeName()) end
local function V(x, y, z) return global.require("Vector3"):new(x, y, z) end

local function uiMode()
    local ok, name = global.pcall(function()
        local BaseUIMode = global.require("Editors.Shared.BaseUIMode")
        return apis().UIModeHelperComponent:GetCurrentModeName(BaseUIMode.GetModeHelperEntity())
    end)
    return ok and global.tostring(name) or "?"
end

function Visitor.Init(netCommand, emote)
    net = netCommand or net
    onEmote = emote or onEmote
end

function Visitor.Active() return active end
function Visitor.Riding() return riding end
function Visitor.GuestView() return guestView end
function Visitor.View() return mode end
function Visitor.Wheel() return wheel end

-- Ground below (x, z) near the height y: terrain, paths and pools, platforms and bridges.
local function groundAt(x, y, z)
    local best
    local function take(h) if h and h <= y + STEP and (not best or h > best) then best = h end end
    global.pcall(function()
        local terrain = apis().voxelterrain
        local top = y + 3
        local d = terrain:RayCast(terrain:GetPrimaryVoxelTerrainEntityID(), V(x, top, z), V(0, -1, 0), 200)
        if d then take(top - d) end
    end)
    global.pcall(function()
        local top = y + 3
        local d = apis().volumes:Raycast(V(x, top, z), V(0, -1, 0))
        if d then take(top - d) end
    end)
    global.pcall(function()
        physicsWorld = physicsWorld or global.api.entity.FindEntityByName("MainPhysicsWorld")
        local ph = global.api.physics
        local hits = ph.RayCast(physicsWorld, V(x, y + 2, z), V(x, y - 30, z), ph.Flag_Building | ph.Flag_Prop, 4) or {}
        for _, hit in global.ipairs(hits) do
            local p = hit.vPos or hit.vPosition or hit.vHitPos
            if p and not (figure and hit.nEntityID == figure.entity) then take(p:GetY()) end
        end
    end)
    return best
end

-- Something solid between a and b at hip height?
local function blocked(ax, ay, az, bx, bz)
    local ok, hit = global.pcall(function()
        physicsWorld = physicsWorld or global.api.entity.FindEntityByName("MainPhysicsWorld")
        local ph = global.api.physics
        local dx, dz = bx - ax, bz - az
        local len = global.math.sqrt(dx * dx + dz * dz)
        if len < 1e-4 then return false end
        local reach = 0.45 / len
        local hits = ph.RayCast(physicsWorld, V(ax, ay + 0.9, az), V(bx + dx * reach, ay + 0.9, bz + dz * reach),
            ph.Flag_Building | ph.Flag_Prop | ph.Flag_Ride | ph.Flag_Track, 4) or {}
        for _, hit in global.ipairs(hits) do
            if not (figure and hit.nEntityID == figure.entity) then return true end   -- not the own figure
        end
        return false
    end)
    return ok and hit
end

local function rotationY(angle)
    local Q = global.require("Quaternion")
    return Q.Identity:WithX(0):WithY(global.math.sin(angle / 2)):WithZ(0):WithW(global.math.cos(angle / 2))
end

local function placeFigure()
    if not figure or not pos then return end
    global.pcall(function()
        local E, X = global.api.entity, global.api.transform
        if not figure.ready then
            if not (E.HaveRequestsCompleted(figure.token) and X.HasTransform(figure.entity)) then return end
            figure.ready = true
        end
        X.SetTransform(figure.entity, global.require("TransformQ").FromOrPos(rotationY(facing + Visitor.FIGURE_YAW), V(pos.x, pos.y, pos.z)))
    end)
end

local function dropFigure()
    if figure then global.pcall(global.api.entity.DestroyEntity, figure.entity) end
    figure = nil
end

local function spawnFigure()
    local ok, entity, token = global.pcall(function()
        local E = global.api.entity
        if not E.FindPrefab(Visitor.FIGURE) then return nil end
        local t = E.CreateRequestCompletionToken()
        local TQ, Q = global.require("TransformQ"), global.require("Quaternion")
        return E.InstantiatePrefab(Visitor.FIGURE, nil, t, TQ.FromOrPos(Q.Identity, V(pos.x, pos.y, pos.z))), t
    end)
    if ok and entity then figure = {entity = entity, token = token, ready = false} end
    return figure ~= nil
end

local function head() return V(pos.x, pos.y + 1.6, pos.z) end

-- The game's Avatar camera behind the figure; it follows GetFocusPoints and turns by GetRotation.
local function avatarCamera()
    local source = {}
    function source.GetFocusPoints() local h = head(); return h, h end
    function source.GetRotation() local r = pendingYaw; pendingYaw = 0; return r end
    function source.GetZoomRequest() return nil, nil end
    function source.NotifyOfMouseInput() end
    camera():RequestMode("Avatar", {vTarget = head(), vOffset = V(0, 1.6, -5), nZoomMin = 2.5, nZoomMax = 14,
        nPitchMin = -1.3, nPitchMax = 0.35, tChangeSource = source})
end

local function walk()
    camera():RequestMode("Walking", {bCursor = false})
end

local function startThird()
    -- where the player looks (the placement focus is (0,0,0) without a tool)
    local ok, focus = global.pcall(function() return global.require("pc2coop.world").FocusPoint() end)
    if not ok or not focus then ok, focus = global.pcall(function() return camera():GetPlacementFocusPos() end) end
    if not ok or not focus then return false end
    pos = {x = focus:GetX(), y = focus:GetY(), z = focus:GetZ()}
    pos.y = groundAt(pos.x, pos.y + 2, pos.z) or pos.y
    if not spawnFigure() then pos = nil; return false end
    local okC = global.pcall(avatarCamera)
    if not okC then dropFigure(); pos = nil; return false end
    return true
end

local function keepInput()
    if frames - lastNet >= 60 then
        lastNet = frames
        net("visitor|1|" .. ((active and not riding and not guestView and not wheel) and "1" or "0"))
    end
end

-- Leave every tool, then walk from where the camera looks. view: "third" or "first".
function Visitor.Start(view)
    if view == "first" or view == "third" then preferred = view end
    global.pcall(function() global.require("Editors.Shared.BaseUIMode").SetNewMode("Select") end)
    mode = "first"
    if preferred == "third" and startThird() then mode = "third" else walk() end
    active, riding, guestView, wheel, startedAt = true, nil, false, nil, frames
    lastNet = -1000
    keepInput()
    return true
end

function Visitor.Stop()
    if riding or guestView then global.pcall(function() global.require("Editors.Shared.BaseUIMode").SetNewMode("Select") end) end
    global.pcall(function() camera():RequestDefaultMode() end)
    dropFigure()
    pos, active, riding, guestView, wheel = nil, false, nil, false, nil
    net("visitor|0|0")
end

-- The game's own first person walk (VisitorCamera UI mode, "Visitor" camera: floor, jump,
-- crouch, swim, lamp, interact), started where the figure stands or the player looks.
-- The figure goes away meanwhile (it would stand in the way) and comes back afterwards.
function Visitor.WatchGuest()
    local init = nil
    global.pcall(function()
        local at = pos and V(pos.x, pos.y, pos.z) or global.require("pc2coop.world").FocusPoint()
        local _, ypr = camera():GetPosYPRZoom()
        local yaw = ypr and ypr:GetX() or 0
        init = {bCursor = true, startingTransform = global.require("TransformQ").FromOrPos(rotationY(yaw), V(at:GetX(), at:GetY() + EYE, at:GetZ()))}
    end)
    dropFigure()
    global.require("Editors.Shared.BaseUIMode").SetNewMode("VisitorCamera", init)
    active, riding, guestView, rideStarted = true, nil, true, frames
    return true
end

local function stationsOf(ride)
    local ok, list = global.pcall(function() return apis().rides:GetStationsForRide(ride) end)
    return ok and global.type(list) == "table" and list or {}
end

-- Rides of the park with what a guest sees: {key, name, kind, e, f, n, queue, trains, dist}.
-- e/f/n are nil until the ride was tested. keyOf: shared ride id (sync.RideKey).
-- at: {x, z} to sort by the distance to that spot (no cache then).
function Visitor.Rides(keyOf, cache, at)
    if cache and not at and frames - listFrame < 60 then return lastList end
    local out, seen = {}, {}
    local w = apis()
    local from
    if at then from = at
    elseif pos then from = {pos.x, pos.z}
    else
        local okC, cam = global.pcall(function() return camera():GetPosYPRZoom() end)
        if okC and cam then from = {cam:GetX(), cam:GetZ()} end
    end
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
            if from then
                local p = global.api.transform.CalculateWorldTransform(ride):GetPos()
                local dx, dz = p:GetX() - from[1], p:GetZ() - from[2]
                entry.dist = global.math.floor(global.math.sqrt(dx * dx + dz * dz) + 0.5)
            end
            out[#out+1] = entry
        end)
    end
    global.table.sort(out, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
    if not at then lastList, listFrame = out, frames end
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

-- E: the nearest ride within 25 m.
function Visitor.Interact(keyOf, findRide)
    local list = Visitor.Rides(keyOf)
    local near = list[1]
    if not near or not near.dist or near.dist > 25 then return false, "kein Fahrgeschaeft in der Naehe" end
    return Visitor.Ride(near.key, findRide)
end

-- Keys from the DLL (only while visitor mode is on). Returns "stop", "interact" or nil.
function Visitor.OnKey(name, down)
    if not active then return nil end
    if name == "tab" and down then return "stop" end
    if name == "e" and down and not riding and not guestView then return "interact" end
    if name == "t" then
        if down and not riding and not wheel then wheel = {x = 0, y = 0, selected = nil}; lastNet = -1000; keepInput()
        elseif not down and wheel then
            local chosen = wheel.selected
            wheel = nil
            lastNet = -1000; keepInput()
            if chosen then onEmote(Visitor.EMOTES[chosen]) end
        end
        return nil
    end
    local digit = global.tonumber(name)
    if digit and down and wheel and Visitor.EMOTES[digit] then wheel.selected = digit end
    return nil
end

-- Mouse travel from the DLL: turns the camera, or picks a wedge of the emote wheel.
function Visitor.OnMouse(dx, dy)
    if not active then return end
    if wheel then
        wheel.x, wheel.y = wheel.x + dx, wheel.y + dy
        if wheel.x * wheel.x + wheel.y * wheel.y > 900 then
            -- six wedges clockwise from the top
            local angle = global.math.atan(wheel.x, -wheel.y)
            if angle < 0 then angle = angle + 2 * global.math.pi end
            wheel.selected = global.math.floor((angle + global.math.pi / 6) / (global.math.pi / 3)) % 6 + 1
        end
        return
    end
    if mode == "third" then
        pendingYaw = pendingYaw + dx * 0.0035 / (global.math.pi * 0.4)
    else
        global.pcall(function()
            local p, ypr = camera():GetPosYPRZoom()
            camera():SetPosYPR(p, V(ypr:GetX() + dx * 0.0035, global.math.max(-1.3, global.math.min(1.3, ypr:GetY() - dy * 0.0035)), 0))
        end)
    end
end

-- Third person: move the figure by WASD relative to the camera, stop at walls, follow ground.
local function advanceFigure()
    if not pos then return end
    local im = apis().InputManager
    local keys = camera():GetKeyBindings() or {}
    local function down(binding)
        if testKeys then return testKeys[binding] == true end
        local ok, v = global.pcall(function() return im:GetKeyDown(binding) end)
        return ok and v
    end
    local fx, fz = 0, 0
    local okC, cam = global.pcall(function() return camera():GetPosYPRZoom() end)
    if okC and cam then fx, fz = pos.x - cam:GetX(), pos.z - cam:GetZ() end
    local len = global.math.sqrt(fx * fx + fz * fz)
    if len < 1e-3 then fx, fz, len = 0, 1, 1 end
    fx, fz = fx / len, fz / len
    local rx, rz = fz, -fx
    local ix, iz = 0, 0
    if down(keys.Forward) then iz = iz + 1 end
    if down(keys.Backward) then iz = iz - 1 end
    if down(keys.Right) then ix = ix + 1 end
    if down(keys.Left) then ix = ix - 1 end
    if ix ~= 0 or iz ~= 0 then
        local speed = (down(keys.SpeedMod) and RUN or WALK) / 60
        local mx, mz = fx * iz + rx * ix, fz * iz + rz * ix
        local m = global.math.sqrt(mx * mx + mz * mz)
        mx, mz = mx / m * speed, mz / m * speed
        facing = global.math.atan(mx, mz)
        local nx, nz = pos.x + mx, pos.z + mz
        if blocked(pos.x, pos.y, pos.z, nx, nz) then
            -- slide along the wall
            if not blocked(pos.x, pos.y, pos.z, nx, pos.z) then nz = pos.z
            elseif not blocked(pos.x, pos.y, pos.z, pos.x, nz) then nx = pos.x
            else nx, nz = pos.x, pos.z end
        end
        local ny = groundAt(nx, pos.y, nz)
        if ny then pos.x, pos.y, pos.z = nx, ny, nz end
    end
    placeFigure()
end

-- Every frame: the controller, and noticing when the player leaves with the game's own keys.
function Visitor.Tick()
    frames = frames + 1
    if not active then return end
    keepInput()
    if mode == "third" and not riding and not guestView then
        global.pcall(advanceFigure)
    end
    if frames % 15 ~= 0 then return end
    local ok, current = global.pcall(cameraMode)
    if not ok then return end
    if guestView then
        if frames - rideStarted > 60 and uiMode() ~= "VisitorCamera" then
            guestView, startedAt = false, frames
            if mode == "third" and pos and (figure or spawnFigure()) then global.pcall(avatarCamera) else global.pcall(walk) end
        end
    elseif riding then
        if frames - rideStarted > 60 and uiMode() ~= "GamefaceCameraSettings"
            and current ~= "FirstPersonRide" and current ~= "ThirdPersonRide" then
            riding, startedAt = nil, frames
            if mode == "third" and pos then global.pcall(avatarCamera) else global.pcall(walk) end
        end
    elseif frames - startedAt > 60 and current ~= (mode == "third" and "Avatar" or "Walking") then
        -- The game's keys left the walk (e.g. the camera reset key): stay a builder.
        Visitor.Stop()
    end
end

-- Activity text for the others, or nil when not a visitor.
function Visitor.Activity()
    if not active then return nil end
    if guestView then return "geht als Besucher in Ich-Sicht durch den Park" end
    if riding then return "faehrt " .. global.string.gsub(riding.name, "[|,;\n]", "") end
    return "geht als Besucher durch den Park"
end

-- Where the others draw the visitor: at the feet, not at the eyes.
function Visitor.Feet()
    if not active or riding then return nil end
    if mode == "third" and pos and not guestView then return V(pos.x, pos.y, pos.z) end
    local ok, p = global.pcall(function() return camera():GetPosYPRZoom() end)
    if not ok or not p then return nil end
    return p:WithY(p:GetY() - EYE)
end

-- QA: walk without a keyboard (the game's own cameras read the real InputManager).
function Visitor._TestKeys(keys) testKeys = keys end

function Visitor._Reset()
    active, riding, guestView, frames, lastList, listFrame = false, nil, false, 0, {}, -1000
    pos, figure, wheel, mode, preferred, pendingYaw = nil, nil, nil, "third", "third", 0
end

return Visitor
