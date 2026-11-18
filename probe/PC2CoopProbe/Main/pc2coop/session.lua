-- Original MIT code. In-game co-op session over Steam (no external program).
--
-- Roles: the lobby owner is the host and runs the Authority (ordering, revisions,
-- attribution); everyone else is a client. Local game changes come from sync.lua as
-- "sync:*" lines, remote ones go back into sync.lua as numbered op lines.
-- Wire messages (Steam, reliable, text):
--   client -> host: hello|<name>|<baseline>|<mode>|<version>|<game>|<dlc>|<mods>   up|...   del|...   pres|...
--     mode: lobby (main menu), needpark, loaded, live
--   host -> client: stage|lobby or park|<park token>|<park name>|<content guard>
--   host -> client: reject|<host version>   (different mod versions never play together)
--   host -> client: ops\n<line>...   roster|<players>   feed|<text>   welcome|<color>
local global = _G
local Session = {}
local World = global.require("pc2coop.world")
local shared = global.require("pc2coop.shared")

-- Mod version; must match the database's probeVersion (checked by the tests).
Session.VERSION = "1.11.0"
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
local askBeforeJoin = true  -- host: a friend who was not invited from here needs the host's OK
local invited, approved, requests = {}, {}, {}  -- host: who was invited / let in / is asking
local joinSource = nil    -- joiner: "launch" when the lobby id came with the game's start
local confirm = nil       -- joiner: {host} while the player has not agreed to join yet
local waiting = false     -- joiner: the host has not let us in yet
local gameVersion = ""    -- this game's version; players of different versions do not mix
local pings = {}          -- sid -> {x, y, z, frame}: "here!" markers, shown for PING_FRAMES
local PING_FRAMES = 480
local lastPing = {}       -- host: sid -> frame of their last ping (one per second at most)
-- Visitor mode (visitor.lua): emotes and ratings of rides, for everyone in the session.
local EMOTES = {wave = "winkt", cheer = "jubelt", laugh = "lacht", sick = "ist schlecht", up = "findet das super",
    down = "findet das nicht gut"}
local emotes = {}         -- sid -> {kind, frame}
local lastEmote = {}      -- host: sid -> frame of the last emote (one per second at most)
local ratings = {}        -- ride key -> {name, by = {sid -> {stars, text, who}}}
local following = nil     -- sid whose camera this player follows
local savedAuthors = {}   -- host: local part -> {res, creator, last} from earlier sessions in this park
local authorsFile = nil   -- host: "pc2coop-authors-<park>.txt"
local dirtyAuthors = {}   -- host: gid -> true, attribution not yet written to the file
local whoCache = {}       -- gid -> {creator, last} as the host answered
local watched, watchedAt = nil, 0  -- gid the local player selects or holds, frame it was asked
local notes = {}          -- note file name -> text being read from the DLL
local lastHostFrame = 0   -- joiner: frame of the last message from the host
local hostSilent = false  -- joiner: no word from the host for a while
local selfStalled = false -- joiner: Steam dropped what this game sent to the host
local departed = {}       -- host: sid -> colour of players who left (they keep it on return)
local rejoin = nil        -- menu: {lobby, host, hostSid} of a session this game dropped out of
local LAST_SESSION = "pc2coop-lastsession.txt"
-- Lobby: the host can wait in the main menu with everyone before a park is chosen.
local stage = nil         -- "lobby" (host in the main menu) or "park"; joiners: as the host said last
local parkToken = nil     -- id of the park the session plays (a new one for every park the host opens)
local parkTitle = ""      -- name of the host's park
local seenStage = nil     -- joiner: stage|token last acted on
local myDlc, myMods = nil, ""  -- owned DLC packs (bit mask, from the UI) and folders of other mods
local contentGuard = true -- host: objects from a DLC that not every player owns are not built
local avatars, avatarAsked = {}, {}  -- sid -> profile picture (base64 PNG), asked once
local choice = nil        -- lobby: the park the host picked {kind, title, detail, starting}
local middle = nil        -- middle mouse button pressed: {frame, camera} (a short click pings)
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

-- A short text a player typed (rating comment): no separators, at most 120 characters.
local function cleanText(text)
    text = global.string.gsub(global.tostring(text or ""), "[|\n\r]", " ")
    return global.string.sub(text, 1, 120)
end

local function validRideKey(key) return global.string.match(key or "", "^F%-?%d+_%-?%d+_%-?%d+$") ~= nil and #key <= 40 end

local send

-- loc: the text is in the game's own notification format and is translated by the UI.
-- Only notifications of the host's park are; anything a player typed never is.
local function toast(text, color, loc)
    toastId = toastId + 1
    toasts[#toasts+1] = {id = toastId, text = text, color = color, loc = loc == true}
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
        if p and p.lobby then
            -- In the main menu: the park comes as a whole when they load it.
        elseif p and p.pending then
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

-- True when some bit of need is not in mask (both whole numbers below 2^53).
local function lacks(mask, need)
    mask, need = global.math.floor(mask or 0), global.math.floor(need or 0)
    while need > 0 do
        if need % 2 == 1 and mask % 2 == 0 then return true end
        need, mask = global.math.floor(need / 2), global.math.floor(mask / 2)
    end
    return false
end

-- Mod folder names, ";"-separated, as a clean list.
local function modList(text)
    local out = {}
    for entry in global.string.gmatch(global.tostring(text or ""), "[^;/]+") do
        local name = global.string.sub(global.string.gsub(entry, "[^%w_%-%. ]", ""), 1, 48)
        if name ~= "" and #out < 40 then out[#out+1] = name end
    end
    return out
end

local function setContent(sid, dlc, mods)
    local p = players[sid]
    if not p then return end
    p.dlc = global.tonumber(dlc)
    if mods ~= nil then p.mods = modList(mods) end
end

-- Host: everyone invited or let in may come back without asking again (kept across park loads).
local function persistAdmitted()
    local list = {}
    for sid in global.pairs(invited) do list[#list+1] = sid end
    for sid in global.pairs(approved) do if not invited[sid] then list[#list+1] = sid end end
    remember("admitted", global.table.concat(list, ","))
end

local function helloLine(mode)
    return "hello|" .. myName .. "|-1|" .. mode .. "|" .. Session.VERSION .. "|" .. gameVersion .. "|"
        .. global.tostring(myDlc or "") .. "|" .. myMods
end

local function stageLine()
    return "stage|" .. global.tostring(stage) .. "|" .. global.tostring(parkToken or "") .. "|" .. clean(parkTitle)
        .. "|" .. (contentGuard and "1" or "0")
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

-- Who made an object and who changed it last; nil when nobody in a session touched it.
local function authorOf(gid)
    local o = objects[gid]
    if o then return o.creator or "Park", o.last or "?" end
    local part = sync.LocalPart and sync.LocalPart(gid)
    local saved = part and savedAuthors[part]
    if saved then return saved.creator, saved.last end
    return nil
end

local function markAuthor(gid) if authorsFile then dirtyAuthors[gid] = true end end

-- Writes new attributions as "part|resource|creator|last" lines (later lines win). The part
-- id is the host's own and survives saving and loading the park.
local function flushAuthors()
    if not authorsFile or global.next(dirtyAuthors) == nil then return end
    local lines = {}
    for gid in global.pairs(dirtyAuthors) do
        local part = sync.LocalPart and sync.LocalPart(gid)
        local o = objects[gid]
        if part and o then
            lines[#lines+1] = global.table.concat({part, o.res, clean(o.creator or "Park"), clean(o.last or "?")}, "|")
            savedAuthors[part] = {res = o.res, creator = o.creator, last = o.last}
            dirtyAuthors[gid] = nil
        elseif not o then
            dirtyAuthors[gid] = nil
        end
        if #lines >= 60 then break end
    end
    if #lines > 0 then net.NetCommand("note-append|" .. authorsFile .. "|" .. global.table.concat(lines, "\n") .. "\n") end
end

local function loadAuthors(text)
    savedAuthors = {}
    for line in global.string.gmatch(text or "", "[^\n]+") do
        local f = split(line, "|")
        local part = global.tonumber(f[1])
        -- Only where the same kind of object still stands (the park may not have been saved).
        local here = part and sync.StateOf and sync.StateOf("P" .. part)
        if here and here.res == f[2] and f[3] then savedAuthors[part] = {res = f[2], creator = f[3], last = f[4] or f[3]} end
    end
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

local function authorityUp(sid, part, gid, rev, res, p, q, s, need)
    if not validResource(res) or not validGid(gid) then return {} end
    if lockedByOther(sid, gid) then return refuseLocked(sid, gid) end
    if gid == "" and contentGuard and need and need > 0 then
        -- A new object from a DLC: built only when everyone owns that DLC.
        local missing = {}
        for _, other in global.ipairs(order) do
            local pl = players[other]
            if pl and pl.dlc and lacks(pl.dlc, need) then missing[#missing+1] = pl.name end
        end
        if #missing > 0 then
            counter = counter + 1
            local refused = global.string.format("%s-%d", global.string.sub(sid, -6), counter)
            tombstones[refused] = 1
            local text = global.table.concat(missing, ", ")
            if sid == me then Session._ContentRefused(need, text) else send(sid, "content|" .. global.math.floor(need) .. "|" .. text) end
            return {{sid, "M|" .. refused .. "|" .. part .. "|1"}, {sid, "D|" .. refused .. "|host|0"}}
        end
    end
    local name = nameOf(sid)
    local state = {res = res, p = p, q = q, s = s, last = name}
    if gid == "" then
        counter = counter + 1
        gid = global.string.format("%s-%d", global.string.sub(sid, -6), counter)
        state.rev, state.creator = 1, name
        count(sid, "created")
        markAuthor(gid)
        noteAction(sid, "platziert", res)
    elseif objects[gid] then
        local current = objects[gid]
        if rev ~= current.rev then return restore(sid, gid, "veraltet") end
        state.rev, state.creator = current.rev + 1, current.creator
        markAuthor(gid)
        count(sid, "edited")
        noteAction(sid, "bearbeitet", res)
    elseif tombstones[gid] then
        return restore(sid, gid, "geloescht")
    elseif global.string.sub(gid, 1, 1) == "P" and rev == 0 then
        local saved = savedAuthors[global.tonumber(global.string.sub(gid, 2)) or -1]
        state.rev, state.creator = 1, saved and saved.creator or "Park"
        markAuthor(gid)
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
    -- Manifest of this copy: which shared object is which part in it, at its revision. The
    -- joiner's aliases come from here, so an object deleted while the copy travels still
    -- gets its alias and the delete that follows finds it.
    local manifest, missing = {}, {}
    for gid, state in global.pairs(objects) do
        local part = sync.LocalPart and sync.LocalPart(gid)
        if part then manifest[gid] = {part = part, rev = state.rev} else missing[gid] = true end
    end
    if players[sid] then players[sid].manifest, players[sid].missing = manifest, missing end
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
-- Ride snapshots (rides.lua): the file goes ahead of its line; a joiner gets the
-- files of the lines it missed while loading.
local rideWaiting = {}   -- host: file -> {sid, old, new} until the file is complete here

local function sendRideFiles(sid, lines)
    for _, line in global.ipairs(lines) do
        local file = global.string.match(line, "^Y|[^|]*|[^|]*|(pc2coop%-ride%-%d+%-%d+%.blueprint)$")
        if file then net.NetCommand("file|" .. sid .. "|" .. file .. "|" .. file) end
    end
end

local function catchUp(sid)
    local p = players[sid]
    local lines = {}
    if p.manifest then
        -- Objects in the transferred copy; everything after it is in pending (in order).
        for gid, m in global.pairs(p.manifest) do lines[#lines+1] = "A|" .. gid .. "|" .. m.part .. "|" .. m.rev end
        for gid in global.pairs(p.missing or {}) do
            if objects[gid] then lines[#lines+1] = upsertLine(gid) end
        end
    else
        for gid, state in global.pairs(objects) do
            local part = sync.LocalPart and sync.LocalPart(gid)
            if part then lines[#lines+1] = "A|" .. gid .. "|" .. part .. "|" .. state.rev
            else lines[#lines+1] = upsertLine(gid) end
        end
    end
    for _, line in global.ipairs(p.pending or {}) do lines[#lines+1] = line end
    p.pending, p.manifest, p.missing = nil, nil, nil
    sendRideFiles(sid, lines)
    sendOps(sid, lines)
    -- Ratings so far (quiet: no toast for old ones).
    for key, r in global.pairs(ratings) do
        for by, v in global.pairs(r.by) do
            send(sid, "rt|" .. by .. "|" .. key .. "|" .. v.stars .. "|" .. r.name .. "|" .. v.who .. "|" .. v.text .. "|0")
        end
    end
end

local function join(sid, name, mode)
    local returning = players[sid] ~= nil
    if not returning then order[#order+1] = sid end
    local color = returning and players[sid].color or departed[sid] or COLORS[(#order - 1) % #COLORS + 1]
    players[sid] = players[sid] or {}
    players[sid].name, players[sid].color = clean(name), color
    stats[players[sid].name] = stats[players[sid].name] or {created = 0, edited = 0, deleted = 0}
    if sid ~= me then send(sid, "welcome|" .. color) end
    for _, fr in global.ipairs(friends) do if fr.sid == sid then fr.invitedAt = nil end end
    if mode == "lobby" then
        players[sid].lobby = true
        if not returning then addFeed(players[sid].name .. " ist in der Lobby") end
        return
    end
    players[sid].lobby = nil
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
        net.NetCommand("del|pc2coop-host-" .. sid .. ".bin")
        net.NetCommand("del|pc2coop-host-" .. sid .. ".trn")
        departed[sid] = players[sid].color
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

local function forwardRide(sid, old, new, file)
    local out = others(sid, "Y|" .. old .. "|" .. new .. "|" .. file)
    if file ~= "-" then
        for _, d in global.ipairs(out) do
            local p = players[d[1]]
            if d[1] ~= me and p and not p.lobby and not p.pending then
                net.NetCommand("file|" .. d[1] .. "|" .. file .. "|" .. file)
            end
        end
    end
    deliver(out)
    if new == "-" then addFeed(nameOf(sid) .. " hat ein Fahrgeschaeft abgerissen")
    elseif old == "-" then addFeed(nameOf(sid) .. " hat eine Achterbahn gebaut")
    else addFeed(nameOf(sid) .. " hat eine Achterbahn geaendert") end
end

-- A change report, either from our own game or from a client.
local function hostChange(sid, f)
    if f[1] == "up" and #f >= 13 then
        local p, q, s = numbers(f, 6, 8), numbers(f, 9, 12), numbers(f, 13, 13)
        if p and q and s then deliver(authorityUp(sid, f[2], f[3], global.tonumber(f[4]), f[5], p, q, s[1], global.tonumber(f[14]))) end
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
                .. "|" .. num(pr.x or 0) .. "|" .. num(pr.y or 0) .. "|" .. num(pr.z or 0) .. "|" .. num(pr.yaw or 0)
                .. "|" .. num(pr.pitch or 0)
            for _, other in global.ipairs(order) do
                if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
            end
        end
    elseif f[1] == "ping" and players[sid] then
        local at = numbers(f, 2, 4)
        if at and (not lastPing[sid] or frames - lastPing[sid] >= 60) then
            lastPing[sid] = frames
            pings[sid] = {x = at[1], y = at[2], z = at[3], frame = frames}
            local line = "pg|" .. sid .. "|" .. num(at[1]) .. "|" .. num(at[2]) .. "|" .. num(at[3])
            for _, other in global.ipairs(order) do
                if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
            end
            if sid ~= me then toast(nameOf(sid) .. " zeigt auf etwas (oben rechts anklicken: folgen)", players[sid].color) end
        end
    elseif f[1] == "who" and players[sid] and validGid(f[2] or "") then
        local creator, last = authorOf(f[2])
        if sid == me then
            whoCache[f[2]] = {creator = creator or "", last = last or ""}
        else
            send(sid, "who|" .. f[2] .. "|" .. clean(creator or "") .. "|" .. clean(last or ""))
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
    elseif f[1] == "emote" and players[sid] and EMOTES[f[2] or ""] then
        if not lastEmote[sid] or frames - lastEmote[sid] >= 60 then
            lastEmote[sid] = frames
            emotes[sid] = {kind = f[2], frame = frames}
            local line = "em|" .. sid .. "|" .. f[2]
            for _, other in global.ipairs(order) do
                if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
            end
            toast(nameOf(sid) .. " " .. EMOTES[f[2]], players[sid].color)
        end
    elseif f[1] == "rate" and players[sid] and validRideKey(f[2]) then
        local stars = global.tonumber(f[3])
        if stars and stars >= 1 and stars <= 5 and stars == global.math.floor(stars) then
            local name, text, who = clean(f[4] or "?"), cleanText(f[5] or ""), nameOf(sid)
            ratings[f[2]] = ratings[f[2]] or {name = name, by = {}}
            ratings[f[2]].name = name
            ratings[f[2]].by[sid] = {stars = stars, text = text, who = who}
            local line = "rt|" .. sid .. "|" .. f[2] .. "|" .. stars .. "|" .. name .. "|" .. who .. "|" .. text .. "|1"
            for _, other in global.ipairs(order) do
                if other ~= me and players[other] and not players[other].pending then send(other, line) end
            end
            local said = who .. " bewertet " .. name .. " mit " .. stars .. "/5" .. (text ~= "" and (": " .. text) or "")
            addFeed(said)
        end
    elseif f[1] == "ride" and players[sid] then
        -- A ride (coaster) as a blueprint file: passed on once the file is complete here.
        local Rides = global.require("pc2coop.rides")
        local old, new, file = f[2] or "", f[3] or "", f[4] or ""
        if not (Rides.ValidKey(old) and Rides.ValidKey(new) and Rides.ValidFile(file)) then return end
        if (new == "-") ~= (file == "-") or (old == "-" and new == "-") then return end
        -- Someone else has this ride open in the track editor: theirs counts.
        if old ~= "-" and locks[old] and locks[old] ~= sid then
            emit("session:ride-refused|" .. old .. "|" .. nameOf(sid)); return
        end
        if sid == me or Rides.IsReady(file) then forwardRide(sid, old, new, file)
        else rideWaiting[file] = {sid, old, new} end
    elseif f[1] == "cmd" and f[2] then
        -- Replayed edit (terrain, lakes, ...): host orders it and forwards it to everyone else.
        -- A setter (park name, prices, open/close) goes back to its author too: applied once
        -- more in the host's order, everyone ends with the same value when two players set
        -- it at once. Additive calls (terrain brush, loans, research) are never repeated.
        if #f[2] <= 3000 then
            local method = global.string.match(f[2], "^![%w_]+%.([%w_]+)%(")
            local setter = method and (global.string.match(method, "^Set") or method == "OpenAttraction" or method == "CloseAttraction")
            if setter and sid ~= me then deliver(others(nil, "K|" .. f[2]))
            else deliver(others(sid, "K|" .. f[2])) end
        end
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
            if p.lobby then act = "lobby"
            elseif p.sending then act = "holt" .. global.math.floor((p.sent or 0) * 100)
            elseif p.pending then act = "laedt" end
            parts[#parts+1] = global.table.concat({sid, p.name, p.color, act, num(pr.x or 0), num(pr.y or 0),
                num(pr.z or 0), num(pr.yaw or 0), global.tostring(p.base or -1),
                num(pr.fx or pr.x or 0), num(pr.fy or pr.y or 0), num(pr.fz or pr.z or 0),
                global.tostring(p.dlc or ""), global.table.concat(p.mods or {}, "/")}, ",")
        end
    end
    local st = {}
    for name, v in global.pairs(stats) do st[#st+1] = name .. "," .. v.created .. "," .. v.edited .. "," .. v.deleted end
    local n = context == "park" and World.Numbers() or nil
    local numbersText = n and (global.tostring(n.guests or 0) .. "," .. global.tostring(global.math.floor(n.cash or 0)) .. ","
        .. (n.unlimited and "1" or "0")) or ""
    return "roster|" .. global.table.concat(parts, ";") .. "|" .. global.table.concat(st, ";") .. "|" .. conflicts
        .. "|" .. numbersText .. "|" .. global.tostring(stage) .. "," .. global.tostring(parkToken or "") .. ","
        .. (contentGuard and "1" or "0") .. "|" .. (choice and global.table.concat({choice.kind, choice.title, choice.detail,
        choice.starting and "1" or "0"}, ",") or "")
end

local function parseRoster(payload)
    local f = split(payload, "|")
    local list = {}
    for _, entry in global.ipairs(split(f[2] or "", ";")) do
        local p = split(entry, ",")
        list[#list+1] = {sid = p[1], name = p[2], color = p[3], act = p[4], x = global.tonumber(p[5]),
            y = global.tonumber(p[6]), z = global.tonumber(p[7]), yaw = global.tonumber(p[8]), base = global.tonumber(p[9]),
            fx = global.tonumber(p[10]), fy = global.tonumber(p[11]), fz = global.tonumber(p[12]),
            dlc = global.tonumber(p[13]), mods = modList(p[14])}
    end
    local st = {}
    for _, entry in global.ipairs(split(f[3] or "", ";")) do
        local p = split(entry, ",")
        st[p[1]] = {created = global.tonumber(p[2]), edited = global.tonumber(p[3]), deleted = global.tonumber(p[4])}
    end
    roster = {players = list, stats = st, conflicts = global.tonumber(f[4]) or 0}
    local n = split(f[5] or "", ",")
    park = n[1] and {guests = global.tonumber(n[1]) or 0, cash = global.tonumber(n[2]) or 0, unlimited = n[3] == "1"} or nil
    local ch = split(f[7] or "", ",")
    if role == "client" then
        choice = ch[1] and ch[1] ~= "" and {kind = ch[1], title = ch[2] or "", detail = ch[3] or "", starting = ch[4] == "1"} or nil
    end
    local st2 = split(f[6] or "", ",")
    if role == "client" and (st2[1] == "lobby" or st2[1] == "park") then
        contentGuard = st2[3] ~= "0"
        if st2[1] ~= stage or (st2[2] or "") ~= (parkToken or "") then
            stage, parkToken = st2[1], st2[2] ~= "" and st2[2] or nil
            Session._OnStage()
        end
    end
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
    if kind == "ridedel" then
        if global.string.match(rest, "^pc2coop%-ride%-%d+%-%d+%.blueprint$") then net.NetCommand("del|" .. rest) end
        return
    end
    if kind == "ride" and role == "client" and hostId then
        local file = global.string.match(rest, "|([^|]+)$")
        if file and file ~= "-" then net.NetCommand("file|" .. hostId .. "|" .. file .. "|" .. file) end
    end
    if kind ~= "up" and kind ~= "del" and kind ~= "pres" and kind ~= "baseline" and kind ~= "cmd" and kind ~= "hold"
        and kind ~= "ride" then return end
    local wire = (kind == "baseline" and "base" or kind) .. "|" .. rest
    if kind == "up" then
        local part, gid = global.string.match(rest, "^(%d+)|([^|]*)|")
        local need = gid == "" and World.RequiredDLC and World.RequiredDLC(global.tonumber(part)) or 0
        if need and need > 0 then wire = wire .. "|" .. global.math.floor(need) end
    end
    if role == "host" then hostChange(me, split(wire, "|"))
    elseif hostId then send(hostId, wire) end
end

local function onMessage(from, payload)
    local kind = global.string.match(payload, "^(%a+)")
    if role == "host" then
        if kind == "hello" then
            local f = split(payload, "|")
            local name, theirGame = clean(f[2] or "?"), clean(f[6] or "")
            if f[5] ~= Session.VERSION then
                local version = clean(f[5] or "alt")
                addFeed(name .. " hat PC2Coop " .. version .. ", du " .. Session.VERSION .. " - bitte beide UPDATE.cmd ausfuehren")
                send(from, "reject|" .. Session.VERSION .. "|" .. gameVersion)
                return
            end
            if gameVersion ~= "" and theirGame ~= "" and theirGame ~= gameVersion then
                addFeed(name .. " hat Spielversion " .. theirGame .. ", du " .. gameVersion .. " - bitte beide in Steam aktualisieren")
                send(from, "reject|" .. Session.VERSION .. "|" .. gameVersion)
                return
            end
            -- A Steam friend can enter a friends-only lobby without an invitation. The park
            -- is only handed to someone the host invited from here or lets in now.
            if not players[from] and askBeforeJoin and not invited[from] and not approved[from] then
                if not requests[from] then
                    toast(name .. " moechte beitreten. Im Multiplayer-Fenster zulassen oder ablehnen.", "fcc419")
                    emit("session:join-request|" .. from)
                end
                requests[from] = {name = name, mode = f[4], base = f[3], dlc = f[7], mods = f[8]}
                send(from, "wait|")
                return
            end
            Session._Admit(from, f[2], f[4], f[3], f[7], f[8])
        elseif players[from] and players[from].stale and kind ~= "hello" then
            -- Steam dropped what we sent this player while the connection hung: their park is
            -- incomplete. Now that they are back, they fetch it again.
            players[from].stale = nil
            send(from, "resync|")
            addFeed(players[from].name .. " war kurz weg - der Park wird neu uebertragen")
            hostChange(from, split(payload, "|"))
        elseif kind == "desync" and players[from] then
            addFeed(players[from].name .. " ist nicht mehr synchron")
        elseif kind == "loadfailed" and players[from] then
            players[from].sending = false
            addFeed(players[from].name .. " konnte den Park nicht laden")
        elseif kind == "chat" and players[from] then
            Session._BroadcastChat(players[from].name, players[from].color, global.string.sub(payload, 6))
        elseif kind == "info" and players[from] then
            local f = split(payload, "|")
            setContent(from, f[2], f[3] or "")
        elseif players[from] and stage == "park" and not players[from].lobby then
            hostChange(from, split(payload, "|"))
        end
    elseif from == hostId then
        lastHostFrame = frames
        if hostSilent then
            hostSilent = false
            toast("Verbindung zum Host wieder da.", "51cf66")
        end
        if selfStalled and kind ~= "resync" then
            -- What we sent while the connection hung is lost: start from the host's park again.
            selfStalled = false
            toast("Die Verbindung war unterbrochen - der Park des Hosts wird neu geladen.", "ff922b")
            Session.Resync()
            return
        end
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
            toast(global.string.sub(payload, 6), "fcc419", true)
        elseif kind == "p" then
            local f = split(payload, "|")
            for _, pl in global.ipairs(roster.players or {}) do
                if pl.sid == f[2] then
                    pl.fx, pl.fy, pl.fz, pl.act = global.tonumber(f[3]), global.tonumber(f[4]), global.tonumber(f[5]), f[6]
                    if f[11] then
                        pl.x, pl.y, pl.z = global.tonumber(f[7]), global.tonumber(f[8]), global.tonumber(f[9])
                        pl.yaw, pl.pitch = global.tonumber(f[10]), global.tonumber(f[11])
                    end
                end
            end
        elseif kind == "em" then
            local f = split(payload, "|")
            if EMOTES[f[3] or ""] then
                emotes[f[2]] = {kind = f[3], frame = frames}
                for _, pl in global.ipairs(roster.players or {}) do
                    if pl.sid == f[2] then toast(pl.name .. " " .. EMOTES[f[3]], pl.color) end
                end
            end
        elseif kind == "rt" then
            local f = split(payload, "|")
            local stars = global.tonumber(f[4])
            if validRideKey(f[3]) and stars and stars >= 1 and stars <= 5 then
                ratings[f[3]] = ratings[f[3]] or {name = clean(f[5]), by = {}}
                ratings[f[3]].name = clean(f[5])
                ratings[f[3]].by[f[2]] = {stars = stars, text = cleanText(f[7] or ""), who = clean(f[6])}
                if f[8] == "1" then
                    toast(clean(f[6]) .. " bewertet " .. clean(f[5]) .. " mit " .. stars .. "/5"
                        .. ((f[7] or "") ~= "" and (": " .. cleanText(f[7])) or ""))
                end
            end
        elseif kind == "pg" then
            local f = split(payload, "|")
            local x, y, z = global.tonumber(f[3]), global.tonumber(f[4]), global.tonumber(f[5])
            if x and y and z then
                pings[f[2]] = {x = x, y = y, z = z, frame = frames}
                for _, pl in global.ipairs(roster.players or {}) do
                    if pl.sid == f[2] then toast(pl.name .. " zeigt auf etwas (oben rechts anklicken: folgen)", pl.color) end
                end
            end
        elseif kind == "who" then
            local f = split(payload, "|")
            if f[2] then whoCache[f[2]] = {creator = f[3] or "", last = f[4] or ""} end
        elseif kind == "resync" then
            selfStalled = false
            toast("Die Verbindung war unterbrochen - der Park des Hosts wird neu geladen.", "ff922b")
            Session.Resync()
        elseif kind == "park" then
            local f = split(payload, "|")
            transfer.world, transfer.name = f[2], f[3]
            Session._TryLoad()
        elseif kind == "feed" then
            feed[#feed+1] = global.string.sub(payload, 6)
            while #feed > 30 do global.table.remove(feed, 1) end
            toast(feed[#feed])
        elseif kind == "reject" then
            local f = split(payload, "|")
            local hostVersion, hostGame = clean(f[2] or "?"), clean(f[3] or "?")
            emit("session:rejected-version|" .. hostVersion .. "|" .. hostGame)
            if hostVersion ~= Session.VERSION then
                Session._RefuseJoin("Der Host hat PC2Coop " .. hostVersion .. ", du " .. Session.VERSION
                    .. ". Bitte UPDATE.cmd ausfuehren (Spiel vorher beenden).")
            else
                Session._RefuseJoin("Der Host hat Spielversion " .. hostGame .. ", du " .. gameVersion
                    .. ". Bitte beide Planet Coaster 2 in Steam aktualisieren.")
            end
        elseif kind == "stage" then
            local f = split(payload, "|")
            if f[2] == "lobby" or f[2] == "park" then
                stage, parkToken, parkTitle, contentGuard = f[2], f[3] ~= "" and f[3] or nil, clean(f[4] or ""), f[5] ~= "0"
                Session._OnStage()
            end
        elseif kind == "content" then
            local f = split(payload, "|")
            Session._ContentRefused(global.tonumber(f[2]) or 0, clean(f[3] or ""))
        elseif kind == "wait" then
            waiting = true
        elseif kind == "welcome" then
            waiting = false
        elseif kind == "denied" then
            Session._RefuseJoin("Der Host hat deinen Beitritt abgelehnt.")
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
    remember("hostPark", parkToken or "")
    seenStage = "park|" .. global.tostring(parkToken)
    transfer, progress, joinFailure, desync = {}, {}, nil, nil
    emit("session:awaiting-park|" .. lobbyId .. "|" .. global.tostring(hostName))
    waiting = false
    send(hostId, helloLine("needpark"))
end

-- Joiner: in the host's lobby (main menu or a park of one's own), waiting for a park.
local function enterLobby()
    remember("lobby", lobbyId)
    remember("phase", "lobby")
    waiting = false
    emit("session:lobby|" .. lobbyId .. "|" .. global.tostring(hostName))
    send(hostId, helloLine("lobby"))
end

-- Joiner: the host opened a park (load it, unless it is the one loaded here) or went back
-- to the lobby.
function Session._OnStage()
    if role ~= "client" then return end
    local key = global.tostring(stage) .. "|" .. global.tostring(parkToken)
    if stage == "park" then
        local phase = memory.phase
        local have = memory.hostPark == (parkToken or "")
        if phase == "lobby" or not have then
            if seenStage == key and phase ~= "lobby" then return end
            if context == "park" and phase == "live" then toast("Der Host hat einen anderen Park geoeffnet - er wird geladen.", "fcc419") end
            requestPark()
        end
    elseif stage == "lobby" and seenStage ~= key then
        seenStage = key
        if context == "park" and memory.phase == "live" then
            toast("Der Host ist zurueck in der Lobby und waehlt einen Park. Geh ins Hauptmenue, um dabei zu bleiben.", "fcc419")
        elseif context == "menu" and memory.phase ~= "lobby" then
            remember("phase", "lobby")
        end
    end
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
        global.require("pc2coop.rides").SetTag(me)
        emit("session:net-ready|" .. me .. "|" .. myName)
    elseif kind == "lobby:entered" then
        -- Steam can report one entry twice; this module instance answers it once.
        if helloLobby == f[2] then return end
        lobbyId, hostId, helloLobby = f[2], f[3], f[2]
        joining, hostName = false, clean(f[4] or "")
        local phase = memory.lobby == lobbyId and memory.phase or nil
        if hostId ~= me and f[5] == "0" then
            Session._RefuseJoin("Der Host dieser Sitzung ist nicht in deiner Steam-Freundesliste. Beitritt abgebrochen.")
            return
        end
        if hostId == me then
            role = "host"
            local again = memory.lobby == lobbyId
            if again then
                for sid in global.string.gmatch(memory.admitted or "", "%d+") do approved[sid] = true end
                contentGuard = memory.guard ~= "0"
            end
            if context == "menu" then
                -- The lobby: everyone waits in the main menu until the host opens a park.
                stage, parkToken, parkTitle = "lobby", nil, ""
                if again then toast("Du bist wieder in der Lobby. Oeffne einen Park - alle laden ihn dann mit.", "fcc419") end
            else
                stage = "park"
                choice = nil
                if not parkToken then
                    parkToken = global.tostring((global.tonumber(memory.parks) or 0) + 1)
                    remember("parks", parkToken)
                end
                global.pcall(function()
                    local name = global.api.world.GetWorldAPIs().park:GetParkName()
                    parkTitle = clean(name)
                    authorsFile = "pc2coop-authors-" .. global.string.sub(global.string.gsub(global.tostring(name), "[^%w%-]", "_"), 1, 40) .. ".txt"
                    net.NetCommand("note-read|" .. authorsFile)
                end)
                sync.Receive("S|" .. myName)
            end
            join(me, myName)
            setContent(me, myDlc, myMods)
            remember("lobby", lobbyId)
            remember("phase", "host")
            emit("session:hosting|" .. lobbyId .. "|" .. stage)
            net.NetCommand("all|" .. stageLine())
        elseif context == "menu" and phase == "loading" then
            -- The game came back to the menu instead of opening the park.
            role = "client"
            failJoin("Der Park des Hosts konnte nicht geladen werden.", true)
        elseif context == "menu" and phase == "failed" then
            role = "client"
            joinFailure = joinFailure or "Der Park des Hosts konnte nicht geladen werden."
        elseif context == "menu" and (phase == "live" or phase == "lobby" or phase == "awaiting") then
            -- Back in the main menu: still in the host's lobby (leaving is a button).
            role = "client"
            if phase == "live" then toast("Du bist in der Lobby von " .. hostName .. ".", "fcc419") end
            enterLobby()
        elseif context == "park" and phase == "loading" then
            role = "client"
            remember("phase", "live")
            emit("session:joined|" .. lobbyId .. "|" .. hostName)
            sync.Receive("S|" .. myName)
            send(hostId, helloLine("loaded"))
            toast("Bereit: du baust jetzt im Park von " .. hostName .. ".", "51cf66")
            World.ApplyGuestProfile()
            net.NetCommand("del|pc2coop-join.bin")
            net.NetCommand("del|pc2coop-join.trn")
            net.NetCommand("note-write|" .. LAST_SESSION .. "|" .. lobbyId .. "|" .. hostId .. "|" .. hostName)
        elseif context == "park" and phase == "live" then
            role = "client"
            sync.Receive("S|" .. myName)
            send(hostId, helloLine("live"))
        else
            role = "client"
            if joinSource == "launch" then
                -- Nobody clicked an invitation: the lobby came with the start of the game.
                confirm = {host = hostName}
                emit("session:join-confirm|" .. lobbyId)
            else
                enterLobby()
            end
        end
        joinSource = nil
    elseif kind == "lobby:join-failed" then
        joining = false
        local code = global.tonumber(f[2]) or 0
        local reasons = {[2] = "Diese Einladung ist abgelaufen: die Sitzung gibt es nicht mehr. Lass dich neu einladen.",
            [4] = "Die Sitzung ist voll.", [6] = "Die Sitzung ist nur fuer Steam-Freunde des Hosts."}
        failJoin(reasons[code] or ("Beitritt nicht moeglich (Steam-Code " .. code .. "). Lass dich neu einladen."), false)
    elseif kind == "member:join" then
        emit("session:member|" .. f[2] .. "|" .. clean(f[3]))
    elseif kind == "member:leave" then
        requests[f[2]] = nil
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
        joinSource = f[4] == "launch" and "launch" or "invite"
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
            pc2 = f[5] == "1", invitedAt = invitedAt, lobby = global.string.match(f[6] or "", "^%d+$")}
    elseif kind == "friends:end" then
        -- Playing Planet Coaster 2 first, then online, then the rest; alphabetical within.
        global.table.sort(friendsLoading, function(a, b)
            local ra = a.pc2 and 0 or (a.state > 0 and 1 or 2)
            local rb = b.pc2 and 0 or (b.state > 0 and 1 or 2)
            if ra ~= rb then return ra < rb end
            return global.string.lower(a.name) < global.string.lower(b.name)
        end)
        friends = friendsLoading
    elseif kind == "avatar" then
        local data = f[3] or ""
        if f[2] and #data <= 16000 and not global.string.find(data, "[^%w%+/=]") then avatars[f[2]] = data end
    elseif kind == "mods" then
        Session._SetMods(global.table.concat(modList(f[2]), ";"))
    elseif kind == "invite:sent" then
        invited[f[2]] = true
        if role == "host" then persistAdmitted() end
        for _, fr in global.ipairs(friends) do
            if fr.sid == f[2] then fr.invitedAt = frames; toast("Einladung an " .. fr.name .. " gesendet") end
        end
    elseif kind == "invite:failed" then
        toast("Einladung konnte nicht gesendet werden")
    elseif kind == "kv" then
        memory[f[2]] = f[3]
    elseif kind == "file:progress" then
        progress[f[2]] = {global.tonumber(f[3]) or 0, global.tonumber(f[4]) or 1}
    elseif kind == "file:done" and global.string.match(f[3] or "", "^pc2coop%-ride%-%d+%-%d+%.blueprint$") then
        global.require("pc2coop.rides").FileReady(f[3])
        local waiting = rideWaiting[f[3]]
        if waiting and role == "host" then
            rideWaiting[f[3]] = nil
            forwardRide(waiting[1], waiting[2], waiting[3], f[3])
        end
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
    elseif kind == "note:data" then
        local name = f[2]
        if name then notes[name] = (notes[name] or "") .. global.string.sub(event, #f[1] + #name + 3) end
    elseif kind == "note:end" then
        local text = notes[f[2]] or ""
        notes[f[2]] = nil
        if f[2] == authorsFile then loadAuthors(text)
        elseif f[2] == LAST_SESSION then Session._LastSession(text) end
    elseif kind == "key:ping" then
        Session.Ping()
    elseif kind == "key:mdown" then
        middle = {frame = frames, camera = {World.Camera()}}
    elseif kind == "key:mup" then
        Session._MiddleUp(global.tonumber(f[2]) or 9999, global.tonumber(f[3]) or 9999)
    elseif kind == "net:peer-stalled" then
        if players[f[2]] then players[f[2]].sending, players[f[2]].stale = false, true end
        if role == "client" and f[2] == hostId then selfStalled = true end
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
    global.pcall(function() gameVersion = clean(global.api.game.GetVersionString()) end)
    if context == "park" then
        shared.onTime = function(paused, index) Session._LocalTime(paused, index) end
        shared.onNotification = function(text) Session._ParkNote(text) end
    end
    helloLobby = nil   -- a new menu or park: the DLL reports the lobby again
    emit("session:init|" .. global.tostring(net.NetStatus and net.NetStatus()))
    -- Module state was reset (new park); the DLL still knows lobby and phase.
    if Session.Available() then
        net.NetCommand("status")
        net.NetCommand("mods")
        if context == "menu" then net.NetCommand("note-read|" .. LAST_SESSION) end
    end
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
    if role or joining then return end
    objects, tombstones, stats, players, order, counter, conflicts = {}, {}, {}, {}, {}, 0, 0
    rejoin = nil
    net.NetCommand("host")
end

-- Host: lets a player in (invited, approved or known from earlier in this lobby).
function Session._Admit(sid, name, mode, base, dlc, mods)
    if stage ~= "park" then mode = "lobby" end
    join(sid, name, mode)
    setContent(sid, dlc, mods or "")
    if sid ~= me then
        approved[sid] = true
        persistAdmitted()
        if mode == "lobby" or mode == "live" or mode == "loaded" then send(sid, stageLine()) end
    end
    if base and mode ~= "lobby" then hostChange(sid, {"base", base}) end
end

-- Join the open lobby of a friend (shown in the friends list).
function Session.JoinFriend(sid)
    for _, fr in global.ipairs(friends) do
        if fr.sid == sid and fr.lobby then onNet("invite:accepted|" .. fr.lobby .. "|" .. sid .. "|click"); return end
    end
end

-- Content: owned DLC packs (from the UI) and other mods (from the DLL).
function Session.SetDlc(mask)
    mask = global.tonumber(mask)
    if not mask or mask == myDlc then return end
    myDlc = global.math.floor(mask)
    Session._ContentChanged()
end

function Session._SetMods(list)
    if list == myMods then return end
    myMods = list
    Session._ContentChanged()
end

function Session._ContentChanged()
    if role == "host" then setContent(me, myDlc, myMods)
    elseif role == "client" and hostId then send(hostId, "info|" .. global.tostring(myDlc or "") .. "|" .. myMods) end
end

function Session._ContentRefused(need, names)
    emit("session:content-refused|" .. global.tostring(need) .. "|" .. global.tostring(names))
    toast("Nicht gebaut: das Objekt ist aus einem DLC, das " .. names .. " nicht hat.", "ff922b")
end

-- Host: refuse (true) or allow objects from DLC packs not every player owns.
function Session.SetContentGuard(value)
    if role ~= "host" then return end
    contentGuard = value ~= false
    remember("guard", contentGuard and "1" or "0")
    net.NetCommand("all|" .. stageLine())
end

function Session.Stage() return stage, parkTitle end

-- A short click of the middle mouse button pings; holding it (camera turn) does not.
function Session._MiddleUp(ms, travel)
    local pressed = middle
    middle = nil
    if not pressed or ms > 350 or travel > 64 then return end
    local now = {World.Camera()}
    for i = 1, 5 do
        local a, b = pressed.camera[i], now[i]
        if a and b and global.math.abs(a - b) > 0.02 then return end
    end
    Session.Ping()
end

-- Lobby: the host picks where to play; everyone sees it before the park is opened.
-- kind: "save" (a saved park of the host), "new" (new sandbox park), "franchise".
function Session.SetChoice(kind, title, detail)
    if role ~= "host" or stage ~= "lobby" then return end
    if not kind then choice = nil; return end
    choice = {kind = clean(kind), title = clean(title or ""), detail = clean(detail or ""), starting = false}
end

function Session.MarkStarting()
    if choice then choice.starting = true end
end

function Session.Choice() return choice end

-- Profile pictures of the players in the session (asked from Steam once per player).
function Session.Avatars()
    for _, p in global.ipairs(Session.View().players or {}) do
        if p.sid and not avatarAsked[p.sid] and global.string.match(p.sid, "^%d+$") then
            avatarAsked[p.sid] = true
            net.NetCommand("avatar|" .. p.sid)
        end
    end
    return avatars
end

function Session.Invite() net.NetCommand("invite") end

-- Joiner progress for the UI: phase ("joining", "awaiting", "loading", "live"), share of the
-- park files received (0..1) and the host's name. Nil when not joining or in a session.
function Session.JoinState()
    local offer = Session._RejoinOffer()
    if offer then return {phase = "rejoin", host = offer.host} end
    if joinFailure then return {phase = "failed", reason = joinFailure, retry = role == "client" and hostId ~= nil, host = hostName} end
    if joining then return {phase = "joining", progress = 0} end
    if role ~= "client" then return nil end
    if confirm then return {phase = "confirm", host = confirm.host} end
    local got, total = 0, 0
    for _, p in global.pairs(progress) do got, total = got + p[1], total + p[2] end
    local phase = memory.phase or "awaiting"
    if waiting and (phase == "awaiting" or phase == "lobby") then phase = "asking" end
    if hostSilent and phase == "live" then return {phase = "silent", host = hostName} end
    if phase == "live" and stage == "lobby" then return {phase = "hostlobby", host = hostName} end
    return {phase = phase, progress = total > 0 and got / total or 0, host = hostName}
end

-- Joiner: the player agreed to join the lobby that came with the start of the game.
function Session.ConfirmJoin()
    if role ~= "client" or not confirm then return end
    confirm = nil
    requestPark()
end

-- Joiner: this session is not joined; says why (and leaves its lobby).
function Session._RefuseJoin(reason)
    Session.Leave()
    joinFailure = reason
    emit("session:join-refused|" .. reason)
end

-- Host: friends who ask to join without an invitation from here.
function Session.Requests()
    local list = {}
    for sid, request in global.pairs(requests) do list[#list+1] = {sid = sid, name = request.name} end
    global.table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Session.Answer(sid, allow)
    local request = requests[sid]
    if role ~= "host" or not request then return end
    requests[sid] = nil
    if allow then
        Session._Admit(sid, request.name, request.mode, request.base, request.dlc, request.mods)
    else
        send(sid, "denied|")
        addFeed(request.name .. " wurde nicht zugelassen")
    end
end

-- Host: false lets every Steam friend in without asking (the lobby is friends-only either way).
function Session.SetAskBeforeJoin(value) askBeforeJoin = value ~= false end

function Session.Desync() return desync end

-- "Here!": a marker at the ground under the cursor, for everyone in the session.
function Session.Ping()
    if not role then return end
    local x, y, z = World.CursorPoint()
    if not x then return end
    pings[me] = {x = x, y = y, z = z, frame = frames}
    local wire = "ping|" .. num(x) .. "|" .. num(y) .. "|" .. num(z)
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
end

-- Visitor mode: wave, cheer ... (EMOTES) for everyone.
function Session.Emote(kind)
    if not role or not EMOTES[kind or ""] then return false end
    local wire = "emote|" .. kind
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    if role ~= "host" then emotes[me] = {kind = kind, frame = frames} end
    return true
end

-- Visitor mode: 1-5 stars and a short suggestion for a ride (key: sync.RideKey).
function Session.Rate(key, stars, name, text)
    stars = global.tonumber(stars)
    if not role or not validRideKey(key) or not stars or stars < 1 or stars > 5 then return false end
    local wire = "rate|" .. key .. "|" .. global.math.floor(stars) .. "|" .. clean(name or "?") .. "|" .. cleanText(text)
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    return true
end

-- key -> {name, avg, count, mine, comments = {{who, stars, text}}}
function Session.Ratings()
    local out = {}
    for key, r in global.pairs(ratings) do
        local sum, n, comments, mine = 0, 0, {}, nil
        for by, v in global.pairs(r.by) do
            sum, n = sum + v.stars, n + 1
            if v.text ~= "" then comments[#comments+1] = {who = v.who, stars = v.stars, text = v.text} end
            if by == me then mine = v.stars end
        end
        out[key] = {name = r.name, avg = n > 0 and global.math.floor(sum / n * 10 + 0.5) / 10 or 0, count = n,
            mine = mine or false, comments = comments}
    end
    return out
end

-- sid -> what the player does right now (emotes of the last four seconds).
function Session.Emotes()
    local out = {}
    for sid, e in global.pairs(emotes) do
        if frames - e.frame < 240 then out[sid] = EMOTES[e.kind] else emotes[sid] = nil end
    end
    return out
end

-- Current pings: {sid, x, y, z, age (0..1)}.
function Session.Pings()
    local list = {}
    for sid, ping in global.pairs(pings) do
        local age = (frames - ping.frame) / PING_FRAMES
        if age >= 1 then pings[sid] = nil
        else list[#list+1] = {sid = sid, x = ping.x, y = ping.y, z = ping.z, age = age} end
    end
    return list
end

function Session.Notice(text, color) toast(text, color) end

-- Follow another player's camera; nil stops.
function Session.SetFollow(sid) following = sid end
function Session.Following() return following end

-- The object the local player selects or holds: its author is asked from the host once.
-- Returns {creator, last} when known.
function Session.Attribution(gid)
    if gid ~= watched then watched, watchedAt = gid, -1000 end
    if not gid or not role then return nil end
    if not whoCache[gid] and frames - watchedAt > 120 then
        watchedAt = frames
        if role == "host" then hostChange(me, {"who", gid}) else send(hostId, "who|" .. gid) end
    end
    return whoCache[gid]
end

-- Menu: the file from an earlier session (lobby|host sid|host name).
function Session._LastSession(text)
    local f = split(global.string.match(text or "", "^[^\n]*") or "", "|")
    if role or joining or not f[1] or not global.string.match(f[1], "^%w+$") then return end
    rejoin = {lobby = f[1], hostSid = f[2], host = clean(f[3] or "")}
    Session.RefreshFriends()
end

-- Menu: the host of that session is playing Planet Coaster 2 right now.
function Session._RejoinOffer()
    if not rejoin or role or joining or joinFailure then return nil end
    for _, fr in global.ipairs(friends) do
        if fr.sid == rejoin.hostSid and fr.pc2 then return rejoin end
    end
    return nil
end

function Session.Rejoin()
    local offer = Session._RejoinOffer()
    if not offer then return end
    rejoin = nil
    joining, progress, joinFailure, joinSource = true, {}, nil, "invite"
    net.NetCommand("join|" .. offer.lobby)
end

function Session.ForgetRejoin()
    rejoin = nil
    net.NetCommand("note-write|" .. LAST_SESSION .. "|")
end
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
    if role == "host" then
        for _, sid in global.ipairs(order) do
            if sid ~= me then
                net.NetCommand("del|pc2coop-host-" .. sid .. ".bin")
                net.NetCommand("del|pc2coop-host-" .. sid .. ".trn")
            end
        end
    end
    flushAuthors()
    joining, progress, desync, joinFailure, helloLobby = false, {}, nil, nil, nil
    invited, approved, requests, confirm, waiting, joinSource = {}, {}, {}, nil, false, nil
    pings, following, whoCache, hostSilent, selfStalled, authorsFile, dirtyAuthors = {}, nil, {}, false, false, nil, {}
    if role == "client" then net.NetCommand("note-write|" .. LAST_SESSION .. "|") end
    if role == "host" then remember("admitted", "") end
    stage, parkToken, parkTitle, seenStage, choice = nil, nil, "", nil, nil
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
                if p.lobby then act = "lobby"
                elseif p.sending then act = "holt" .. global.math.floor((p.sent or 0) * 100)
                elseif p.pending then act = "laedt" end
                list[#list+1] = {sid = sid, name = p.name, color = p.color, act = act, x = pr.x, y = pr.y, z = pr.z,
                    yaw = pr.yaw, pitch = pr.pitch, base = p.base, fx = pr.fx, fy = pr.fy, fz = pr.fz, hold = holds[sid],
                    dlc = p.dlc, mods = p.mods}
            end
        end
        return {role = role, me = me, host = me, lobby = lobbyId, players = list, stats = stats, conflicts = conflicts, feed = feed,
            park = context == "park" and World.Numbers() or nil, stage = stage, parkTitle = parkTitle, guard = contentGuard,
            context = context, dlc = myDlc, choice = choice}
    end
    for _, pl in global.ipairs(roster.players or {}) do pl.hold = holds[pl.sid] end
    return {role = role, me = me, host = hostId, lobby = lobbyId, players = roster.players or {}, stats = roster.stats or {},
        conflicts = roster.conflicts or 0, feed = feed, park = park, stage = stage, parkTitle = parkTitle, guard = contentGuard,
        context = context, dlc = myDlc, choice = choice}
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
    if role == "host" then
        flushActions(false)
        if frames % 300 == 0 then flushAuthors() end
    end
    if role == "client" and memory.phase == "live" and not hostSilent and lastHostFrame > 0 and frames - lastHostFrame > 600 then
        hostSilent = true
        toast("Keine Verbindung zum Host - warte ...", "ff922b")
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
