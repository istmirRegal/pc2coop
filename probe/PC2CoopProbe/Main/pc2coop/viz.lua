-- Original MIT code. Shows the other players inside the park, with display-only entities
-- (never part of the park: not placed, not saved, verified by saving and reloading):
--   * a small disc on the ground where a player looks,
--   * a dotted wedge from below their camera towards that spot (direction and visible area),
--   * a tinted ghost of what they hold in the editor while they look for a place,
--   * a tint on objects they are editing (locked for everyone else).
-- All of it uses highlight channel 3 ("custom"), so it has one colour at a time.
local global = _G
local Viz = {}
local shared = global.require("pc2coop.shared")

local emit = function() end
local enabled = true
local players = {}        -- sid -> {marker, dots = {...}, ghosts = {...}, big, signature}
local tinted = {}         -- entity -> true (objects locked by others)
local beacons = {}        -- sid -> {ring, column = {...}}: "here!" pings
local colour = nil
local frames = 0
local failed = false

local CHANNEL = 3
local DISC = "pc_primitive_circle_game"
-- Figure of a player in visitor mode: a guest with the player's look that walks, runs and
-- does the player's emotes (figure.lua). Where no guest figure can be built: a guest statue
-- of the park scenery. NOT peep_avatar_startscreen: that one crashes the game in a park.
local FIGURE = "my_stoneguests_01_game"
local figureChecked, figureFound = false, false
local function figureOK()
    if not figureChecked then
        figureChecked = true
        local ok, found = global.pcall(global.api.entity.FindPrefab, FIGURE)
        figureFound = ok and found ~= nil and found ~= false
    end
    return figureFound
end
-- The wedge: five dots along each edge and three across its far end.
-- Each entry: {share of the half angle, share of the reach}.
local DOTS = {}
for i = 1, 5 do DOTS[#DOTS+1] = {1, i / 5} end
for i = 1, 5 do DOTS[#DOTS+1] = {-1, i / 5} end
for _, share in global.ipairs({-0.5, 0, 0.5}) do DOTS[#DOTS+1] = {share, 1} end
local HALF_ANGLE = 0.47          -- radians, about 27 degrees: a 54 degree wedge
local MAX_GHOSTS = 8
-- Prefab families that must never be instantiated for display (a ride prefab ends the game).
local UNSAFE = {"^fr_", "^tr_", "^cc_", "^ptr_", "^station_", "^track_", "^fl_", "^wp_", "^facility_", "^utility_",
    "^staff", "^guest", "^char_"}

local function E() return global.api.entity end
local function X() return global.api.transform end

local function track(entity)
    shared.vizEntities = shared.vizEntities or {}
    shared.vizEntities[#shared.vizEntities+1] = entity
    return entity
end

local function destroy(entity)
    if entity == nil then return end
    global.pcall(E().DestroyEntity, entity)
    for i, other in global.ipairs(shared.vizEntities or {}) do
        if other == entity then global.table.remove(shared.vizEntities, i); break end
    end
end

local function spawn(prefab, scale)
    local Vector3, Quaternion, TransformQ = global.require("Vector3"), global.require("Quaternion"), global.require("TransformQ")
    local token = E().CreateRequestCompletionToken()
    local ok, entity = global.pcall(E().InstantiatePrefab, prefab, nil, token,
        TransformQ.FromOrPos(Quaternion.Identity, Vector3:new(0, -500, 0)))
    if not ok or entity == nil then return nil end
    return {entity = track(entity), scale = scale, ready = false, token = token, at = nil}
end

-- An entity can be moved once its prefab finished loading.
local function ready(item)
    if item.ready then return true end
    if E().HaveRequestsCompleted(item.token) and X().HasTransform(item.entity) then
        item.ready = true
        global.pcall(X().SetScale, item.entity, item.scale or 1)
        global.pcall(global.api.model.SetHighlighted, item.entity, CHANNEL, true, true)
    end
    return item.ready
end

local function ease(item, x, y, z, dt)
    local at = item.at
    if not at then at = {x, y, z}; item.at = at
    else
        local dx, dy, dz = x - at[1], y - at[2], z - at[3]
        if dx * dx + dy * dy + dz * dz > 150 * 150 then at[1], at[2], at[3] = x, y, z
        else
            local k = 1 - global.math.exp(-(dt or 1 / 60) * 9)
            at[1], at[2], at[3] = at[1] + dx * k, at[2] + dy * k, at[3] + dz * k
        end
    end
    return at
end

local function place(item, x, y, z, dt, rotation)
    if not item or not ready(item) then return end
    local at = ease(item, x, y, z, dt)
    local Vector3 = global.require("Vector3")
    if rotation then
        local TransformQ = global.require("TransformQ")
        X().SetTransform(item.entity, TransformQ.FromOrPos(rotation, Vector3:new(at[1], at[2], at[3])))
        global.pcall(X().SetScale, item.entity, item.scale or 1)
    else
        X().SetPosition(item.entity, Vector3:new(at[1], at[2], at[3]))
    end
end

-- How big a marker is drawn (P6 finding A9: too big, the same up close as far away): by the
-- camera's distance, about the same size on the screen, small when the camera is close.
local camAt, camFrame = nil, -1
local function sizeAt(x, y, z)
    if camFrame ~= frames then
        camFrame = frames
        camAt = nil
        local okW, W = global.pcall(global.require, "pc2coop.world")
        if okW and W and W.Camera then
            local cx, cy, cz = W.Camera()
            if cx then camAt = {cx, cy, cz} end
        end
    end
    if not camAt or not x then return 1 end
    local dx, dy, dz = x - camAt[1], (y or camAt[2]) - camAt[2], z - camAt[3]
    -- About 1/25 of the distance: a ring of a few dozen pixels at any distance (at 1/60 it vanished
    -- from 45 m, test copy).
    return global.math.max(0.5, global.math.min(3, global.math.sqrt(dx * dx + dy * dy + dz * dz) / 25))
end
-- Sets an item's scale when it changed noticeably.
local function resize(item, scale)
    if not item or not item.ready or (item.shown and global.math.abs(item.shown - scale) < 0.02) then return end
    item.shown = scale
    global.pcall(X().SetScale, item.entity, scale)
end

-- Height of the terrain below (x, z); hint is used where the ray finds nothing.
local function ground(x, z, hint)
    local ok, y = global.pcall(function()
        local Vector3 = global.require("Vector3")
        local terrain = global.api.world.GetWorldAPIs().voxelterrain
        local id = terrain:GetPrimaryVoxelTerrainEntityID()
        local top = hint + 80
        local distance = terrain:RayCast(id, Vector3:new(x, top, z), Vector3:new(0, -1, 0), 400)
        return distance and (top - distance) or nil
    end)
    return ok and y or hint
end

local function setColour(hex)
    if hex == colour and frames % 30 ~= 0 then return end
    colour = hex
    global.pcall(function()
        local Vector3, model = global.require("Vector3"), global.api.model
        local r = (global.tonumber(global.string.sub(hex, 1, 2), 16) or 255) / 255
        local g = (global.tonumber(global.string.sub(hex, 3, 4), 16) or 160) / 255
        local b = (global.tonumber(global.string.sub(hex, 5, 6), 16) or 60) / 255
        -- The editor rewrites channel settings when the player changes tools: set them often.
        model.SetHighlightBehaviour(CHANNEL, model.HighlightDefault)
        model.SetHighlightEdgeColour(CHANNEL, Vector3:new(r, g, b), 1)
        model.SetHighlightFillColour(CHANNEL, Vector3:new(r, g, b), 0.45)  -- see-through (P6 A9)
    end)
end

local function safePrefab(resource)
    if global.type(resource) ~= "string" or not global.string.match(resource, "^[%w_%.%-]+$") then return nil end
    local lower = global.string.lower(resource)
    for _, pattern in global.ipairs(UNSAFE) do
        if global.string.match(lower, pattern) then return nil end
    end
    -- The name comes from another player's game. A scenery piece consists of a visual
    -- prefab "<name>" and a game prefab "<name>_game"; only when both exist is the visual
    -- one shown. Anything else (rides, vehicles, engine prefabs) gets the plain disc.
    local okArt, art = global.pcall(E().FindPrefab, resource)
    local okGame, game = global.pcall(E().FindPrefab, resource .. "_game")
    if okArt and art and okGame and game then return resource end
    return nil
end

local function drop(state)
    destroy(state.marker and state.marker.entity)
    if state.figure and state.figure.fig then global.pcall(function() state.figure.fig:Destroy() end)
    else destroy(state.figure and state.figure.entity) end
    for _, dot in global.ipairs(state.dots or {}) do destroy(dot.entity) end
    for _, ghost in global.ipairs(state.ghosts or {}) do destroy(ghost.entity) end
    destroy(state.big and state.big.entity)
end

local function quaternion(item)
    local Quaternion = global.require("Quaternion")
    return Quaternion.Identity:WithX(item.qx):WithY(item.qy):WithZ(item.qz):WithW(item.qw)
end

-- A guest figure with the player's look (figure.lua), or nil where none can be built.
local function guestFigure(p)
    local ok, made = global.pcall(function()
        local Figure = global.require("pc2coop.figure")
        if not Figure.Available() then return nil end
        local fig = Figure.New(Figure.ParseLook(p.look) or Figure.DefaultLook(), p.color,
            {track = track, untrack = function(entity)
                for i, other in global.ipairs(shared.vizEntities or {}) do
                    if other == entity then global.table.remove(shared.vizEntities, i); break end
                end
            end})
        fig:Warm()
        return {fig = fig, look = p.look}
    end)
    return ok and made or nil
end

-- The visitor's feet, eased; walk or run from the speed, the player's emote while standing,
-- facing where it goes (or away from the player's camera while it stands).
local function placeGuest(state, p, x, y, z, dt)
    local Figure = global.require("pc2coop.figure")
    dt = dt or 1 / 60
    local g = state.figure
    if g.look ~= p.look then
        global.pcall(function() g.fig:Destroy() end)
        local fresh = guestFigure(p)
        if not fresh then return end
        state.figure, g = fresh, fresh
    end
    local at = g.at
    if not at then at = {x, y, z}; g.at = at end
    local dx, dz = x - at[1], z - at[3]
    if dx * dx + dz * dz > 150 * 150 then at[1], at[2], at[3], dx, dz = x, y, z, 0, 0 end
    local k = 1 - global.math.exp(-dt * 9)
    local mx, mz = dx * k, dz * k
    at[1], at[2], at[3] = at[1] + mx, at[2] + (y - at[2]) * k, at[3] + mz
    local speed = global.math.sqrt(mx * mx + mz * mz) / global.math.max(dt, 1e-3)
    g.speed = (g.speed or 0) * 0.85 + speed * 0.15
    if g.speed > 0.4 and (mx ~= 0 or mz ~= 0) then g.yaw = global.math.atan(mx, mz)
    elseif not g.yaw and p.x and p.fx then g.yaw = global.math.atan(p.fx - p.x, p.fz - p.z) end
    local gaitNow = Figure.Gait(g.speed)
    if gaitNow == "walk" and (p.emote == "eat" or p.emote == "drink") then gaitNow = "walk" .. p.emote
    elseif gaitNow == "idle" and p.emote then gaitNow = p.emote end
    global.pcall(function() g.fig:Place(at[1], at[2], at[3], g.yaw or 0, gaitNow) end)
end

-- One remote player: p = {sid, x, y, z (camera), fx, fy, fz (focus), hold = {label, items},
-- look (figure.lua wire text), emote (kind of the last few seconds)}
local function update(p, dt)
    local state = players[p.sid]
    if not state then
        state = {dots = {}, ghosts = {}, targets = {}}
        players[p.sid] = state
        state.marker = spawn(DISC, 1)
        for i, dot in global.ipairs(DOTS) do state.dots[i] = spawn(DISC, 0.2 + 0.35 * dot[2]) end
    end
    local fx, fy, fz = p.fx or p.x, p.fy or p.y, p.fz or p.z
    local signature = global.string.format("%.0f,%.0f,%.0f,%.0f", p.x or fx, p.z or fz, fx, fz)
    if signature ~= state.signature then
        -- New view: recompute where the dots sit (terrain height by ray, a few times a second).
        state.signature = signature
        local targets = {marker = {fx, ground(fx, fz, fy) + 0.12, fz}}
        local dx, dz = fx - (p.x or fx), fz - (p.z or fz)
        local length = global.math.sqrt(dx * dx + dz * dz)
        if length > 4 then
            local reach = global.math.min(length * 1.08, 140)
            local angle = global.math.atan(dx, dz)
            for i, dot in global.ipairs(DOTS) do
                local a = angle + dot[1] * HALF_ANGLE
                local x, z = p.x + global.math.sin(a) * reach * dot[2], p.z + global.math.cos(a) * reach * dot[2]
                targets[i] = {x, ground(x, z, fy) + 0.12, z}
            end
        end
        state.targets = targets
    end
    local m = state.targets.marker
    -- A visitor: the figure where the player stands, in the player's colour. The figure is the
    -- marker then: the ground disc and the view dots would cover everything close up.
    local visiting = global.string.find(global.tostring(p.act or ""), "Besucher", 1, true) ~= nil
    place(state.marker, m[1], visiting and -500 or m[2], m[3], dt)
    local k = sizeAt(m[1], m[2], m[3])
    resize(state.marker, 1 * k)
    if visiting and not state.figure then state.figure = guestFigure(p) or (figureOK() and spawn(FIGURE, 1)) or nil end
    if state.figure and state.figure.fig then
        if visiting then
            placeGuest(state, p, fx, fy or 0, fz, dt)
        else
            global.pcall(function() state.figure.fig:Destroy() end); state.figure = nil
        end
    elseif state.figure then
        if visiting then
            local yaw = ((p.x and p.fx) and global.math.atan((p.fx or 0) - p.x, (p.fz or 0) - p.z) or 0) + global.math.pi / 2  -- statue looks along -x
            local Quaternion = global.require("Quaternion")
            place(state.figure, fx, (fy or 0), fz, dt, Quaternion.Identity:WithY(global.math.sin(yaw / 2)):WithW(global.math.cos(yaw / 2)))
        else
            destroy(state.figure.entity); state.figure = nil
        end
    end
    for i, dot in global.ipairs(state.dots) do
        local t = state.targets[i]
        if t and not visiting then place(dot, t[1], t[2], t[3], dt) else place(dot, m[1], -500, m[3], dt) end
        resize(dot, (0.2 + 0.35 * DOTS[i][2]) * (t and sizeAt(t[1], t[2], t[3]) or k))
    end
    -- What the player holds: ghosts of up to MAX_GHOSTS parts, or a large disc for things
    -- that cannot be shown as a model (rides, blueprints of rides).
    local items = p.hold and p.hold.items or {}
    local wanted, big = {}, nil
    for _, item in global.ipairs(items) do
        if item.model then
            if #wanted < MAX_GHOSTS then wanted[#wanted+1] = item end
        else
            big = big or item
        end
    end
    for i = #state.ghosts, 1, -1 do
        local ghost = state.ghosts[i]
        if not wanted[i] or wanted[i].resource ~= ghost.resource then
            destroy(ghost.entity)
            global.table.remove(state.ghosts, i)
        end
    end
    for i, item in global.ipairs(wanted) do
        local ghost = state.ghosts[i]
        if not ghost then
            local prefab = safePrefab(item.resource)
            ghost = prefab and spawn(prefab, item.scale or 1) or nil
            if ghost then ghost.resource = item.resource; state.ghosts[i] = ghost else big = big or item end
        end
        if ghost then
            ghost.scale = item.scale or 1
            place(ghost, item.x, item.y, item.z, dt, quaternion(item))
        end
    end
    if big then
        state.big = state.big or spawn(DISC, 5)
        place(state.big, big.x, ground(big.x, big.z, big.y) + 0.15, big.z, dt)
    elseif state.big then
        destroy(state.big.entity)
        state.big = nil
    end
end

function Viz.Init(logger) emit = logger end

-- Developer check: players (and locked entities) that are shown next to the real ones.
local pinned, pinnedLocked
function Viz.Pin(list, locked) pinned, pinnedLocked = list, locked end
function Viz.SetEnabled(value) enabled = value == true; if not enabled then Viz.Clear() end end
function Viz.Enabled() return enabled end

-- remote: list of the other players (see update); lockedEntities: entity -> true for
-- objects somebody else is editing; hex: colour for all of it.
-- A mark must never cover anything of the park (P6 A9, second round; before: a filled disc
-- and three discs floating above it, a build area as one big filled disc):
--   * on a shared object (ping.entity): that object gets the game's highlight in the player's
--     colour, blinking while the mark lasts - nothing is drawn over it;
--   * on the ground, for park events and build areas: a ring of small dots flat on the ground
--     around the spot, the middle stays free. Sized by the camera's distance; a build area's
--     ring has the area's size and stands still, a mark widens a little and turns slowly.
local RING_DOTS = 10

local function dropDots(state)
    for _, item in global.ipairs(state.dots or {}) do destroy(item.entity) end
    state.dots, state.heights = {}, nil
end

local function unlight(state)
    if state.entity and not tinted[state.entity] then
        global.pcall(global.api.model.SetHighlighted, state.entity, CHANNEL, false, true)
    end
    state.entity, state.lit = nil, nil
end

local function beacon(sid, ping, dt)
    local state = beacons[sid]
    if not state then state = {dots = {}}; beacons[sid] = state end
    if state.entity ~= ping.entity then unlight(state) end
    if ping.entity then
        state.entity = ping.entity
        -- On for two thirds of every half second: a signal, not a lasting tint.
        local on = frames % 30 < 20
        if on ~= state.lit then
            global.pcall(global.api.model.SetHighlighted, ping.entity, CHANNEL, on or tinted[ping.entity] == true, true)
            state.lit = on
        end
        if #state.dots > 0 then dropDots(state) end
        return
    end
    local area = ping.radius and ping.radius > 0
    local count = area and global.math.max(12, global.math.min(40, global.math.floor(ping.radius * 1.2))) or RING_DOTS
    while #state.dots < count do
        local item = spawn(DISC, 0.12)
        if not item then break end   -- the game made no entity: fewer dots, never a stuck loop
        state.dots[#state.dots+1] = item
    end
    while #state.dots > count do destroy(global.table.remove(state.dots).entity) end
    local key = global.string.format("%.1f,%.1f,%.1f", ping.x, ping.z, area and ping.radius or 0)
    if state.key ~= key then
        -- The ground under every dot of a build area (once per place); a small ring sits on the
        -- height of its middle.
        state.key, state.heights = key, {}
        state.y = ground(ping.x, ping.z, ping.y)
    end
    local k = sizeAt(ping.x, state.y, ping.z)
    local radius = area and ping.radius or (0.9 + 0.25 * global.math.sin((ping.age or 0) * 50)) * k
    local turn = area and 0 or frames / 240
    local Vector3 = global.require("Vector3")
    for i, item in global.ipairs(state.dots) do
        if item and ready(item) then
            local a = turn + (i - 1) * 2 * global.math.pi / count
            local x, z = ping.x + global.math.cos(a) * radius, ping.z + global.math.sin(a) * radius
            local y = state.y
            if area then
                state.heights[i] = state.heights[i] or ground(x, z, state.y)
                y = state.heights[i]
            end
            X().SetPosition(item.entity, Vector3:new(x, y + 0.06, z))
            resize(item, (area and 0.22 or 0.12) * k)
        end
    end
end

local function dropBeacon(state)
    dropDots(state)
    unlight(state)
end

function Viz.Update(remote, lockedEntities, hex, dt, pings)
    frames = frames + 1
    if failed or not enabled then return end
    if pinned then
        local all, allLocked = {}, {}
        for _, p in global.ipairs(remote) do all[#all+1] = p end
        for _, p in global.ipairs(pinned) do all[#all+1] = p end
        for entity in global.pairs(lockedEntities) do allLocked[entity] = true end
        for entity in global.pairs(pinnedLocked or {}) do allLocked[entity] = true end
        remote, lockedEntities, hex = all, allLocked, hex or (pinned[1] and pinned[1].color)
    end
    local ok, failure = global.pcall(function()
        setColour(hex or "ffa94d")
        local live = {}
        for _, p in global.ipairs(remote) do
            live[p.sid] = true
            update(p, dt)
        end
        for sid, state in global.pairs(players) do
            if not live[sid] then drop(state); players[sid] = nil end
        end
        local pinged = {}
        for _, ping in global.ipairs(pings or {}) do
            pinged[ping.sid] = true
            beacon(ping.sid, ping, dt)
        end
        for sid, state in global.pairs(beacons) do
            if not pinged[sid] then dropBeacon(state); beacons[sid] = nil end
        end
        local model = global.api.model
        for entity in global.pairs(tinted) do
            if not lockedEntities[entity] then
                global.pcall(model.SetHighlighted, entity, CHANNEL, false, true)
                tinted[entity] = nil
            end
        end
        for entity in global.pairs(lockedEntities) do
            if not tinted[entity] then
                global.pcall(model.SetHighlighted, entity, CHANNEL, true, true)
                tinted[entity] = true
            end
        end
    end)
    if not ok then
        failed = true
        emit("viz:error|" .. global.tostring(failure))
        global.pcall(Viz.Clear)
    end
end

function Viz.Clear()
    for _, state in global.pairs(players) do drop(state) end
    players = {}
    for _, state in global.pairs(beacons) do dropBeacon(state) end
    beacons = {}
    for entity in global.pairs(tinted) do global.pcall(global.api.model.SetHighlighted, entity, CHANNEL, false, true) end
    tinted = {}
    -- Entities of an earlier module instance (the park manager was restarted).
    for _, entity in global.ipairs(shared.vizEntities or {}) do global.pcall(E().DestroyEntity, entity) end
    shared.vizEntities = {}
end

function Viz.Stats()
    local count = 0
    for _ in global.pairs(players) do count = count + 1 end
    return {players = count, entities = #(shared.vizEntities or {}), failed = failed}
end

return Viz
