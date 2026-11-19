-- Original MIT code. The visitor figure: the game's own guest models and baked guest
-- animations (stand, walk, run, cheer ...), base game only (Content0).
--
-- The game's guest prefab "peep" is a template: the crowd system fills in its model and
-- animation names and drives it with guest logic (GuestVisual ...). We copy it without that
-- logic, fill in fixed model names, colours and one animation, and compile that as an own
-- prefab (api.entity.CompilePrefab, through ACSE). One prefab per look and animation. A
-- figure keeps one entity per animation it has shown and shows exactly one of them; the
-- others wait under the ground (switching is instant, the animation keeps running).
-- Tested in the test copy, build 26255360: walk, run, idle, cheer, point, laugh for adult
-- and teen guests; the start screen avatar prefab itself crashes a park (1.12.0).
local global = _G
local Figure = {}

-- Model numbers that exist in the base game per guest group (am = adult male, af = adult
-- female, tm/tf = teens, cm/cf = children): <group>_<part><number>.mdl2.
Figure.PARTS = {
    am = {body = {"01", "04", "07", "08", "10", "11"}, legs = {"01", "04", "07", "08", "11", "12"},
        head = {"01", "04", "07", "08"}, hair = {"01", "04", "07", "08"}},
    af = {body = {"01", "02", "04", "10", "11", "12"}, legs = {"01", "04", "11", "12", "13"},
        head = {"01", "02", "03", "04"}, hair = {"01", "02", "03", "04"}},
    tm = {body = {"01", "02", "06", "10", "11", "12"}, legs = {"01", "06", "11", "12", "13"},
        head = {"01", "02", "03", "06"}, hair = {"01", "02", "03", "06"}},
    tf = {body = {"01", "03", "06", "07", "08", "09"}, legs = {"01", "06", "07", "08", "09", "11"},
        head = {"01", "03", "06"}, hair = {"01", "03", "06", "07"}},
    cm = {body = {"01", "02", "10", "11", "12"}, legs = {"01", "02", "11", "12", "13"},
        head = {"01", "02", "03"}, hair = {"01", "02", "03"}},
    cf = {body = {"03", "04", "10", "11", "12"}, legs = {"03", "04", "11", "12", "13"},
        head = {"01", "03", "04"}, hair = {"01", "03", "04"}},
}
-- State -> baked animation (<group>$<name>.bani). The emotes are those of visitor.lua.
Figure.ANIMS = {idle = "standbaseidle01", walk = "walkbase", run = "runbase", wave = "standwaveflag_loop",
    cheer = "standreactcheer", laugh = "standreactlaugh", sick = "standreactsick", up = "standreactpoint",
    down = "standreactbored"}
local MISSING = {cm = {wave = "cheer"}}
local BASE = {idle = true, walk = true, run = true}
local HIDDEN = -500
local SOURCE = "peep"
-- Guest logic and root motion stay out: the figure stands where we put it.
local DROP = {GuestVisual = true, GuestInventoryVisuals = true, GuestWaterObjectsCreator = true,
    GuestFaceStructureAnimation = true, BakedMotionApplication = true, BakedAnimTree = true, LevelOfDetail = true}
local CHILDREN = {Torso = "body", Legs = "legs", Head = "head", Hair = "hair"}

local compiled = {}      -- prefab name -> name or false
local available = nil

local function hexOk(h) return global.type(h) == "string" and global.string.match(h, "^%x%x%x%x%x%x$") ~= nil end

-- Wire text of a look: "am.1.1.1.1.rrggbb-rrggbb-rrggbb-rrggbb.rrggbb-rrggbb.rrggbb";
-- "x" instead of the colours: the player's colour.
function Figure.LookText(look)
    local function list(t) return t and global.table.concat(t, "-") or "x" end
    return global.table.concat({look.g, look.body, look.legs, look.head, look.hair, list(look.top), list(look.bottom),
        look.hairc or "x"}, ".")
end

-- Strict: anything else from the network is nil.
function Figure.ParseLook(text)
    if global.type(text) ~= "string" or #text > 80 or not global.string.match(text, "^[%w%.%-]+$") then return nil end
    local f = {}
    for part in global.string.gmatch(text, "[^%.]+") do f[#f+1] = part end
    if #f ~= 8 or not Figure.PARTS[f[1]] then return nil end
    local parts = Figure.PARTS[f[1]]
    local look = {g = f[1]}
    for i, part in global.ipairs({"body", "legs", "head", "hair"}) do
        local n = global.tonumber(f[i + 1])
        if not n or n ~= global.math.floor(n) or n < 1 or n > #parts[part] then return nil end
        look[part] = n
    end
    local function colours(t, count)
        if t == "x" then return nil, true end
        local out = {}
        for h in global.string.gmatch(t, "[^%-]+") do if not hexOk(h) then return nil, false end; out[#out+1] = h end
        if #out ~= count then return nil, false end
        return out, true
    end
    local ok1, ok2
    look.top, ok1 = colours(f[6], 4)
    look.bottom, ok2 = colours(f[7], 2)
    if not ok1 or not ok2 then return nil end
    if f[8] ~= "x" then
        if not hexOk(f[8]) then return nil end
        look.hairc = f[8]
    end
    return look
end

function Figure.DefaultLook() return {g = "am", body = 1, legs = 1, head = 1, hair = 1} end

local function hexOf(v)
    local ok, r, g, b = global.pcall(function() return v:GetX(), v:GetY(), v:GetZ() end)
    if not ok then
        if global.type(v) ~= "table" then return nil end
        r, g, b = v.x or v[1], v.y or v[2], v.z or v[3]
    end
    if global.type(r) ~= "number" or global.type(g) ~= "number" or global.type(b) ~= "number" then return nil end
    local function c(x) return global.math.max(0, global.math.min(255, global.math.floor(x * 255 + 0.5))) end
    return global.string.format("%02x%02x%02x", c(r), c(g), c(b))
end

-- The player's own Frontier avatar (start screen): age and gender group and the clothing
-- colours. The game stores its parts as numbers we cannot map to model names; the number
-- picks one of the base game models, so a player always looks the same.
function Figure.FromAvatar(data)
    if global.type(data) ~= "table" or global.type(data.parts) ~= "table" then return nil end
    local g = global.string.lower(global.string.sub(global.tostring(data.group or ""), 1, 2))
    if not Figure.PARTS[g] then g = "am" end
    local parts = Figure.PARTS[g]
    local function pick(list, part)
        local id = global.tonumber(global.type(part) == "table" and part.model or 0) or 0
        return global.math.floor(global.math.abs(id)) % #list + 1
    end
    local function colours(part, count)
        local list = global.type(part) == "table" and global.type(part.custom) == "table" and part.custom.colours
        if global.type(list) ~= "table" then return nil end
        local out = {}
        for i = 1, count do
            local h = hexOf(list[i])
            if not h then return nil end
            out[i] = h
        end
        return out
    end
    local p = data.parts
    local look = {g = g, body = pick(parts.body, p.Bodies), legs = pick(parts.legs, p.Legs), head = pick(parts.head, p.Heads),
        hair = pick(parts.hair, p.Hair), top = colours(p.Bodies, 4), bottom = colours(p.Legs, 2)}
    local hair = colours(p.Hair, 1)
    look.hairc = hair and hair[1] or nil
    return look
end

function Figure.OwnLook()
    local ok, look = global.pcall(function()
        local GD = global.require("Database.GameDatabase")
        for _, player in global.pairs(GD.tPlayers or {}) do
            local avatar = player:GetData("AvatarData", "Main")
            local found = avatar and Figure.FromAvatar(avatar.tData)
            if found then return found end
        end
    end)
    return ok and look or Figure.DefaultLook()
end

-- Can figures be built here (ACSE prefab functions and the guest template)?
function Figure.Available()
    if available == nil then
        local ok, found = global.pcall(function()
            local E = global.api.entity
            return global.type(E.CompilePrefab) == "function" and E.FindPrefab(SOURCE) ~= nil
        end)
        available = ok and found == true
    end
    return available
end

local function resolve(t, props, defaults)
    if global.type(t) ~= "table" then return t end
    if t.__property then
        local v = props[t.__property]
        if v == nil then v = defaults[t.__property] end
        return v
    end
    local out = {}
    for k, v in global.pairs(t) do
        if k ~= "__inheritance" then
            local r = resolve(v, props, defaults)
            if r ~= nil then out[k] = r end
        end
    end
    return out
end

local function defaultsOf(properties)
    local out = {}
    for k, v in global.pairs(properties or {}) do
        if global.type(v) == "table" and v.Default ~= nil and v.Default ~= "" then out[k] = v.Default end
    end
    return out
end

local function vec(hex)
    local n = function(i) return (global.tonumber(global.string.sub(hex, i, i + 1), 16) or 128) / 255 end
    return global.require("Vector3"):new(n(1), n(3), n(5))
end

local function animOf(look, state)
    local key = (MISSING[look.g] or {})[state] or state
    return Figure.ANIMS[key] or Figure.ANIMS.idle
end

-- The colours a look shows; hex: the player's colour for "x".
function Figure.Colours(look, hex)
    hex = hexOk(hex) and hex or "ffa94d"
    return look.top or {hex, "f2f2f2", "333333", hex}, look.bottom or {"3b4a66", "2b2b2b"}, look.hairc or "4a3426"
end

function Figure.PrefabName(look, state, hex)
    local top, bottom, hair = Figure.Colours(look, hex)
    local key = global.table.concat({look.g, look.body, look.legs, look.head, look.hair, global.table.concat(top),
        global.table.concat(bottom), hair}, "_")
    return "PC2CoopFigure_" .. key .. "_" .. animOf(look, state)
end

local function build(look, state, hex)
    local name = Figure.PrefabName(look, state, hex)
    if compiled[name] ~= nil then return compiled[name] or nil end
    local ok = global.pcall(function()
        local E = global.api.entity
        local source = E.FindPrefab(SOURCE)
        local top, bottom, hair = Figure.Colours(look, hex)
        local slots = {body = top, legs = {bottom[1], bottom[2], bottom[1], bottom[2]}, head = top,
            hair = {hair, hair, hair, hair}}
        local parts = Figure.PARTS[look.g]
        local root = {Components = {}, Children = {}}
        local rootProps = {SkeletonName = look.g .. "_skeleton", DefaultAnimName = look.g .. "$" .. animOf(look, state)}
        for k, v in global.pairs(source.Components) do
            if not DROP[k] then root.Components[k] = resolve(v, rootProps, {}) end
        end
        for child, part in global.pairs(CHILDREN) do
            local c = source.Children[child]
            local props = {ModelName = look.g .. "_" .. part .. parts[part][look[part]]}
            for i = 1, 4 do props["Slot" .. (i - 1) .. "_Colour"] = vec(slots[part][i]) end
            local out = {Components = {}}
            for k, v in global.pairs(c.Components) do out.Components[k] = resolve(v, props, defaultsOf(c.Properties)) end
            root.Children[child] = out
        end
        E.CompilePrefab(root, name)
    end)
    compiled[name] = ok and name or false
    return ok and name or nil
end

-- One figure in the park. hooks: {track = function(entity), untrack = function(entity)}.
local Instance = {}
Instance.__index = Instance

function Figure.New(look, hex, hooks)
    return global.setmetatable({look = look or Figure.DefaultLook(), hex = hex, ents = {}, shown = nil, hooks = hooks or {}},
        Instance)
end

local function transform(x, y, z, yaw)
    local Q = global.require("Quaternion")
    local q = Q.Identity:WithX(0):WithY(global.math.sin(yaw / 2)):WithZ(0):WithW(global.math.cos(yaw / 2))
    return global.require("TransformQ").FromOrPos(q, global.require("Vector3"):new(x, y, z))
end

function Instance:_spawn(state)
    local name = build(self.look, state, self.hex)
    if not name then return nil end
    local ok, entity = global.pcall(function()
        local E = global.api.entity
        return E.InstantiatePrefab(name, nil, E.CreateRequestCompletionToken(), transform(0, HIDDEN, 0, 0))
    end)
    if not ok or entity == nil then return nil end
    if self.hooks.track then self.hooks.track(entity) end
    return {entity = entity, ready = false}
end

local function ready(item)
    if not item.ready then
        local ok, has = global.pcall(global.api.transform.HasTransform, item.entity)
        item.ready = ok and has == true
    end
    return item.ready
end

function Instance:_drop(state)
    local item = self.ents[state]
    if not item then return end
    global.pcall(global.api.entity.DestroyEntity, item.entity)
    if self.hooks.untrack then self.hooks.untrack(item.entity) end
    self.ents[state] = nil
    if self.shown == state then self.shown = nil end
end

-- Builds stand, walk and run up front so the first steps show at once.
function Instance:Warm()
    for state in global.pairs(BASE) do
        if not self.ents[state] then self.ents[state] = self:_spawn(state) end
    end
end

-- Shows the figure at the feet (x, y, z), turned to yaw (radians, 0 = +z), doing state
-- ("idle", "walk", "run" or an emote). Until that animation's entity is there, the one shown
-- so far stays. Returns whether something is shown.
function Instance:Place(x, y, z, yaw, state)
    if not Figure.ANIMS[state or ""] then state = "idle" end
    if not self.ents[state] then
        if not BASE[state] then
            for other in global.pairs(self.ents) do if not BASE[other] then self:_drop(other) end end
        end
        self.ents[state] = self:_spawn(state)
    end
    local show = nil
    if self.ents[state] and ready(self.ents[state]) then show = state
    elseif self.shown and self.ents[self.shown] and ready(self.ents[self.shown]) then show = self.shown
    else
        for other, item in global.pairs(self.ents) do if ready(item) then show = other; break end end
    end
    if self.shown and self.shown ~= show and self.ents[self.shown] then
        global.pcall(global.api.transform.SetTransform, self.ents[self.shown].entity, transform(x, HIDDEN, z, 0))
    end
    self.shown = show
    if show then global.pcall(global.api.transform.SetTransform, self.ents[show].entity, transform(x, y, z, yaw)) end
    return show ~= nil
end

function Instance:Shown() return self.shown end

function Instance:Owns(entity)
    for _, item in global.pairs(self.ents) do if item.entity == entity then return true end end
    return false
end

function Instance:Destroy()
    for state in global.pairs(self.ents) do self:_drop(state) end
end

-- Walk or run from the speed in metres per second.
function Figure.Gait(speed)
    if speed > 4.6 then return "run" end
    if speed > 0.5 then return "walk" end
    return "idle"
end

function Figure._Reset() compiled, available = {}, nil end

return Figure
