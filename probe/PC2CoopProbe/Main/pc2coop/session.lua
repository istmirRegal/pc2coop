-- Original MIT code. In-game co-op session over Steam (no external program).
--
-- Roles: the lobby owner is the host and runs the Authority (ordering, revisions,
-- attribution); everyone else is a client. Local game changes come from sync.lua as
-- "sync:*" lines, remote ones go back into sync.lua as numbered op lines.
-- Wire messages (Steam, reliable, text):
--   client -> host: hello|<name>|<baseline>|<mode>|<version>   up|...   del|...   pres|...
--   host -> client: reject|<host version>   (different mod versions never play together)
--   host -> client: ops\n<line>...   roster|<players>   feed|<text>   welcome|<color>
local global = _G
local Session = {}
local World = global.require("pc2coop.world")
local shared = global.require("pc2coop.shared")

-- Mod version; must match the database's probeVersion (checked by the tests).
Session.VERSION = "1.6.0"
local COLORS = {"ff6b6b", "4dabf7", "51cf66", "fcc419", "cc5de8", "ff922b", "22b8cf", "f06595"}
local net, sync
local emit = function() end
local me, myName = nil, "?"
local role, hostId, lobbyId = nil, nil, nil
local players = {}        -- sid -> {name, color, pres, base}
local order = {}          -- join order of sids
local objects, tombstones, stats = {}, {}, {}
local counter, conflicts = 0, 0
local feed = {}
local seq = 0
local roster = {}         -- client view of players (from host)
local manager             -- the game's park load/save manager
local memory = {}         -- session facts kept in the DLL across park loads
local tasks = {}          -- coroutines (saving takes several frames)
local transfer = {}       -- joiner: received files and park description
local friends, friendsLoading = {}, {}
local chat = {}           -- {name, text, color}
local toasts = {}         -- {id, text, color}
local toastId = 0
local joining, hostName = false, nil  -- joiner: invite accepted / host shown while loading
local progress = {}       -- joiner: file name -> {received, total}
local desync = nil        -- reason when a remote change could not be applied here
local context = "park"    -- "menu" while the main menu is open: nothing to build in
local helloLobby = nil    -- lobby this module instance already announced itself to
local joinFailure = nil   -- why joining or loading the host's park failed (shown to the player)
local INVITE_FRAMES = 1500  -- an invite button stays "Eingeladen" this long (about 25 s)
local locks = {}          -- host: gid -> sid of the player editing that object
local holds = {}          -- everyone: sid -> {label, gids, items} of what a player holds
local bursts = {}         -- host: "sid|verb" -> {name, verb, n, res, last}: one log line per burst
local recent = {}         -- host: seq -> line given to the local game (to undo what it refuses)
local park = nil          -- the host park's numbers: {guests, cash, unlimited}
local lastNote = {}       -- host: notification text -> frame it was last passed on
local lastRoster = 0
local frames = 0

local function split(text, sep)
    local out = {}
    for field in global.string.gmatch(text, "([^" .. sep .. "]*)" .. sep .. "?") do out[#out+1] = field end
    if out[#out] == "" then out[#out] = nil end
    return out
end

local function clean(name)
    name = global.string.gsub(global.tostring(name or "?"), "[|;,\n\r]", "")
    return global.string.sub(name, 1, 32)
end

local send

local function toast(text, color)
    toastId = toastId + 1
    toasts[#toasts+1] = {id = toastId, text = text, color = color}
    while #toasts > 10 do global.table.remove(toasts, 1) end
end

local function addFeed(text)
    feed[#feed+1] = text
    while #feed > 30 do global.table.remove(feed, 1) end
    toast(text)
    emit("session:feed|" .. text)
    if role == "host" then
        for _, sid in global.ipairs(order) do if sid ~= me then send(sid, "feed|" .. text) end end
    end
end

-- Local sync stream: numbered lines into sync.lua ---------------------------------------

local function toGame(lines)
    local numbered = {}
    for _, line in global.ipairs(lines) do
        local kind, rest = global.string.match(line, "^(%a)|(.*)$")
        if kind then
            seq = seq + 1
            numbered[#numbered+1] = kind .. "|" .. seq .. "|" .. rest
        end
    end
    if role == "host" then
        for _, line in global.ipairs(numbered) do
            local n = global.tonumber(global.string.match(line, "^%a|(%d+)|"))
            if n then recent[n] = line; recent[n - 300] = nil end
        end
    end
    if #numbered > 0 then sync.Receive(global.table.concat(numbered, "\n")) end
end

-- Transport -----------------------------------------------------------------------------

local LIMIT = 3900

function send(sid, payload)
    net.NetCommand("send|" .. sid .. "|" .. payload)
end

local function sendOps(sid, lines)
    if sid == me then toGame(lines); return end
    local batch, size = {}, 0
    for _, line in global.ipairs(lines) do
        if size + #line + 1 > LIMIT and #batch > 0 then
            send(sid, "ops\n" .. global.table.concat(batch, "\n"))
            batch, size = {}, 0
        end
        batch[#batch+1] = line
        size = size + #line + 1
    end
    if #batch > 0 then send(sid, "ops\n" .. global.table.concat(batch, "\n")) end
end

local function deliver(deliveries)
    local bySid, sids = {}, {}
    for _, d in global.ipairs(deliveries) do
        local p = players[d[1]]
        if p and p.pending then
            -- Joiner is still loading the host park: hold its ops until it is ready.
            p.pending[#p.pending+1] = d[2]
        else
            if not bySid[d[1]] then bySid[d[1]] = {}; sids[#sids+1] = d[1] end
            global.table.insert(bySid[d[1]], d[2])
        end
    end
    for _, sid in global.ipairs(sids) do sendOps(sid, bySid[sid]) end
end

local function remember(key, value)
    memory[key] = value
    net.NetCommand("kv|" .. key .. "|" .. value)
end

-- Authority (host only) -----------------------------------------------------------------

local function num(v) return global.string.format("%.9g", v) end

local function upsertLine(gid)
    local s = objects[gid]
    return global.table.concat({"U", gid, clean(s.last), global.tostring(s.rev), s.res,
        num(s.p[1]), num(s.p[2]), num(s.p[3]), num(s.q[1]), num(s.q[2]), num(s.q[3]), num(s.q[4]), num(s.s)}, "|")
end

local function nameOf(sid) return players[sid] and players[sid].name or "?" end

local function count(sid, key)
    local name = nameOf(sid)
    stats[name] = stats[name] or {created = 0, edited = 0, deleted = 0}
    stats[name][key] = stats[name][key] + 1
end

-- "Vici hat 143 Objekte platziert" instead of 143 lines.
local function noteAction(sid, verb, res)
    local key = sid .. "|" .. verb
    local burst = bursts[key]
    if not burst then burst = {name = nameOf(sid), verb = verb, n = 0}; bursts[key] = burst end
    burst.n, burst.res, burst.last = burst.n + 1, res, frames
end

local function flushActions(force)
    for key, burst in global.pairs(bursts) do
        if force or frames - burst.last >= 45 then
            bursts[key] = nil
            if burst.n == 1 then addFeed(burst.name .. " hat " .. global.tostring(burst.res) .. " " .. burst.verb)
            else addFeed(burst.name .. " hat " .. burst.n .. " Objekte " .. burst.verb) end
        end
    end
end

local function others(sid, line)
    local out = {}
    for _, other in global.ipairs(order) do
        if other ~= sid and players[other] then out[#out+1] = {other, line} end
    end
    return out
end

local function restore(sid, gid, reason)
    conflicts = conflicts + 1
    local out = {{sid, "R|" .. gid .. "|" .. reason}}
    if objects[gid] then
        out[#out+1] = {sid, upsertLine(gid)}
        addFeed(nameOf(sid) .. ": Aenderung verworfen, " .. objects[gid].last .. " war schneller")
    else
        out[#out+1] = {sid, "D|" .. gid .. "|host|0"}
    end
    return out
end

-- The object is being edited by someone else: the change is refused and the author's
-- game is put back to the shared state (from this host's world for untouched park objects).
local function refuseLocked(sid, gid)
    conflicts = conflicts + 1
    local out = {{sid, "R|" .. gid .. "|gesperrt"}}
    if objects[gid] then
        out[#out+1] = {sid, upsertLine(gid)}
    else
        local state = sync.StateOf and sync.StateOf(gid)
        if state then
            out[#out+1] = {sid, global.table.concat({"U", gid, "Park", "0", state.res, num(state.p[1]), num(state.p[2]),
                num(state.p[3]), num(state.q[1]), num(state.q[2]), num(state.q[3]), num(state.q[4]), num(state.s)}, "|")}
        end
    end
    return out
end

local function lockedByOther(sid, gid) return gid ~= "" and locks[gid] ~= nil and locks[gid] ~= sid end

local function validResource(res) return global.type(res) == "string" and global.string.match(res, "^[%w_%.%-]+$") and #res <= 96 end
local function validGid(gid) return gid == "" or (global.string.match(gid, "^[%w_%.%-]+$") and #gid <= 64) end

local function authorityUp(sid, part, gid, rev, res, p, q, s)
    if not validResource(res) or not validGid(gid) then return {} end
    if lockedByOther(sid, gid) then return refuseLocked(sid, gid) end
    local name = nameOf(sid)
    local state = {res = res, p = p, q = q, s = s, last = name}
    if gid == "" then
        counter = counter + 1
        gid = global.string.format("%s-%d", global.string.sub(sid, -6), counter)
        state.rev, state.creator = 1, name
        count(sid, "created")
        noteAction(sid, "platziert", res)
    elseif objects[gid] then
        local current = objects[gid]
        if rev ~= current.rev then return restore(sid, gid, "veraltet") end
        state.rev, state.creator = current.rev + 1, current.creator
        count(sid, "edited")
        noteAction(sid, "bearbeitet", res)
    elseif tombstones[gid] then
        return restore(sid, gid, "geloescht")
    elseif global.string.sub(gid, 1, 1) == "P" and rev == 0 then
        state.rev, state.creator = 1, "Park"
        count(sid, "edited")
        noteAction(sid, "bearbeitet", res)
    else
        return {{sid, "R|" .. gid .. "|unbekannt"}}
    end
    objects[gid] = state
    local out = {{sid, "M|" .. gid .. "|" .. part .. "|" .. state.rev}}
    for _, d in global.ipairs(others(sid, upsertLine(gid))) do out[#out+1] = d end
    return out
end

local function authorityDelete(sid, part, gid, rev)
    if gid == "" or not validGid(gid) then return {} end
    if lockedByOther(sid, gid) then return refuseLocked(sid, gid) end
    local res
    if objects[gid] then
        if rev ~= objects[gid].rev then return restore(sid, gid, "veraltet") end
        res = objects[gid].res
        objects[gid] = nil
    elseif global.string.sub(gid, 1, 1) == "P" and rev == 0 and not tombstones[gid] then
        res = "Parkobjekt"
    elseif tombstones[gid] then
        return restore(sid, gid, "unbekannt")
    else
        return {}
    end
    tombstones[gid] = rev + 1
    count(sid, "deleted")
    addFeed(nameOf(sid) .. " hat " .. res .. " geloescht")
    local out = {{sid, "M|" .. gid .. "|" .. part .. "|0"}}
    for _, d in global.ipairs(others(sid, "D|" .. gid .. "|" .. clean(nameOf(sid)) .. "|" .. (rev + 1))) do out[#out+1] = d end
    return out
end

local function sendPark(sid)
    -- The joiner gets the host's exact park; part ids survive save/load (verified).
    -- One copy per joiner: the DLL streams it chunk by chunk while Steam has room, so a
    -- second joiner must not overwrite a file that is still being sent.
    local base = "pc2coop-host-" .. sid
    local ok, failure = manager:SaveTerrainToFile("/run/" .. base .. ".trn", true)
    global.assert(ok, "terrain save failed: " .. global.tostring(failure))
    ok, failure = manager:SaveParkToFile("/run/" .. base .. ".bin", true, false)
    global.assert(ok, "park save failed: " .. global.tostring(failure))
    net.NetCommand("file|" .. sid .. "|" .. base .. ".trn|pc2coop-join.trn")
    net.NetCommand("file|" .. sid .. "|" .. base .. ".bin|pc2coop-join.bin")
    local parkName = global.api.world.GetWorldAPIs().park:GetParkName()
    send(sid, "park|" .. global.tostring(global.api.world.GetActive()) .. "|" .. clean(parkName))
    emit("session:park-sent|" .. sid)
end

-- After the joiner loaded our park: map every object to the part id it already has.
local function catchUp(sid)
    local p = players[sid]
    local lines = {}
    for gid, state in global.pairs(objects) do
        local part = sync.LocalPart and sync.LocalPart(gid)
        if part then lines[#lines+1] = "A|" .. gid .. "|" .. part .. "|" .. state.rev
        else lines[#lines+1] = upsertLine(gid) end
    end
    for _, line in global.ipairs(p.pending or {}) do lines[#lines+1] = line end
    p.pending = nil
    sendOps(sid, lines)
end

local function join(sid, name, mode)
    local returning = players[sid] ~= nil
    if not returning then order[#order+1] = sid end
    local color = returning and players[sid].color or COLORS[(#order - 1) % #COLORS + 1]
    players[sid] = players[sid] or {}
    players[sid].name, players[sid].color = clean(name), color
    stats[players[sid].name] = stats[players[sid].name] or {created = 0, edited = 0, deleted = 0}
    if sid ~= me then send(sid, "welcome|" .. color) end
    for _, fr in global.ipairs(friends) do if fr.sid == sid then fr.invitedAt = nil end end
    if mode == "needpark" then
        -- Asked again while the park is still on its way: it arrives, nothing to restart.
        if players[sid].sending then return end
        players[sid].pending, players[sid].sending, players[sid].sent = {}, true, 0
        addFeed(players[sid].name .. " tritt bei und laedt den Park")
        tasks[#tasks+1] = global.coroutine.create(function() sendPark(sid) end)
    elseif mode == "loaded" and players[sid].pending then
        addFeed(players[sid].name .. " ist beigetreten")
        catchUp(sid)
        for holder, hold in global.pairs(holds) do
            if holder ~= sid then send(sid, "h|" .. holder .. "|" .. hold.label .. "|" .. hold.gids .. "|" .. hold.raw) end
        end
        local paused, index = World.Time()
        if paused ~= nil then send(sid, "time|" .. (paused and "1" or "0") .. "|" .. index .. "|") end
    else
        if not returning then addFeed(players[sid].name .. " ist beigetreten") end
        local snapshot = {}
        for gid in global.pairs(objects) do snapshot[#snapshot+1] = {sid, upsertLine(gid)} end
        deliver(snapshot)
    end
end

local hostHold

local function leave(sid)
    if players[sid] then
        addFeed(players[sid].name .. " hat die Sitzung verlassen")
        if holds[sid] or global.next(locks) then hostHold(sid, "", "", "") end
        players[sid] = nil
        for i, other in global.ipairs(order) do if other == sid then global.table.remove(order, i); break end end
    end
end

local function parseItems(text)
    local items = {}
    for entry in global.string.gmatch(text or "", "[^;]+") do
        local f = split(entry, ",")
        local resource = f[1] or ""
        local model = global.string.sub(resource, 1, 1) ~= "!"
        if not model then resource = global.string.sub(resource, 2) end
        local n = {}
        for i = 2, 9 do n[i] = global.tonumber(f[i]) end
        if n[2] and n[3] and n[4] and #items < 8 then
            items[#items+1] = {resource = resource, model = model, x = n[2], y = n[3], z = n[4],
                qx = n[5] or 0, qy = n[6] or 0, qz = n[7] or 0, qw = n[8] or 1, scale = n[9] or 1}
        end
    end
    return items
end

-- Tells sync.lua which objects the others hold (their locks), by player name.
local function publishLocks()
    local map = {}
    for sid, hold in global.pairs(holds) do
        if sid ~= me then
            local name = "?"
            for _, pl in global.ipairs(role == "host" and {} or (roster.players or {})) do if pl.sid == sid then name = pl.name end end
            if role == "host" and players[sid] then name = players[sid].name end
            for gid in global.string.gmatch(hold.gids or "", "[^,]+") do map[gid] = name end
        end
    end
    if sync.SetRemoteLocks then sync.SetRemoteLocks(map) end
end

local function setHold(sid, label, gids, items)
    if label == nil or label == "" then holds[sid] = nil
    else holds[sid] = {label = clean(label), gids = gids or "", items = parseItems(items), raw = items or ""} end
    publishLocks()
end

local function releaseLocks(sid)
    for gid, owner in global.pairs(locks) do if owner == sid then locks[gid] = nil end end
end

-- Host: a player picked something up or put it down.
function hostHold(sid, label, gids, items)
    releaseLocks(sid)
    local denied
    if label ~= "" then
        for gid in global.string.gmatch(gids or "", "[^,]+") do
            if validGid(gid) then
                if locks[gid] and locks[gid] ~= sid then denied = locks[gid] else locks[gid] = sid end
            end
        end
    end
    if denied then
        releaseLocks(sid)
        label, gids, items = "", "", ""
        if sid == me then Session._Denied(nameOf(denied)) else send(sid, "deny|" .. nameOf(denied)) end
    end
    setHold(sid, label, gids, items)
    local line = "h|" .. sid .. "|" .. clean(label) .. "|" .. (gids or "") .. "|" .. (items or "")
    for _, other in global.ipairs(order) do
        if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
    end
end

local function timeText(name, paused, index)
    local speeds = {"x1", "x2", "x5"}
    if paused then return name .. " hat das Spiel pausiert" end
    return name .. " laesst das Spiel laufen (" .. (speeds[index] or "x1") .. ")"
end

local function numbers(fields, from, to)
    local out = {}
    for i = from, to do
        local n = global.tonumber(fields[i])
        if not n or n ~= n or global.math.abs(n) > 1e6 then return nil end
        out[#out+1] = n
    end
    return out
end

-- A change report, either from our own game or from a client.
local function hostChange(sid, f)
    if f[1] == "up" and #f >= 13 then
        local p, q, s = numbers(f, 6, 8), numbers(f, 9, 12), numbers(f, 13, 13)
        if p and q and s then deliver(authorityUp(sid, f[2], f[3], global.tonumber(f[4]), f[5], p, q, s[1])) end
    elseif f[1] == "del" and #f >= 4 then
        deliver(authorityDelete(sid, f[2], f[3], global.tonumber(f[4])))
    elseif f[1] == "pres" and players[sid] then
        local pr = {x = global.tonumber(f[2]), y = global.tonumber(f[3]), z = global.tonumber(f[4]),
            yaw = global.tonumber(f[5]), pitch = global.tonumber(f[6]), act = clean(f[9]),
            fx = global.tonumber(f[10]), fy = global.tonumber(f[11]), fz = global.tonumber(f[12])}
        players[sid].pres = pr
        -- Where a player looks goes to the others right away; the roster is too slow for that.
        if pr.fx then
            local line = "p|" .. sid .. "|" .. num(pr.fx) .. "|" .. num(pr.fy) .. "|" .. num(pr.fz) .. "|" .. pr.act
            for _, other in global.ipairs(order) do
                if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
            end
        end
    elseif f[1] == "hold" and players[sid] then
        hostHold(sid, f[2] or "", f[3] or "", f[4] or "")
    elseif f[1] == "time" and players[sid] then
        local paused, index = f[2] == "1", global.tonumber(f[3]) or 1
        if sid ~= me then World.SetTime(paused, index) end
        local line = "time|" .. (paused and "1" or "0") .. "|" .. index .. "|" .. nameOf(sid)
        for _, other in global.ipairs(order) do
            if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
        end
        addFeed(timeText(nameOf(sid), paused, index))
    elseif f[1] == "cmd" and f[2] then
        -- Replayed edit (terrain, lakes, ...): host orders it and forwards it to everyone else.
        if #f[2] <= 3000 then deliver(others(sid, "K|" .. f[2])) end
    elseif f[1] == "base" and players[sid] then
        players[sid].base = global.tonumber(f[2])
    end
end

local function rosterLine()
    local parts = {}
    for _, sid in global.ipairs(order) do
        local p = players[sid]
        if p then
            local pr = p.pres or {}
            -- A joiner has no presence yet: show how far the park transfer is instead.
            local act = pr.act or "-"
            if p.sending then act = "holt" .. global.math.floor((p.sent or 0) * 100)
            elseif p.pending then act = "laedt" end
            parts[#parts+1] = global.table.concat({sid, p.name, p.color, act, num(pr.x or 0), num(pr.y or 0),
                num(pr.z or 0), num(pr.yaw or 0), global.tostring(p.base or -1),
                num(pr.fx or pr.x or 0), num(pr.fy or pr.y or 0), num(pr.fz or pr.z or 0)}, ",")
        end
    end
    local st = {}
    for name, v in global.pairs(stats) do st[#st+1] = name .. "," .. v.created .. "," .. v.edited .. "," .. v.deleted end
    local n = World.Numbers()
    local numbersText = n and (global.tostring(n.guests or 0) .. "," .. global.tostring(global.math.floor(n.cash or 0)) .. ","
        .. (n.unlimited and "1" or "0")) or ""
    return "roster|" .. global.table.concat(parts, ";") .. "|" .. global.table.concat(st, ";") .. "|" .. conflicts
        .. "|" .. numbersText
end

local function parseRoster(payload)
    local f = split(payload, "|")
    local list = {}
    for _, entry in global.ipairs(split(f[2] or "", ";")) do
        local p = split(entry, ",")
        list[#list+1] = {sid = p[1], name = p[2], color = p[3], act = p[4], x = global.tonumber(p[5]),
            y = global.tonumber(p[6]), z = global.tonumber(p[7]), yaw = global.tonumber(p[8]), base = global.tonumber(p[9]),
            fx = global.tonumber(p[10]), fy = global.tonumber(p[11]), fz = global.tonumber(p[12])}
    end
    local st = {}
    for _, entry in global.ipairs(split(f[3] or "", ";")) do
        local p = split(entry, ",")
        st[p[1]] = {created = global.tonumber(p[2]), edited = global.tonumber(p[3]), deleted = global.tonumber(p[4])}
    end
    roster = {players = list, stats = st, conflicts = global.tonumber(f[4]) or 0}
    local n = split(f[5] or "", ",")
    park = n[1] and {guests = global.tonumber(n[1]) or 0, cash = global.tonumber(n[2]) or 0, unlimited = n[3] == "1"} or nil
end

-- Inputs ----------------------------------------------------------------------------------

-- Every line sync.lua emits passes through here.
function Session.OnSyncLine(line)
    if not role then return end
    local kind, rest = global.string.match(line, "^sync:([%a%-]+)|?(.*)$")
    if kind == "desync" and role == "host" and Session._HostRefused(global.tonumber(global.string.match(rest, "^(%d+)")), rest) then
        return
    end
    if kind == "desync" then
        local first = desync == nil
        desync = global.string.match(rest, "^[^|]*|(.*)$") or rest
        if first then toast("Eine Änderung konnte hier nicht übernommen werden. Multiplayer-Fenster: \"Neu synchronisieren\".", "ff922b") end
        if role == "client" and hostId then send(hostId, "desync|" .. global.string.sub(clean(desync), 1, 120)) end
        return
    end
    if kind == "hold-denied" then Session._Denied(rest); return end
    if kind == "hold-lost" then
        toast("Ein Mitspieler hat das Objekt geaendert, das du gerade bearbeitet hast.", "ff922b")
        return
    end
    if kind == "undo-blocked" then
        toast("Rueckgaengig geht nur fuer deinen eigenen letzten Schritt - der neueste hier stammt von einem Mitspieler.", "ff922b")
        return
    end
    if kind == "rejected" then
        local reason = global.string.match(rest, "|(.*)$") or ""
        if reason == "gesperrt" then toast("Zurueckgenommen: ein Mitspieler bearbeitet dieses Objekt gerade.", "ff922b")
        elseif reason == "veraltet" then toast("Zurueckgenommen: ein Mitspieler war bei diesem Objekt schneller.", "ff922b") end
        return
    end
    if kind ~= "up" and kind ~= "del" and kind ~= "pres" and kind ~= "baseline" and kind ~= "cmd" and kind ~= "hold" then return end
    local wire = (kind == "baseline" and "base" or kind) .. "|" .. rest
    if role == "host" then hostChange(me, split(wire, "|"))
    elseif hostId then send(hostId, wire) end
end

local function onMessage(from, payload)
    local kind = global.string.match(payload, "^(%a+)")
    if role == "host" then
        if kind == "hello" then
            local f = split(payload, "|")
            if f[5] ~= Session.VERSION then
                local version = clean(f[5] or "alt")
                addFeed(clean(f[2] or "?") .. " hat PC2Coop " .. version .. ", du " .. Session.VERSION .. " - bitte beide UPDATE.cmd ausfuehren")
                send(from, "reject|" .. Session.VERSION)
                return
            end
            join(from, f[2], f[4])
            if f[3] then hostChange(from, {"base", f[3]}) end
        elseif kind == "desync" and players[from] then
            addFeed(players[from].name .. " ist nicht mehr synchron")
        elseif kind == "loadfailed" and players[from] then
            players[from].sending = false
            addFeed(players[from].name .. " konnte den Park nicht laden")
        elseif kind == "chat" and players[from] then
            Session._BroadcastChat(players[from].name, players[from].color, global.string.sub(payload, 6))
        elseif players[from] then
            hostChange(from, split(payload, "|"))
        end
    elseif from == hostId then
        if kind == "ops" then
            local lines = {}
            for line in global.string.gmatch(global.string.sub(payload, 5), "[^\n]+") do lines[#lines+1] = line end
            toGame(lines)
        elseif kind == "roster" then
            parseRoster(payload)
        elseif kind == "h" then
            local f = split(payload, "|")
            setHold(f[2], f[3] or "", f[4] or "", f[5] or "")
        elseif kind == "deny" then
            Session._Denied(clean(split(payload, "|")[2] or "?"))
        elseif kind == "time" then
            local f = split(payload, "|")
            local paused, index = f[2] == "1", global.tonumber(f[3]) or 1
            World.SetTime(paused, index)
            if f[4] and f[4] ~= "" then toast(timeText(clean(f[4]), paused, index)) end
        elseif kind == "note" then
            toast(global.string.sub(payload, 6), "fcc419")
        elseif kind == "p" then
            local f = split(payload, "|")
            for _, pl in global.ipairs(roster.players or {}) do
                if pl.sid == f[2] then
                    pl.fx, pl.fy, pl.fz, pl.act = global.tonumber(f[3]), global.tonumber(f[4]), global.tonumber(f[5]), f[6]
                end
            end
        elseif kind == "park" then
            local f = split(payload, "|")
            transfer.world, transfer.name = f[2], f[3]
            Session._TryLoad()
        elseif kind == "feed" then
            feed[#feed+1] = global.string.sub(payload, 6)
            while #feed > 30 do global.table.remove(feed, 1) end
            toast(feed[#feed])
        elseif kind == "reject" then
            local hostVersion = clean(split(payload, "|")[2] or "?")
            toast("Der Host hat PC2Coop " .. hostVersion .. ", du " .. Session.VERSION .. ". Bitte UPDATE.cmd ausfuehren (Spiel vorher beenden).", "ff6b6b")
            emit("session:rejected-version|" .. hostVersion)
            Session.Leave()
        elseif kind == "chat" then
            local f = split(payload, "|")
            Session._AddChat(f[2], f[3], global.string.sub(payload, #f[1] + #f[2] + #f[3] + 4))
        end
    end
end

-- Joiner: ask the host for its park (first join, retry, resync).
local function requestPark()
    remember("lobby", lobbyId)
    remember("phase", "awaiting")
    transfer, progress, joinFailure, desync = {}, {}, nil, nil
    emit("session:awaiting-park|" .. lobbyId .. "|" .. global.tostring(hostName))
    send(hostId, "hello|" .. myName .. "|-1|needpark|" .. Session.VERSION)
end

local function failJoin(reason, tellHost)
    joinFailure = reason
    if lobbyId then remember("phase", "failed") end
    emit("session:join-failed|" .. reason)
    if tellHost and hostId then send(hostId, "loadfailed|") end
end

local function onNet(event)
    local f = split(event, "|")
    local kind = f[1]
    if kind == "net:ready" then
        me, myName = f[2], clean(f[3])
        emit("session:net-ready|" .. me .. "|" .. myName)
    elseif kind == "lobby:entered" then
        -- Steam can report one entry twice; this module instance answers it once.
        if helloLobby == f[2] then return end
        lobbyId, hostId, helloLobby = f[2], f[3], f[2]
        joining, hostName = false, clean(f[4] or "")
        local phase = memory.lobby == lobbyId and memory.phase or nil
        if hostId == me then
            if context == "menu" then
                -- Back in the main menu: there is no park to share any more.
                toast("Sitzung beendet: du hast den Park verlassen.")
                Session.Leave()
                return
            end
            role = "host"
            join(me, myName)
            remember("lobby", lobbyId)
            remember("phase", "host")
            emit("session:hosting|" .. lobbyId)
            sync.Receive("S|" .. myName)
        elseif context == "menu" and phase == "loading" then
            -- The game came back to the menu instead of opening the park.
            role = "client"
            failJoin("Der Park des Hosts konnte nicht geladen werden.", true)
        elseif context == "menu" and phase == "failed" then
            role = "client"
            joinFailure = joinFailure or "Der Park des Hosts konnte nicht geladen werden."
        elseif context == "menu" and phase == "live" then
            role = "client"
            toast("Du hast die Sitzung verlassen.")
            Session.Leave()
        elseif context == "park" and phase == "loading" then
            role = "client"
            remember("phase", "live")
            emit("session:joined|" .. lobbyId .. "|" .. hostName)
            sync.Receive("S|" .. myName)
            send(hostId, "hello|" .. myName .. "|-1|loaded|" .. Session.VERSION)
            toast("Bereit: du baust jetzt im Park von " .. hostName .. ".", "51cf66")
            World.ApplyGuestProfile()
        elseif context == "park" and phase == "live" then
            role = "client"
            sync.Receive("S|" .. myName)
            send(hostId, "hello|" .. myName .. "|-1|live|" .. Session.VERSION)
        else
            role = "client"
            requestPark()
        end
    elseif kind == "lobby:join-failed" then
        joining = false
        local code = global.tonumber(f[2]) or 0
        local reasons = {[2] = "Diese Einladung ist abgelaufen: die Sitzung gibt es nicht mehr. Lass dich neu einladen.",
            [4] = "Die Sitzung ist voll.", [6] = "Die Sitzung ist nur fuer Steam-Freunde des Hosts."}
        failJoin(reasons[code] or ("Beitritt nicht moeglich (Steam-Code " .. code .. "). Lass dich neu einladen."), false)
    elseif kind == "member:join" then
        emit("session:member|" .. f[2] .. "|" .. clean(f[3]))
    elseif kind == "member:leave" then
        if role == "host" then leave(f[2]) end
        if f[2] == hostId and role == "client" then
            addFeed("Host hat die Sitzung beendet")
            Session.Leave()
        end
    elseif kind == "msg" then
        onMessage(f[2], global.string.sub(event, #f[1] + #f[2] + 3))
    elseif kind == "invite:accepted" then
        if role and lobbyId == f[2] then
            toast("Du bist bereits in dieser Sitzung.")
            return
        end
        if role then Session.Leave() end
        joining, progress, joinFailure = true, {}, nil
        net.NetCommand("join|" .. f[2])
        emit("session:joining|" .. f[2])
    elseif kind == "key:menu" then
        if Session.OnMenuKey then Session.OnMenuKey() end
    elseif kind == "key:dev" then
        if Session.OnDevKey then Session.OnDevKey() end
    elseif kind == "friends:begin" then
        friendsLoading = {}
    elseif kind == "friend" then
        local invitedAt
        for _, old in global.ipairs(friends) do if old.sid == f[2] then invitedAt = old.invitedAt end end
        friendsLoading[#friendsLoading+1] = {sid = f[2], name = clean(f[3]), state = global.tonumber(f[4]) or 0,
            pc2 = f[5] == "1", invitedAt = invitedAt}
    elseif kind == "friends:end" then
        -- Playing Planet Coaster 2 first, then online, then the rest; alphabetical within.
        global.table.sort(friendsLoading, function(a, b)
            local ra = a.pc2 and 0 or (a.state > 0 and 1 or 2)
            local rb = b.pc2 and 0 or (b.state > 0 and 1 or 2)
            if ra ~= rb then return ra < rb end
            return global.string.lower(a.name) < global.string.lower(b.name)
        end)
        friends = friendsLoading
    elseif kind == "invite:sent" then
        for _, fr in global.ipairs(friends) do
            if fr.sid == f[2] then fr.invitedAt = frames; toast("Einladung an " .. fr.name .. " gesendet") end
        end
    elseif kind == "invite:failed" then
        toast("Einladung konnte nicht gesendet werden")
    elseif kind == "kv" then
        memory[f[2]] = f[3]
    elseif kind == "file:progress" then
        progress[f[2]] = {global.tonumber(f[3]) or 0, global.tonumber(f[4]) or 1}
    elseif kind == "file:done" then
        local total = global.tonumber(f[4]) or 1
        progress[f[3]] = {total, total}
        transfer[f[3]] = true
        Session._TryLoad()
    elseif kind == "file:sending" and players[f[2]] then
        -- Host: terrain first, then the park; both about the same size.
        local share = (global.tonumber(f[4]) or 0) / global.math.max(1, global.tonumber(f[5]) or 1)
        players[f[2]].sent = (f[3] == "pc2coop-join.bin" and 0.5 or 0) + share * 0.5
    elseif kind == "file:sent" and players[f[2]] then
        if f[3] == "pc2coop-join.bin" then players[f[2]].sending, players[f[2]].sent = false, 1
        else players[f[2]].sent = 0.5 end
    elseif kind == "net:peer-stalled" then
        if players[f[2]] then players[f[2]].sending = false end
        -- Steam accepted nothing for this player for a minute: the data for them is gone.
        local who = players[f[2]] and players[f[2]].name or "Ein Mitspieler"
        addFeed("Verbindung zu " .. who .. " haengt - bitte neu beitreten")
        emit("session:peer-stalled|" .. f[2] .. "|" .. global.tostring(f[3]))
    elseif kind == "lobby:created" then
        emit("session:lobby-created|" .. f[2])
    elseif kind == "lobby:left" then
        role, hostId, lobbyId, helloLobby = nil, nil, nil, nil
    else
        emit("session:" .. event)
    end
end

-- Public API --------------------------------------------------------------------------------

function Session.Init(logger, diagnostic, syncModule, parkManager)
    emit, net, sync, manager = logger, diagnostic, syncModule, parkManager
    if context == "park" then
        shared.onTime = function(paused, index) Session._LocalTime(paused, index) end
        shared.onNotification = function(text) Session._ParkNote(text) end
    end
    helloLobby = nil   -- a new menu or park: the DLL reports the lobby again
    emit("session:init|" .. global.tostring(net.NetStatus and net.NetStatus()))
    -- Module state was reset (new park); the DLL still knows lobby and phase.
    if Session.Available() then net.NetCommand("status") end
end

-- Opens the transferred park file (next to the game's exe) as a sandbox park.
function Session._LoadPark(world, name)
    global.pcall(function()
        local nextData = global.api.game.GetEnvironment():RequireInterface("Interfaces.INextWorldDataManager")
        nextData:SetGameMode("Sandbox", "ScenarioEdit")
        nextData:SetParkName(name or "PC2 Co-op")
    end)
    return manager:RequestLoadParkFromFile("/run/pc2coop-join.bin", world, nil, name, false)
end

-- Joiner: load the host's park once both files and the description arrived.
function Session._TryLoad()
    if role ~= "client" or not transfer.world or not transfer["pc2coop-join.bin"] or not transfer["pc2coop-join.trn"] then return end
    if transfer.started or not manager then return end
    transfer.started = true
    remember("phase", "loading")
    emit("session:loading-park|" .. transfer.world)
    local ok, failure = Session._LoadPark(transfer.world, transfer.name)
    if not ok then
        transfer.started = false
        failJoin("Die uebertragene Park-Datei ist ungueltig (" .. global.tostring(failure) .. ").", true)
    end
end

function Session.Available() return net and net.HasNet() end

-- "Eingeladen" wears off, so a friend who missed the invite can be invited again.
function Session.Friends()
    for _, fr in global.ipairs(friends) do
        fr.invited = fr.invitedAt ~= nil and frames - fr.invitedAt < INVITE_FRAMES
    end
    return friends
end

-- "menu": the main menu is open (joining only). "park": a park is loaded.
function Session.SetContext(value) context = value == "menu" and "menu" or "park" end
function Session.Chat() return chat end
function Session.Toasts() return toasts end
function Session.RefreshFriends() net.NetCommand("friends") end
function Session.InviteFriend(sid)
    if global.type(sid) == "string" and global.string.match(sid, "^%d+$") then net.NetCommand("invite_user|" .. sid) end
end

function Session._AddChat(name, color, text)
    chat[#chat+1] = {name = clean(name), color = color, text = global.string.sub(global.tostring(text), 1, 200)}
    while #chat > 40 do global.table.remove(chat, 1) end
    toast(clean(name) .. ": " .. chat[#chat].text, color)
end

function Session._BroadcastChat(name, color, text)
    text = global.string.gsub(global.string.sub(global.tostring(text), 1, 200), "[\n\r]", " ")
    Session._AddChat(name, color, text)
    for _, sid in global.ipairs(order) do
        if sid ~= me then send(sid, "chat|" .. clean(name) .. "|" .. global.tostring(color) .. "|" .. text) end
    end
end

function Session.SendChat(text)
    if not role or global.type(text) ~= "string" or text == "" then return end
    text = global.string.gsub(global.string.sub(text, 1, 200), "[\n\r|]", " ")
    if role == "host" then
        local p = players[me] or {}
        Session._BroadcastChat(myName, p.color, text)
    elseif hostId then
        send(hostId, "chat|" .. text)
    end
end

function Session.Host()
    if role then return end
    objects, tombstones, stats, players, order, counter, conflicts = {}, {}, {}, {}, {}, 0, 0
    net.NetCommand("host")
end

function Session.Invite() net.NetCommand("invite") end

-- Joiner progress for the UI: phase ("joining", "awaiting", "loading", "live"), share of the
-- park files received (0..1) and the host's name. Nil when not joining or in a session.
function Session.JoinState()
    if joinFailure then return {phase = "failed", reason = joinFailure, retry = role == "client" and hostId ~= nil, host = hostName} end
    if joining then return {phase = "joining", progress = 0} end
    if role ~= "client" then return nil end
    local got, total = 0, 0
    for _, p in global.pairs(progress) do got, total = got + p[1], total + p[2] end
    return {phase = memory.phase or "awaiting", progress = total > 0 and got / total or 0, host = hostName}
end

function Session.Desync() return desync end
function Session.Park() return park end
function Session.Holds() return holds end

function Session._Denied(name)
    toast(global.tostring(name) .. " bearbeitet das gerade. Dein Werkzeug wurde zurueckgesetzt.", "ff922b")
    World.LeaveTool()
end

-- The local player paused or changed the speed (reported by the HUD hook).
function Session._LocalTime(paused, index)
    if not role then return end
    local wire = "time|" .. (paused and "1" or "0") .. "|" .. index
    if role == "host" then hostChange(me, split(wire, "|")) elseif hostId then send(hostId, wire) end
end

-- Host: a notification of the host's park (ride broken down, ...) goes to everyone.
function Session._ParkNote(text)
    if role ~= "host" or global.type(text) ~= "string" then return end
    if lastNote[text] and frames - lastNote[text] < 600 then return end
    emit("session:park-note|" .. global.string.sub(text, 1, 160))
    lastNote[text] = frames
    text = global.string.gsub(global.string.sub(text, 1, 300), "[\n\r]", " ")
    for _, sid in global.ipairs(order) do
        if sid ~= me and players[sid] and not players[sid].pending then send(sid, "note|" .. text) end
    end
end

-- Host: this game could not apply a change that the session already accepted (e.g. a
-- friend built outside this park's boundary). The session is put back to what the host
-- has, so the parks stay equal. Returns true when handled.
function Session._HostRefused(seq, rest)
    local line = seq and recent[seq]
    if not line then return false end
    local f = split(line, "|")
    if f[1] ~= "U" then return false end
    local gid = f[3]
    local state = sync.StateOf and sync.StateOf(gid)
    local why = global.string.find(rest, "invalid-placement", 1, true) and "hier nicht moeglich (z. B. ausserhalb der Parkgrenze)" or "beim Host nicht moeglich"
    local owner = objects[gid] and objects[gid].last or "?"
    if state then
        local current = objects[gid] or {rev = 0, creator = "Park"}
        objects[gid] = {res = state.res, p = state.p, q = state.q, s = state.s, rev = current.rev + 1, last = "Host", creator = current.creator}
        deliver(others(me, upsertLine(gid)))
        addFeed("Aenderung von " .. owner .. " zurueckgenommen: " .. why)
    else
        objects[gid], tombstones[gid] = nil, true
        deliver(others(me, "D|" .. gid .. "|host|0"))
        addFeed("Objekt von " .. owner .. " entfernt: " .. why)
    end
    return true
end

-- Joiner: fetch the host's current park again (after a change failed to apply here).
function Session.Resync()
    if role ~= "client" or not hostId then return end
    requestPark()
    emit("session:resync")
end

-- Close the "joining failed" notice; also leaves the lobby the failed join is still in.
function Session.DismissJoin()
    local inLobby = role ~= nil
    joinFailure, joining = nil, false
    if inLobby then Session.Leave() end
end

function Session.Leave()
    joining, progress, desync, joinFailure, helloLobby = false, {}, nil, nil, nil
    locks, holds, bursts, recent, park, lastNote = {}, {}, {}, {}, nil, {}
    if sync.SetRemoteLocks then sync.SetRemoteLocks({}) end
    for _, fr in global.ipairs(friends) do fr.invitedAt = nil end
    net.NetCommand("leave")
    sync.Receive("X")
    role, hostId, lobbyId, players, order, roster = nil, nil, nil, {}, {}, {}
end

-- Snapshot for in-game UI and labels: players with name, colour, activity and position.
function Session.View()
    if role == "host" then
        local list = {}
        for _, sid in global.ipairs(order) do
            local p = players[sid]
            if p then
                local pr = p.pres or {}
                local act = pr.act
                if p.sending then act = "holt" .. global.math.floor((p.sent or 0) * 100)
                elseif p.pending then act = "laedt" end
                list[#list+1] = {sid = sid, name = p.name, color = p.color, act = act, x = pr.x, y = pr.y, z = pr.z,
                    yaw = pr.yaw, base = p.base, fx = pr.fx, fy = pr.fy, fz = pr.fz, hold = holds[sid]}
            end
        end
        return {role = role, me = me, host = me, lobby = lobbyId, players = list, stats = stats, conflicts = conflicts, feed = feed,
            park = World.Numbers()}
    end
    for _, pl in global.ipairs(roster.players or {}) do pl.hold = holds[pl.sid] end
    return {role = role, me = me, host = hostId, lobby = lobbyId, players = roster.players or {}, stats = roster.stats or {},
        conflicts = roster.conflicts or 0, feed = feed, park = park}
end

function Session.Tick()
    frames = frames + 1
    if not Session.Available() then return end
    for _ = 1, 64 do
        local event = net.NetPoll()
        if not event then break end
        local ok, failure = global.pcall(onNet, event)
        if not ok then emit("session:error|" .. global.tostring(failure)) end
    end
    for i = #tasks, 1, -1 do
        local ok, failure = global.coroutine.resume(tasks[i])
        if not ok then emit("session:task-error|" .. global.tostring(failure)) end
        if not ok or global.coroutine.status(tasks[i]) == "dead" then global.table.remove(tasks, i) end
    end
    if role == "host" then flushActions(false) end
    if role == "host" and frames - lastRoster >= 30 then
        lastRoster = frames
        local line = rosterLine()
        for _, sid in global.ipairs(order) do if sid ~= me then send(sid, line) end end
        parseRoster(line)
    end
end

-- Test seam: drive the session without Steam.
Session._onNet = onNet
return Session
