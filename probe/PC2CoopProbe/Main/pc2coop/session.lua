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

-- Mod version; must match the database's probeVersion (checked by the tests).
Session.VERSION = "1.4.2"
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

local function validResource(res) return global.type(res) == "string" and global.string.match(res, "^[%w_%.%-]+$") and #res <= 96 end
local function validGid(gid) return gid == "" or (global.string.match(gid, "^[%w_%.%-]+$") and #gid <= 64) end

local function authorityUp(sid, part, gid, rev, res, p, q, s)
    if not validResource(res) or not validGid(gid) then return {} end
    local name = nameOf(sid)
    local state = {res = res, p = p, q = q, s = s, last = name}
    if gid == "" then
        counter = counter + 1
        gid = global.string.format("%s-%d", global.string.sub(sid, -6), counter)
        state.rev, state.creator = 1, name
        count(sid, "created")
        addFeed(name .. " hat " .. res .. " platziert")
    elseif objects[gid] then
        local current = objects[gid]
        if rev ~= current.rev then return restore(sid, gid, "veraltet") end
        state.rev, state.creator = current.rev + 1, current.creator
        count(sid, "edited")
        addFeed(name .. " hat " .. res .. " bearbeitet")
    elseif tombstones[gid] then
        return restore(sid, gid, "geloescht")
    elseif global.string.sub(gid, 1, 1) == "P" and rev == 0 then
        state.rev, state.creator = 1, "Park"
        count(sid, "edited")
        addFeed(name .. " hat " .. res .. " bearbeitet")
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
    local ok, failure = manager:SaveTerrainToFile("/run/pc2coop-host.trn", true)
    global.assert(ok, "terrain save failed: " .. global.tostring(failure))
    ok, failure = manager:SaveParkToFile("/run/pc2coop-host.bin", true, false)
    global.assert(ok, "park save failed: " .. global.tostring(failure))
    net.NetCommand("file|" .. sid .. "|pc2coop-host.trn|pc2coop-join.trn")
    net.NetCommand("file|" .. sid .. "|pc2coop-host.bin|pc2coop-join.bin")
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
    if mode == "needpark" then
        players[sid].pending = {}
        addFeed(players[sid].name .. " tritt bei und laedt den Park")
        tasks[#tasks+1] = global.coroutine.create(function() sendPark(sid) end)
    elseif mode == "loaded" and players[sid].pending then
        addFeed(players[sid].name .. " ist beigetreten")
        catchUp(sid)
    else
        if not returning then addFeed(players[sid].name .. " ist beigetreten") end
        local snapshot = {}
        for gid in global.pairs(objects) do snapshot[#snapshot+1] = {sid, upsertLine(gid)} end
        deliver(snapshot)
    end
end

local function leave(sid)
    if players[sid] then
        addFeed(players[sid].name .. " hat die Sitzung verlassen")
        players[sid] = nil
        for i, other in global.ipairs(order) do if other == sid then global.table.remove(order, i); break end end
    end
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
        players[sid].pres = {x = global.tonumber(f[2]), y = global.tonumber(f[3]), z = global.tonumber(f[4]),
            yaw = global.tonumber(f[5]), pitch = global.tonumber(f[6]), act = clean(f[9])}
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
            parts[#parts+1] = global.table.concat({sid, p.name, p.color, pr.act or "-", num(pr.x or 0), num(pr.y or 0),
                num(pr.z or 0), num(pr.yaw or 0), global.tostring(p.base or -1)}, ",")
        end
    end
    local st = {}
    for name, v in global.pairs(stats) do st[#st+1] = name .. "," .. v.created .. "," .. v.edited .. "," .. v.deleted end
    return "roster|" .. global.table.concat(parts, ";") .. "|" .. global.table.concat(st, ";") .. "|" .. conflicts
end

local function parseRoster(payload)
    local f = split(payload, "|")
    local list = {}
    for _, entry in global.ipairs(split(f[2] or "", ";")) do
        local p = split(entry, ",")
        list[#list+1] = {sid = p[1], name = p[2], color = p[3], act = p[4], x = global.tonumber(p[5]),
            y = global.tonumber(p[6]), z = global.tonumber(p[7]), yaw = global.tonumber(p[8]), base = global.tonumber(p[9])}
    end
    local st = {}
    for _, entry in global.ipairs(split(f[3] or "", ";")) do
        local p = split(entry, ",")
        st[p[1]] = {created = global.tonumber(p[2]), edited = global.tonumber(p[3]), deleted = global.tonumber(p[4])}
    end
    roster = {players = list, stats = st, conflicts = global.tonumber(f[4]) or 0}
end

-- Inputs ----------------------------------------------------------------------------------

-- Every line sync.lua emits passes through here.
function Session.OnSyncLine(line)
    if not role then return end
    local kind, rest = global.string.match(line, "^sync:([%a%-]+)|?(.*)$")
    if kind == "desync" then
        local first = desync == nil
        desync = global.string.match(rest, "^[^|]*|(.*)$") or rest
        if first then toast("Eine Änderung konnte hier nicht übernommen werden. Multiplayer-Fenster: \"Neu synchronisieren\".", "ff922b") end
        if role == "client" and hostId then send(hostId, "desync|" .. global.string.sub(clean(desync), 1, 120)) end
        return
    end
    if kind ~= "up" and kind ~= "del" and kind ~= "pres" and kind ~= "baseline" and kind ~= "cmd" then return end
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

local function onNet(event)
    local f = split(event, "|")
    local kind = f[1]
    if kind == "net:ready" then
        me, myName = f[2], clean(f[3])
        emit("session:net-ready|" .. me .. "|" .. myName)
    elseif kind == "lobby:entered" then
        lobbyId, hostId = f[2], f[3]
        joining, hostName = false, clean(f[4] or "")
        if hostId == me then
            role = "host"
            join(me, myName)
            remember("lobby", lobbyId)
            remember("phase", "host")
            emit("session:hosting|" .. lobbyId)
            sync.Receive("S|" .. myName)
        else
            role = "client"
            if memory.phase == "loading" and memory.lobby == lobbyId then
                remember("phase", "live")
                emit("session:joined|" .. lobbyId .. "|" .. clean(f[4]))
                sync.Receive("S|" .. myName)
                send(hostId, "hello|" .. myName .. "|-1|loaded|" .. Session.VERSION)
            elseif memory.phase == "live" and memory.lobby == lobbyId then
                sync.Receive("S|" .. myName)
                send(hostId, "hello|" .. myName .. "|-1|live|" .. Session.VERSION)
            else
                remember("lobby", lobbyId)
                remember("phase", "awaiting")
                transfer = {}
                emit("session:awaiting-park|" .. lobbyId .. "|" .. clean(f[4]))
                send(hostId, "hello|" .. myName .. "|-1|needpark|" .. Session.VERSION)
            end
        end
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
        if role then Session.Leave() end
        joining, progress = true, {}
        net.NetCommand("join|" .. f[2])
        emit("session:joining|" .. f[2])
    elseif kind == "key:menu" then
        if Session.OnMenuKey then Session.OnMenuKey() end
    elseif kind == "key:dev" then
        if Session.OnDevKey then Session.OnDevKey() end
    elseif kind == "friends:begin" then
        friendsLoading = {}
    elseif kind == "friend" then
        local invited = false
        for _, old in global.ipairs(friends) do if old.sid == f[2] then invited = old.invited end end
        friendsLoading[#friendsLoading+1] = {sid = f[2], name = clean(f[3]), state = global.tonumber(f[4]) or 0,
            pc2 = f[5] == "1", invited = invited}
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
        for _, fr in global.ipairs(friends) do if fr.sid == f[2] then fr.invited = true; toast("Einladung an " .. fr.name .. " gesendet") end end
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
    elseif kind == "lobby:created" then
        emit("session:lobby-created|" .. f[2])
    elseif kind == "lobby:left" then
        role, hostId, lobbyId = nil, nil, nil
    else
        emit("session:" .. event)
    end
end

-- Public API --------------------------------------------------------------------------------

function Session.Init(logger, diagnostic, syncModule, parkManager)
    emit, net, sync, manager = logger, diagnostic, syncModule, parkManager
    emit("session:init|" .. global.tostring(net.NetStatus and net.NetStatus()))
    -- Module state was reset (new park); the DLL still knows lobby and phase.
    if Session.Available() then net.NetCommand("status") end
end

-- Joiner: load the host's park once both files and the description arrived.
function Session._TryLoad()
    if role ~= "client" or not transfer.world or not transfer["pc2coop-join.bin"] or not transfer["pc2coop-join.trn"] then return end
    if transfer.started or not manager then return end
    transfer.started = true
    remember("phase", "loading")
    emit("session:loading-park|" .. transfer.world)
    global.pcall(function()
        local nextData = global.api.game.GetEnvironment():RequireInterface("Interfaces.INextWorldDataManager")
        nextData:SetGameMode("Sandbox", "ScenarioEdit")
        nextData:SetParkName(transfer.name or "PC2 Co-op")
    end)
    local ok, failure = manager:RequestLoadParkFromFile("/run/pc2coop-join.bin", transfer.world, nil, transfer.name, false)
    if not ok then emit("session:load-failed|" .. global.tostring(failure)); remember("phase", "awaiting") end
end

function Session.Available() return net and net.HasNet() end

function Session.Friends() return friends end
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
    if joining then return {phase = "joining", progress = 0} end
    if role ~= "client" then return nil end
    local got, total = 0, 0
    for _, p in global.pairs(progress) do got, total = got + p[1], total + p[2] end
    return {phase = memory.phase or "awaiting", progress = total > 0 and got / total or 0, host = hostName}
end

function Session.Desync() return desync end

-- Joiner: fetch the host's current park again (after a change failed to apply here).
function Session.Resync()
    if role ~= "client" or not hostId then return end
    desync, transfer, progress = nil, {}, {}
    remember("phase", "awaiting")
    send(hostId, "hello|" .. myName .. "|-1|needpark|" .. Session.VERSION)
    emit("session:resync")
end

function Session.Leave()
    joining, progress, desync = false, {}, nil
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
                list[#list+1] = {sid = sid, name = p.name, color = p.color, act = pr.act, x = pr.x, y = pr.y, z = pr.z,
                    yaw = pr.yaw, base = p.base}
            end
        end
        return {role = role, me = me, host = me, lobby = lobbyId, players = list, stats = stats, conflicts = conflicts, feed = feed}
    end
    return {role = role, me = me, host = hostId, lobby = lobbyId, players = roster.players or {}, stats = roster.stats or {},
        conflicts = roster.conflicts or 0, feed = feed}
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
