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
Session.VERSION = "2.1.0"
-- Errors with their stack, written sparingly (guard.lua); the last messages for a report.
Session._guard = global.require("pc2coop.guard")
Session._ring = {}
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
local typing = false      -- the chat input of the HUD is open: visitor key presses are text
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
-- Refused changes (TP-16): a short line at the object, {gid, text, color, fallback, frame, seen}.
-- When the object does not turn up in this game within MARK_FIND_FRAMES, a notice card says it.
local marks = {}
local MARK_FRAMES, MARK_FIND_FRAMES = 300, 30
local lastPing = {}       -- host: sid -> frame of their last ping (one per second at most)
-- Visitor mode (visitor.lua): emotes and ratings of rides, for everyone in the session.
local EMOTES = {wave = "winkt", cheer = "jubelt", laugh = "lacht", sick = "ist schlecht", up = "findet das super",
    down = "findet das nicht gut", eat = "isst", drink = "trinkt"}
local lastBuy = {}        -- host: sid -> frame of the last purchase (one per two seconds)
local emotes = {}         -- sid -> {kind, frame}
local okFigure, Figure = global.pcall(global.require, "pc2coop.figure")
if not okFigure then Figure = {ParseLook = function() return nil end, OwnLook = function() return nil end} end
local myLook = nil        -- figure.lua wire text of this player's look (Frontier avatar)
local lookFrame = -100000
local lastEmote = {}      -- host: sid -> frame of the last emote (one per second at most)
local ratings = {}        -- ride key -> {name, by = {sid -> {stars, text, who}}}
local lastUnsupported = -100000
local ratingsFile = nil   -- host: "pc2coop-ratings-<park>.txt", ratings kept between game starts
-- Team features (docs/KONZEPT.md): board, park events, session rules, last visit, checkpoints.
local Board = global.require("pc2coop.board")
local boardFile, visitsFile = nil, nil
local events = {}         -- park events with a place: {text, x, y, z, frame}
local EVENT_FRAMES = 7200 -- about two minutes
local rules = {speed = "all", visitors = "1", foreign = "free"}
local RULE_VALUES = {speed = {all = true, host = true}, visitors = {["1"] = true, ["0"] = true}, foreign = {free = true, ask = true}}
local lastVisit = {}      -- host: sid -> {cash, rides = {key = name}} when the player last left
local sinceText = nil     -- shown to this player: what changed since the last visit
local checkpoints = {}    -- host: {n, base, label, frame}
local vote = nil          -- {id, kind, arg, text, by, answers = {sid = true/false}}
local voteSerial = 0
local rideLister = nil    -- function() -> {key = name}; set for tests, else the visitor module
local invitation = nil    -- {by, key, name, frame}: someone invites everyone to a test ride
local pingContext = nil   -- {x, y, z, frame}: own ping just made; the panel offers actions for that spot
local CONTEXT_FRAMES = 600
local lastTakeAsk = {}    -- sid -> frame (host: one takeover question per player every 5 s)
local parkFrames = 0      -- frames in a park with a session (the first-use hint waits a bit)
-- Competition (docs/KONZEPT.md "Wettbewerb"): the host keeps it, the others get "cp" lines.
--   cp|<id>|<mode>|<phase build|rate|done>|<seconds left>|<topic>|<sid:name;...>|<sid:design10:tech10:count,...>
local COMP_MODES = {duel = "Bauduell", timer = "Koop gegen die Uhr"}
local comp = nil          -- host: {id, mode, phase, minutes, endMs, topic, entries, names, ratings, sent}
local compView = nil      -- others: the last cp line, read
local compMine = {}       -- sid -> {d, t}: what this player gave
local compSerial = 0
local nowMs = nil         -- real time from the DLL ("now" events)
local INVITE_RIDE_FRAMES = 3600
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

-- At most limit bytes, never through the middle of a UTF-8 letter (umlauts in names).
local function cut(text, limit)
    if #text <= limit then return text end
    local i = limit
    while i > 0 do
        local b = global.string.byte(text, i + 1) or 0
        if b < 128 or b >= 192 then break end
        i = i - 1
    end
    return global.string.sub(text, 1, i)
end

local function clean(name)
    name = global.string.gsub(global.tostring(name or "?"), "[|;,\n\r]", "")
    return cut(name, 32)
end

-- A short text a player typed (rating comment): no separators, at most 120 characters.
local function cleanText(text)
    text = global.string.gsub(global.tostring(text or ""), "[|\n\r]", " ")
    return cut(text, 120)
end

-- Someone would like to go on with what this player edits (FEAT-137): since the UX overhaul a
-- request card with "Verstanden" (TP-19), no toast. {by, label, frame}; module field, the main
-- chunk is at its limit of locals.
Session._takeAsk = nil
Session.TAKE_ASK_FRAMES = 1800
function Session._AskedToTake(name, label)
    Session._takeAsk = {by = name, label = label, frame = frames}
end

local function validRideKey(key) return global.string.match(key or "", "^F%-?%d+_%-?%d+_%-?%d+$") ~= nil and #key <= 40 end

local send

-- loc: the text is in the game's own notification format and is translated by the UI.
-- Only notifications of the host's park are; anything a player typed never is.
-- kind: "chat" (a message) and "event" (what a player did) go to the chat area bottom
-- left, everything else is a notice.
local function toast(text, color, loc, kind)
    toastId = toastId + 1
    toasts[#toasts+1] = {id = toastId, text = text, color = color, loc = loc == true, kind = kind or "notice"}
    while #toasts > 10 do global.table.remove(toasts, 1) end
end

-- The player another one's name stands for in a refusal; "host" marks a removal by the host.
local function someone(name)
    name = clean(name or "")
    if name == "" or name == "?" or name == "host" then return "Ein Mitspieler", false end
    return name, true
end

local function colorOfName(name)
    if role == "host" then
        for _, p in global.pairs(players) do if p.name == name then return p.color end end
    end
    for _, p in global.ipairs(roster.players or {}) do if p.name == name then return p.color end end
end

-- A change of the local player was refused or undone: say it at the object (TP-16).
local function markConflict(gid, text, color, fallback)
    if global.type(gid) ~= "string" or not global.string.match(gid, "^[%w_%.%-]+$") or #gid > 64 then
        toast(fallback, "ff922b")
        return
    end
    for i = #marks, 1, -1 do if marks[i].gid == gid then global.table.remove(marks, i) end end
    marks[#marks+1] = {gid = gid, text = text, color = color, fallback = fallback, frame = frames}
    while #marks > 4 do global.table.remove(marks, 1) end
end

-- Each frame: a mark whose object is not in this game in time becomes a notice card.
local function checkMarks()
    for i = #marks, 1, -1 do
        local m = marks[i]
        local age = frames - m.frame
        if not m.seen then
            local ok, entity = global.pcall(function() return sync.GidToEntity and sync.GidToEntity(m.gid) end)
            if ok and entity then m.seen = true end
        end
        if not m.seen and age >= MARK_FIND_FRAMES then
            toast(m.fallback, "ff922b")
            global.table.remove(marks, i)
        elseif age >= MARK_FRAMES then
            global.table.remove(marks, i)
        end
    end
end

local function addFeed(text)
    feed[#feed+1] = text
    while #feed > 30 do global.table.remove(feed, 1) end
    toast(text, nil, false, "event")
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
    Session._Remember(payload, true)
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
    -- The refusal names who changed the object last (shown at the object, TP-16).
    local out = {{sid, "R|" .. gid .. "|" .. reason .. (objects[gid] and ("|" .. clean(objects[gid].last)) or "")}}
    if objects[gid] then
        out[#out+1] = {sid, upsertLine(gid)}
        addFeed(nameOf(sid) .. ": Änderung verworfen, " .. objects[gid].last .. " war schneller")
    else
        out[#out+1] = {sid, "D|" .. gid .. "|host|0"}
    end
    return out
end

-- The object is being edited by someone else: the change is refused and the author's
-- game is put back to the shared state (from this host's world for untouched park objects).
local function refuseLocked(sid, gid)
    conflicts = conflicts + 1
    local out = {{sid, "R|" .. gid .. "|gesperrt|" .. clean(nameOf(locks[gid]))}}
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
    -- Session rule: others' builds are not torn down without asking.
    local o = objects[gid]
    if rules.foreign == "ask" and o and o.creator and o.creator ~= "Park" and o.creator ~= nameOf(sid) then
        if sid ~= me then send(sid, "ruledeny|Das hat " .. clean(o.creator) .. " gebaut - frag erst nach (Sitzungsregel).")
        else toast("Das hat " .. clean(o.creator) .. " gebaut - frag erst nach (Sitzungsregel).", "ff922b") end
        return restore(sid, gid, "fremd")
    end
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
    addFeed(nameOf(sid) .. " hat " .. res .. " gelöscht")
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
    Session._SendTeam(sid)
    local since = Session._Since(sid)
    if since then send(sid, "since|" .. since) end
end

-- Everything of the session besides the park itself, for a player who (re)loaded it: ratings
-- (quiet, no toast for old ones), board, rules, the game speed, a running competition and who
-- holds what. Sent after every load: the fuzz test (tests/test_fuzz_session_lua.py) found that
-- a second load in a row (resync twice, a hiccup) left the player without board and rules.
function Session._SendTeam(sid)
    for key, r in global.pairs(ratings) do
        for by, v in global.pairs(r.by) do
            send(sid, "rt|" .. by .. "|" .. key .. "|" .. v.stars .. "|" .. r.name .. "|" .. v.who .. "|" .. v.text .. "|0")
        end
    end
    for _, line in global.ipairs(Board.Lines()) do send(sid, line) end
    send(sid, "rules|" .. rules.speed .. "|" .. rules.visitors .. "|" .. rules.foreign)
    for holder, hold in global.pairs(holds) do
        if holder ~= sid then send(sid, "h|" .. holder .. "|" .. hold.label .. "|" .. hold.gids .. "|" .. hold.raw) end
    end
    local paused, index = World.Time()
    if paused ~= nil then send(sid, "time|" .. (paused and "1" or "0") .. "|" .. index .. "|") end
    if comp then send(sid, Session._CompLine()) end
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
        if not returning then addFeed(players[sid].name .. " ist der Sitzung beigetreten") end
        return
    end
    players[sid].lobby = nil
    if mode == "needpark" then
        -- Asked again while the park is still on its way: it arrives, nothing to restart -
        -- unless that transfer is stuck (no end after 30 s): then it starts anew.
        if players[sid].sending and frames - (players[sid].sendingSince or frames) < 1800 then return end
        players[sid].pending, players[sid].sending, players[sid].sent = {}, true, 0
        players[sid].sendingSince = frames
        addFeed(players[sid].name .. " tritt bei und lädt den Park")
        tasks[#tasks+1] = global.coroutine.create(function() sendPark(sid) end)
    elseif mode == "loaded" and players[sid].pending then
        addFeed(players[sid].name .. " ist beigetreten")
        catchUp(sid)
    else
        if not returning then addFeed(players[sid].name .. " ist beigetreten") end
        local snapshot = {}
        for gid in global.pairs(objects) do snapshot[#snapshot+1] = {sid, upsertLine(gid)} end
        deliver(snapshot)
        if sid ~= me then Session._SendTeam(sid) end
    end
end

local hostHold

local function leave(sid)
    if players[sid] then
        global.pcall(Session._RememberVisit, sid)
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
    local denied, deniedGid
    if label ~= "" then
        for gid in global.string.gmatch(gids or "", "[^,]+") do
            if validGid(gid) then
                if locks[gid] and locks[gid] ~= sid then denied, deniedGid = locks[gid], gid else locks[gid] = sid end
            end
        end
    end
    if denied then
        releaseLocks(sid)
        label, gids, items = "", "", ""
        if sid == me then Session._Denied(nameOf(denied), deniedGid)
        else send(sid, "deny|" .. clean(nameOf(denied)) .. "|" .. deniedGid) end
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
    return name .. " lässt das Spiel laufen (" .. (speeds[index] or "x1") .. ")"
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
    if new == "-" then addFeed(nameOf(sid) .. " hat ein Fahrgeschäft abgerissen")
    elseif old == "-" then addFeed(nameOf(sid) .. " hat eine Achterbahn gebaut")
    else addFeed(nameOf(sid) .. " hat eine Achterbahn geändert") end
end

-- A change report, either from our own game or from a client.
-- Host: at most `limit` messages of one kind per player within `window` frames (security
-- review 2026-11-21). Without it one player could flood everyone with chat, test ride
-- invitations or board changes, and fill the board and ratings files (2 MB each, then nothing
-- more is kept). The host itself is not limited. Module fields: the main chunk is at its limit.
Session._rates = {}
Session.RATE_LIMITS = {chat = {8, 300}, board = {20, 300}, ["ride-invite"] = {2, 600}, rate = {10, 600},
    time = {10, 300}, who = {30, 60}, ["take-ask"] = {6, 300}}
function Session._Allow(sid, kind)
    local rule = Session.RATE_LIMITS[kind]
    if not rule or sid == me then return true end
    local key = global.tostring(sid) .. "|" .. kind
    local entry = Session._rates[key]
    if not entry or frames - entry.start >= rule[2] then
        entry = {start = frames, count = 0}
        Session._rates[key] = entry
    end
    entry.count = entry.count + 1
    if entry.count == rule[1] + 1 then emit("session:rate-limited|" .. global.tostring(sid) .. "|" .. kind) end
    return entry.count <= rule[1]
end

-- A number from another player for a place or an angle: finite and within the world, else nil.
function Session._Finite(value)
    local n = global.tonumber(value)
    if not n or n ~= n or global.math.abs(n) > 1e6 then return nil end
    return n
end

local function hostChange(sid, f)
    if f[1] and not Session._Allow(sid, f[1]) then return end
    if f[1] == "up" and #f >= 13 then
        local p, q, s = numbers(f, 6, 8), numbers(f, 9, 12), numbers(f, 13, 13)
        if p and q and s then deliver(authorityUp(sid, f[2], f[3], global.tonumber(f[4]), f[5], p, q, s[1], global.tonumber(f[14]))) end
    elseif f[1] == "del" and #f >= 4 then
        deliver(authorityDelete(sid, f[2], f[3], global.tonumber(f[4])))
    elseif f[1] == "pres" and players[sid] then
        local F = Session._Finite
        local pr = {x = F(f[2]), y = F(f[3]), z = F(f[4]), yaw = F(f[5]), pitch = F(f[6]), act = clean(f[9]),
            fx = F(f[10]), fy = F(f[11]), fz = F(f[12])}
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
            local gid = Session._PingGid(f[5]) and f[5] or nil
            pings[sid] = {x = at[1], y = at[2], z = at[3], frame = frames, gid = gid}
            local line = "pg|" .. sid .. "|" .. num(at[1]) .. "|" .. num(at[2]) .. "|" .. num(at[3]) .. "|" .. (gid or "")
            for _, other in global.ipairs(order) do
                if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
            end
            if sid ~= me then toast(nameOf(sid) .. " zeigt auf etwas", players[sid].color, false, "event") end
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
    elseif f[1] == "time" and players[sid] and rules.speed == "host" and sid ~= me then
        -- Only the host sets the game speed: the player's game goes back to the host's.
        local hostPaused, hostIndex = World.Time()
        if hostPaused ~= nil then send(sid, "time|" .. (hostPaused and "1" or "0") .. "|" .. hostIndex .. "|") end
        send(sid, "ruledeny|Nur der Host ändert das Spieltempo (Sitzungsregel).")
    elseif f[1] == "time" and players[sid] then
        local paused, index = f[2] == "1", global.tonumber(f[3]) or 1
        if sid ~= me then World.SetTime(paused, index) end
        local line = "time|" .. (paused and "1" or "0") .. "|" .. index .. "|" .. nameOf(sid)
        for _, other in global.ipairs(order) do
            if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
        end
        addFeed(timeText(nameOf(sid), paused, index))
    elseif f[1] == "board" and players[sid] then
        -- add|kind|x|y|z|radius|title|text|assignee   set|id|field|value   del|id
        local changed, removed
        if f[2] == "add" then
            local item = Board.Make(f[3], f[4], f[5], f[6], f[7], f[8], f[9], nameOf(sid), f[10])
            if item then changed = Board.Add(item) end
        elseif f[2] == "set" and f[4] == "vote" then
            changed = Board.Set(f[3] or "", "vote", clean(nameOf(sid)) .. ":" .. (f[5] == "1" and "1" or "0"))
        elseif f[2] == "set" then
            changed = Board.Set(f[3] or "", f[4], f[5])
        elseif f[2] == "del" and Board.Get(f[3] or "") then
            removed = f[3]; Board.Remove(removed)
        end
        local line = changed and Board.Line(changed) or (removed and ("bd-|" .. removed))
        if line then
            for _, other in global.ipairs(order) do
                if other ~= me and players[other] and not players[other].pending then send(other, line) end
            end
            if boardFile then net.NetCommand("note-append|" .. boardFile .. "|" .. line .. "\n") end
            if changed and f[2] == "add" then addFeed(nameOf(sid) .. ": " .. Board.KINDS[changed.kind] .. " \"" .. changed.title .. "\"")
            elseif changed and f[3] and f[4] == "done" and changed.done then addFeed(nameOf(sid) .. " hat erledigt: " .. changed.title) end
        end
    elseif f[1] == "comp-rate" and players[sid] and comp and comp.phase == "rate" and f[2] == comp.id
        and comp.names[f[3] or ""] and f[3] ~= sid then
        local d, t = global.tonumber(f[4]), global.tonumber(f[5])
        if d and t and d >= 1 and d <= 5 and t >= 1 and t <= 5 then
            comp.ratings[sid] = comp.ratings[sid] or {}
            comp.ratings[sid][f[3]] = {d = global.math.floor(d), t = global.math.floor(t)}
            Session._CompCheck()
        end
    elseif f[1] == "take-ask" and players[sid] and players[f[2] or ""] and holds[f[2]] then
        -- Someone would like to go on with what another player is editing: the editor is asked.
        if not lastTakeAsk[sid] or frames - lastTakeAsk[sid] >= 300 then
            lastTakeAsk[sid] = frames
            if f[2] == me then Session._AskedToTake(nameOf(sid), holds[f[2]].label)
            else send(f[2], "tk|" .. clean(nameOf(sid)) .. "|" .. clean(holds[f[2]].label)) end
            addFeed(nameOf(sid) .. " fragt " .. nameOf(f[2]) .. " nach Übernahme")
        end
    elseif f[1] == "ride-invite" and players[sid] and validRideKey(f[2]) then
        local line = "iv|" .. clean(nameOf(sid)) .. "|" .. f[2] .. "|" .. clean(f[3] or "?")
        for _, other in global.ipairs(order) do
            if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
        end
        if sid ~= me then invitation = {by = nameOf(sid), key = f[2], name = clean(f[3] or "?"), frame = frames} end
        addFeed(nameOf(sid) .. " lädt zur Testfahrt auf " .. clean(f[3] or "?") .. " ein")
    elseif f[1] == "vote-answer" and players[sid] and vote and f[2] == vote.id then
        vote.answers[sid] = f[3] == "1"
        Session._VoteCheck()
    elseif f[1] == "buy" and players[sid] then
        Session._HostBuy(sid, f[2], global.tonumber(f[3]))
    elseif f[1] == "emote" and players[sid] and EMOTES[f[2] or ""] then
        if not lastEmote[sid] or frames - lastEmote[sid] >= 60 then
            lastEmote[sid] = frames
            emotes[sid] = {kind = f[2], frame = frames}
            local line = "em|" .. sid .. "|" .. f[2]
            for _, other in global.ipairs(order) do
                if other ~= me and other ~= sid and players[other] and not players[other].pending then send(other, line) end
            end
            toast(nameOf(sid) .. " " .. EMOTES[f[2]], players[sid].color, false, "event")
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
            if ratingsFile then
                net.NetCommand("note-append|" .. ratingsFile .. "|" .. global.table.concat({f[2], sid, stars, name, who, text}, "|") .. "\n")
            end
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
                global.tostring(p.dlc or ""), global.table.concat(p.mods or {}, "/"), p.look or ""}, ",")
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
            dlc = global.tonumber(p[13]), mods = modList(p[14]), look = Figure.ParseLook(p[15]) and p[15] or nil}
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
        if first and role ~= "client" then toast("Eine Änderung konnte hier nicht übernommen werden.", "ff922b") end
        if role == "client" and hostId then send(hostId, "desync|" .. global.string.sub(clean(desync), 1, 120)) end
        return
    end
    if kind == "hold-denied" then
        local f = split(rest, "|")
        Session._Denied(f[1], f[2])
        return
    end
    if kind == "hold-lost" then
        -- hold-lost|<who changed it>|<gid>
        local f = split(rest, "|")
        local who, named = someone(f[1])
        markConflict(f[2], who .. " hat das gerade geändert", named and colorOfName(who) or nil,
            who .. " hat das Objekt geändert, das du gerade bearbeitet hast.")
        return
    end
    if kind == "undo-blocked" then
        toast("Rückgängig geht nur für deinen eigenen letzten Schritt - der neueste hier stammt von einem Mitspieler.", "ff922b")
        return
    end
    if kind == "rejected" then
        -- rejected|<gid>|<reason>|<who was in the way>: the object is put back, the line says why.
        local f = split(rest, "|")
        local reason = f[2] or ""
        local who, named = someone(f[3])
        local color = named and colorOfName(who) or nil
        if reason == "gesperrt" then
            markConflict(f[1], who .. " baut hier gerade", color, "Zurückgenommen: " .. who .. " baut hier gerade.")
        elseif reason == "veraltet" then
            markConflict(f[1], who .. " war schneller", color, "Zurückgenommen: " .. who .. " war bei diesem Objekt schneller.")
        end
        return
    end
    if kind == "unsupported" then
        if frames - lastUnsupported > 600 then
            lastUnsupported = frames
            toast("„" .. clean(rest) .. "“ wird noch nicht an die anderen übertragen.", "ff922b")
        end
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
                addFeed(name .. " hat PC2Coop " .. version .. ", du " .. Session.VERSION .. ". Ihr braucht dieselbe Version: PC2Coop-Setup → „Nach Update suchen“.")
                send(from, "reject|" .. Session.VERSION .. "|" .. gameVersion)
                return
            end
            if gameVersion ~= "" and theirGame ~= "" and theirGame ~= gameVersion then
                addFeed(name .. " hat Spielversion " .. theirGame .. ", du " .. gameVersion .. ". Beide aktualisieren das Spiel in Steam.")
                send(from, "reject|" .. Session.VERSION .. "|" .. gameVersion)
                return
            end
            -- A Steam friend can enter a friends-only lobby without an invitation. The park
            -- is only handed to someone the host invited from here or lets in now.
            if not players[from] and askBeforeJoin and not invited[from] and not approved[from] then
                if not requests[from] then
                    toast(name .. " möchte beitreten.", "fcc419")
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
            addFeed(players[from].name .. " war kurz weg - der Park wird neu übertragen")
            hostChange(from, split(payload, "|"))
        elseif kind == "desync" and players[from] then
            addFeed(players[from].name .. " ist nicht mehr synchron")
        elseif kind == "loadfailed" and players[from] then
            players[from].sending = false
            addFeed(players[from].name .. " konnte den Park nicht laden")
        elseif kind == "chat" and players[from] then
            if Session._Allow(from, "chat") then
                Session._BroadcastChat(players[from].name, players[from].color, global.string.sub(payload, 6))
            end
        elseif kind == "info" and players[from] then
            local f = split(payload, "|")
            setContent(from, f[2], f[3] or "")
        elseif kind == "look" and players[from] then
            -- The player's visitor figure (figure.lua); in the lobby too, so it is there in the park.
            local f = split(payload, "|")
            if Figure.ParseLook(f[2]) then players[from].look = f[2] end
        elseif players[from] and stage == "park" and not players[from].lobby then
            hostChange(from, split(payload, "|"))
        end
    elseif from == hostId then
        lastHostFrame = frames
        -- The connection pill turns green for a moment (CoopLayer.js); no toast.
        if hostSilent then hostSilent = false end
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
            local f = split(payload, "|")
            Session._Denied(f[2], f[3])
        elseif kind == "time" then
            local f = split(payload, "|")
            local paused, index = f[2] == "1", global.tonumber(f[3]) or 1
            World.SetTime(paused, index)
            if f[4] and f[4] ~= "" then toast(timeText(clean(f[4]), paused, index)) end
        elseif kind == "note" then
            -- note|x|y|z|text: a park event of the host with the place it happened
            local x, y, z, text = global.string.match(payload, "^note|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            text = text or global.string.sub(payload, 6)
            toast(text, "fcc419", true)
            if global.tonumber(x) and global.tonumber(z) then
                events[#events+1] = {text = text, x = global.tonumber(x), y = global.tonumber(y) or 0, z = global.tonumber(z), frame = frames}
                while #events > 20 do global.table.remove(events, 1) end
            end
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
                    if pl.sid == f[2] and f[4] ~= "q" then toast(pl.name .. " " .. EMOTES[f[3]], pl.color, false, "event") end
                end
            end
        elseif kind == "sold" then
            local f = split(payload, "|")
            if f[2] == "ok" then
                emotes[me] = (f[3] == "eat" or f[3] == "drink") and {kind = f[3], frame = frames} or emotes[me]
                global.pcall(function() global.require("pc2coop.visitor").Ate(f[3]) end)
            else
                toast(cleanText(f[3] or "Kaufen geht gerade nicht"), "ff922b")
            end
        elseif kind == "bd" or kind == "bd-" then
            Board.Apply(payload)
        elseif kind == "rules" then
            local f = split(payload, "|")
            if RULE_VALUES.speed[f[2] or ""] then rules.speed = f[2] end
            if RULE_VALUES.visitors[f[3] or ""] then rules.visitors = f[3] end
            if RULE_VALUES.foreign[f[4] or ""] then rules.foreign = f[4] end
        elseif kind == "cp" then
            Session._CompRead(payload)
        elseif kind == "tk" then
            local f = split(payload, "|")
            Session._AskedToTake(clean(f[2] or "?"), clean(f[3] or "?"))
        elseif kind == "iv" then
            local f = split(payload, "|")
            if validRideKey(f[3]) then invitation = {by = clean(f[2]), key = f[3], name = clean(f[4] or "?"), frame = frames} end
        elseif kind == "since" then
            sinceText = global.string.sub(global.string.gsub(global.string.sub(payload, 7), "[\n\r]", " "), 1, 600)
            Session._ShowSince()
        elseif kind == "ruledeny" then
            toast(global.string.sub(global.string.gsub(global.string.sub(payload, 10), "[\n\r]", " "), 1, 160), "ff922b")
        elseif kind == "vote" then
            local f = split(payload, "|")
            if f[2] == "-" then vote = nil
            else vote = {id = f[2], kind = clean(f[3]), arg = clean(f[4]), text = global.string.sub(f[5] or "", 1, 160), by = clean(f[6]), answers = {}} end
        elseif kind == "rt" then
            local f = split(payload, "|")
            local stars = global.tonumber(f[4])
            if validRideKey(f[3]) and stars and stars >= 1 and stars <= 5 then
                ratings[f[3]] = ratings[f[3]] or {name = clean(f[5]), by = {}}
                ratings[f[3]].name = clean(f[5])
                ratings[f[3]].by[f[2]] = {stars = stars, text = cleanText(f[7] or ""), who = clean(f[6])}
                if f[8] == "1" then
                    toast(clean(f[6]) .. " bewertet " .. clean(f[5]) .. " mit " .. stars .. "/5"
                        .. ((f[7] or "") ~= "" and (": " .. cleanText(f[7])) or ""), nil, false, "event")
                end
            end
        elseif kind == "pg" then
            local f = split(payload, "|")
            local at = numbers(f, 3, 5)
            if at then
                pings[f[2]] = {x = at[1], y = at[2], z = at[3], frame = frames, gid = Session._PingGid(f[6]) and f[6] or nil}
                for _, pl in global.ipairs(roster.players or {}) do
                    if pl.sid == f[2] then toast(pl.name .. " zeigt auf etwas", pl.color, false, "event") end
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
            Session._ParkProgress()
            Session._TryLoad()
        elseif kind == "feed" then
            feed[#feed+1] = global.string.sub(payload, 6)
            while #feed > 30 do global.table.remove(feed, 1) end
            toast(feed[#feed], nil, false, "event")
        elseif kind == "reject" then
            local f = split(payload, "|")
            local hostVersion, hostGame = clean(f[2] or "?"), clean(f[3] or "?")
            emit("session:rejected-version|" .. hostVersion .. "|" .. hostGame)
            if hostVersion ~= Session.VERSION then
                Session._RefuseJoin("Der Host hat PC2Coop " .. hostVersion .. ", du " .. Session.VERSION
                    .. ". Ihr braucht dieselbe Version: Spiel beenden, PC2Coop-Setup → „Nach Update suchen“.")
            else
                Session._RefuseJoin("Der Host hat Spielversion " .. hostGame .. ", du " .. gameVersion
                    .. ". Aktualisiert beide Planet Coaster 2 in Steam.")
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
    Session._parkProgressFrame = frames
    send(hostId, helloLine("needpark"))
end

-- Joiner: a park that does not come (its transfer was lost on the way) is asked for again
-- after 20 s without any progress, three times; then the join fails with "Erneut versuchen".
-- The fuzz test (tests/test_fuzz_session_lua.py) found players waiting for it for ever.
Session.PARK_RETRY_FRAMES, Session.PARK_RETRIES = 1200, 3
function Session._ParkProgress() Session._parkProgressFrame = frames end
function Session._CheckParkArrives()
    if role ~= "client" or memory.phase ~= "awaiting" or waiting or not hostId then
        Session._parkRetries = 0
        return
    end
    if frames - (Session._parkProgressFrame or frames) < Session.PARK_RETRY_FRAMES then return end
    if (Session._parkRetries or 0) < Session.PARK_RETRIES then
        Session._parkRetries = (Session._parkRetries or 0) + 1
        emit("session:park-retry|" .. Session._parkRetries)
        requestPark()
    else
        Session._parkRetries = 0
        Session._FailJoin("Der Park des Hosts ist nicht angekommen. Versuch es noch einmal.", false)
    end
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
            if context == "park" and phase == "live" then toast("Der Host hat einen anderen Park geöffnet - er wird geladen.", "fcc419") end
            requestPark()
        end
    elseif stage == "lobby" and seenStage ~= key then
        seenStage = key
        if context == "park" and memory.phase == "live" then
            emit("session:host-in-menu")   -- the dialog with "Ins Hauptmenü" (JoinState "hostlobby")
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
Session._FailJoin = failJoin

local function onNet(event)
    local f = split(event, "|")
    local kind = f[1]
    if kind == "net:ready" then
        me, myName = f[2], clean(f[3])
        global.require("pc2coop.rides").SetTag(me)
        emit("session:net-ready|" .. me .. "|" .. myName)
    elseif kind == "report:done" or kind == "report:error" then
        Session._ReportResult(kind, f[2])
    elseif kind == "lobby:entered" then
        -- Steam can report one entry twice; this module instance answers it once.
        if helloLobby == f[2] then return end
        if Session._dropLobby == f[2] then
            net.NetCommand("leave")
            emit("session:join-cancelled|" .. f[2])
            return
        end
        lobbyId, hostId, helloLobby = f[2], f[3], f[2]
        -- The same short code in the host's and the guests' logs: their reports fit together.
        Session._code = Session._Code(lobbyId)
        emit("session:code|" .. Session._code)
        joining, hostName, Session._ended, Session._starting = false, clean(f[4] or ""), nil, nil
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
                if again then toast("Deine Sitzung läuft weiter. Öffne einen Park - alle laden ihn dann mit.", "fcc419") end
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
                    ratingsFile = "pc2coop-ratings-" .. global.string.sub(global.string.gsub(global.tostring(name), "[^%w%-]", "_"), 1, 40) .. ".txt"
                    net.NetCommand("note-read|" .. ratingsFile)
                    local base = global.string.sub(global.string.gsub(global.tostring(name), "[^%w%-]", "_"), 1, 40)
                    boardFile, visitsFile = "pc2coop-board-" .. base .. ".txt", "pc2coop-visits-" .. base .. ".txt"
                    Board.Reset()
                    net.NetCommand("note-read|" .. boardFile)
                    net.NetCommand("note-read|" .. visitsFile)
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
            if phase == "live" then toast("Du bist weiter in der Sitzung von " .. hostName .. ". Der Host wählt einen Park.", "fcc419") end
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
        local reasons = {[2] = "Diese Einladung ist abgelaufen, die Sitzung gibt es nicht mehr. Lass dich neu einladen.",
            [4] = "Die Sitzung ist voll.", [6] = "Die Sitzung ist nur für Steam-Freunde des Hosts."}
        failJoin(reasons[code] or ("Beitritt nicht möglich (Steam-Code " .. code .. "). Lass dich neu einladen."), false)
    elseif kind == "member:join" then
        emit("session:member|" .. f[2] .. "|" .. clean(f[3]))
    elseif kind == "member:leave" then
        requests[f[2]] = nil
        if role == "host" then leave(f[2]) end
        if f[2] == hostId and role == "client" then
            local name = hostName
            addFeed("Host hat die Sitzung beendet")
            Session.Leave()
            Session._ended = {host = name}   -- a field: the main chunk is at Lua's 200 locals
            emit("session:host-gone|" .. global.tostring(name))
            global.pcall(function()
                local Visitor = global.require("pc2coop.visitor")
                if Visitor.Active() then Visitor.Stop() end
            end)
        end
    elseif kind == "msg" then
        onMessage(f[2], global.string.sub(event, #f[1] + #f[2] + 3))
    elseif kind == "invite:accepted" then
        if role and lobbyId == f[2] then
            toast("Du bist bereits in dieser Sitzung.")
            return
        end
        if role then Session.Leave() end
        joining, progress, joinFailure, Session._ended = true, {}, nil, nil
        Session._joinLobby, Session._dropLobby = f[2], nil
        joinSource = f[4] == "launch" and "launch" or "invite"
        net.NetCommand("join|" .. f[2])
        emit("session:joining|" .. f[2])
    elseif kind == "key:menu" then
        if Session.OnMenuKey then Session.OnMenuKey() end
    elseif kind == "key:dev" then
        if Session.OnDevKey then Session.OnDevKey() end
    elseif kind == "key:chat" then
        -- Enter: the UI opens the chat input when it fits (in a park, no text field of the game).
        if Session.OnChatKey then Session.OnChatKey() end
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
    elseif kind == "now" then
        nowMs = global.tonumber(f[2])
        Session._CompClock()
    elseif kind == "kv" then
        memory[f[2]] = f[3]
        if f[2] == "rules" and f[3] then
            local speed, visitors, foreign = global.string.match(f[3], "^(%a+),(%d),(%a+)$")
            if speed and RULE_VALUES.speed[speed] then rules.speed = speed end
            if visitors and RULE_VALUES.visitors[visitors] then rules.visitors = visitors end
            if foreign and RULE_VALUES.foreign[foreign] then rules.foreign = foreign end
        end
    elseif kind == "file:progress" then
        progress[f[2]] = {global.tonumber(f[3]) or 0, global.tonumber(f[4]) or 1}
        Session._ParkProgress()
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
        Session._ParkProgress()
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
        elseif boardFile and f[2] == boardFile then
            for line in global.string.gmatch(text, "[^\n]+") do Board.Apply(line) end
        elseif visitsFile and f[2] == visitsFile then
            -- "sid|cash|key:name,key:name" lines, later lines win.
            for line in global.string.gmatch(text, "[^\n]+") do
                local v = split(line, "|")
                if v[1] and global.string.match(v[1], "^%d+$") then
                    local seen = {}
                    for entry in global.string.gmatch(v[3] or "", "[^,]+") do
                        local key, name = global.string.match(entry, "^([^:]+):(.*)$")
                        if key then seen[key] = name end
                    end
                    lastVisit[v[1]] = {cash = global.tonumber(v[2]), rides = seen}
                end
            end
            if me and lastVisit[me] then sinceText = Session._Since(me); Session._ShowSince() end
        elseif ratingsFile and f[2] == ratingsFile then
            -- "key|sid|stars|ride|who|text" lines, later lines win.
            for line in global.string.gmatch(text, "[^\n]+") do
                local r = split(line, "|")
                local stars = global.tonumber(r[3])
                if validRideKey(r[1]) and r[2] and stars and stars >= 1 and stars <= 5 then
                    ratings[r[1]] = ratings[r[1]] or {name = clean(r[4]), by = {}}
                    ratings[r[1]].by[r[2]] = {stars = stars, who = clean(r[5]), text = cleanText(r[6] or "")}
                end
            end
        elseif f[2] == LAST_SESSION then Session._LastSession(text) end
    elseif kind == "key:ping" then
        Session.Ping()
    elseif kind == "key:mdown" then
        middle = {frame = frames, camera = {World.Camera()}}
    elseif kind == "key:mup" then
        Session._MiddleUp(global.tonumber(f[2]) or 9999, global.tonumber(f[3]) or 9999)
    elseif kind == "key:v" and typing and f[3] == "1" then
        -- The chat input is open: T, E, V and 1-6 are letters there. Releases still go through.
    elseif kind == "key:v" then
        -- Visitor mode keys (DLL, only while it is on): Tab, T, E, V, F, 1-6.
        local Visitor = global.require("pc2coop.visitor")
        local todo, number = Visitor.OnKey(f[2], f[3] == "1")
        if todo == "stop" then Visitor.Stop()
        elseif todo == "interact" then
            local ok, failure = Visitor.Interact(sync.RideKey, sync.GidToEntity)
            if not ok then toast("E: " .. global.tostring(failure) .. ".", "ff922b") end
        elseif todo == "view" then
            Visitor.ToggleView()
        elseif todo == "list" then
            Visitor.SetList(not Visitor.ListOpen())
        elseif todo == "buy" then
            Session.BuyPick(number)
        end
    elseif kind == "mouse" then
        global.require("pc2coop.visitor").OnMouse(global.tonumber(f[2]) or 0, global.tonumber(f[3]) or 0)
    elseif kind == "net:peer-stalled" then
        if players[f[2]] then players[f[2]].sending, players[f[2]].stale = false, true end
        if role == "client" and f[2] == hostId then selfStalled = true end
        -- Steam accepted nothing for this player for a minute: the data for them is gone.
        local who = players[f[2]] and players[f[2]].name or "Ein Mitspieler"
        addFeed("Die Verbindung zu " .. who .. " hängt. Tritt neu bei.")
        emit("session:peer-stalled|" .. f[2] .. "|" .. global.tostring(f[3]))
    elseif kind == "net:error" then
        Session._netError = f[2] or "?"   -- the DLL could not bind Steam: multiplayer stays off
        emit("session:" .. event)
    elseif kind == "lobby:error" then
        emit("session:" .. event)
        if f[2] == "create-failed" and Session._starting then
            Session._starting = nil
            failJoin("Die Sitzung konnte nicht erstellt werden (Steam-Code " .. global.tostring(f[3] or "?") .. ").", false)
        end
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
    Session._guard.Init(function(line) emit(line) end, function() Session._DumpRing("first-error") end)
    global.pcall(function() gameVersion = clean(global.api.game.GetVersionString()) end)
    if context == "park" then
        shared.onTime = function(paused, index) Session._LocalTime(paused, index) end
        shared.onNotification = function(text, entity) Session._ParkNote(text, entity) end
    end
    helloLobby = nil   -- a new menu or park: the DLL reports the lobby again
    global.pcall(function()
        global.require("pc2coop.visitor").Init(function(command) net.NetCommand(command) end,
            function(kind) Session.Emote(kind) end)
    end)
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
        failJoin("Die übertragene Park-Datei ist ungültig (" .. global.tostring(failure) .. ").", true)
    end
end

function Session.Available() return net and net.HasNet() and not Session._netError end

-- Why the multiplayer is off (UX_OVERHAUL.md §5 "Steam fehlt"): "dll" when the mod's DLL did not
-- load, "steam" when the DLL could not bind Steam's interfaces; nil when all is well. Both are
-- final for this game start (the DLL loads and binds once), so the UI offers no retry.
function Session.NetProblem()
    if Session._netError then return "steam" end
    if not (net and net.HasNet()) then return "dll" end
    return nil
end

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
function Session.SetTyping(on) typing = on == true end
function Session.Typing() return typing end
function Session.Toasts() return toasts end
function Session.RefreshFriends() net.NetCommand("friends") end
function Session.InviteFriend(sid)
    if global.type(sid) == "string" and global.string.match(sid, "^%d+$") then net.NetCommand("invite_user|" .. sid) end
end

function Session._AddChat(name, color, text)
    chat[#chat+1] = {name = clean(name), color = color, text = global.string.sub(global.tostring(text), 1, 200)}
    while #chat > 40 do global.table.remove(chat, 1) end
    toast(clean(name) .. ": " .. chat[#chat].text, color, false, "chat")
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
    Session._ended = nil
    objects, tombstones, stats, players, order, counter, conflicts = {}, {}, {}, {}, {}, 0, 0
    rejoin = nil
    Session._starting, Session._dropLobby = frames, nil
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
    if Session.Ping() and pings[me] then
        pingContext = {x = pings[me].x, y = pings[me].y, z = pings[me].z, frame = frames}
    end
end

-- Actions for the spot of the own last ping (shown next to the cursor for a few seconds).
function Session.Context()
    if pingContext and (not role or frames - pingContext.frame > CONTEXT_FRAMES) then pingContext = nil end
    return pingContext
end

function Session.CloseContext() pingContext = nil end

-- Ask the player who edits something to hand it over when done.
function Session.AskTakeover(sid)
    if not role or not sid then return false end
    local wire = "take-ask|" .. clean(sid)
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    return true
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
    if Session._starting and not role then return {phase = "starting"} end
    if Session._ended and not role then return {phase = "ended", host = Session._ended.host} end
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
    -- On an object: its shared id goes along, so everyone sees that object outlined (P6 A9).
    local gid = ""
    if sync.PartOnRay and World.CursorRay then
        local ok, found = global.pcall(function() return sync.PartOnRay(World.CursorRay()) end)
        if ok and Session._PingGid(found) then gid = found end
    end
    pings[me] = {x = x, y = y, z = z, frame = frames, gid = gid ~= "" and gid or nil}
    local wire = "ping|" .. num(x) .. "|" .. num(y) .. "|" .. num(z) .. "|" .. gid
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    return true
end

-- A shared id a mark may carry: a scenery part, never a ride (F/S) or anything odd.
function Session._PingGid(gid)
    return global.type(gid) == "string" and gid ~= "" and #gid <= 64 and global.string.match(gid, "^[%w_%.%-]+$") ~= nil
        and not global.string.match(gid, "^[FS]")
end

-- Visitor mode: wave, cheer ... (EMOTES) for everyone.
function Session.Emote(kind)
    if not role or not EMOTES[kind or ""] then return false end
    local wire = "emote|" .. kind
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    if role ~= "host" then emotes[me] = {kind = kind, frame = frames} end
    return true
end

-- Visitor mode: buying at a shop (shop.lua). The host checks the shop and the item, books
-- the price into the park's cash like a shop sale, tells everyone and the figure eats or
-- drinks. Without a session the player is the park: the same, locally.
function Session._HostBuy(sid, gid, index, entity)
    local Shop = global.require("pc2coop.shop")
    local function refuse(text)
        if sid == me then toast(text, "ff922b") else send(sid, "sold|no|" .. text) end
    end
    if lastBuy[sid] and frames - lastBuy[sid] < 120 then return end
    entity = entity or (gid and sync.GidToEntity(gid))
    if not entity then refuse("Diesen Shop gibt es beim Host nicht"); return end
    local item
    for _, it in global.ipairs(Shop.Items(entity)) do if it.index == index then item = it end end
    if not item then refuse("Das gibt es dort nicht mehr"); return end
    if not Shop.IsOpen(entity) then refuse("Der Shop ist geschlossen"); return end
    lastBuy[sid] = frames
    tasks[#tasks+1] = global.coroutine.create(function() Shop.Credit(item.cost, item.item) end)
    local who = role and nameOf(sid) or myName or "Du"
    if role then addFeed(who .. " kauft " .. Shop.Readable(item.item) .. " (" .. Shop.Price(item.cost) .. ")")
    else toast("Gekauft: " .. Shop.Readable(item.item) .. " (" .. Shop.Price(item.cost) .. ")") end
    if item.kind then
        emotes[sid] = {kind = item.kind, frame = frames}
        for _, other in global.ipairs(order) do
            if other ~= me and other ~= sid and players[other] and not players[other].pending then
                send(other, "em|" .. sid .. "|" .. item.kind .. "|q")
            end
        end
    end
    if sid == me then global.pcall(function() global.require("pc2coop.visitor").Ate(item.kind) end)
    else send(sid, "sold|ok|" .. (item.kind or "-") .. "|" .. clean(Shop.Readable(item.item)) .. "|" .. Shop.Price(item.cost)) end
end

-- 1-6 in a shop's buy list (visitor.lua).
function Session.BuyPick(n)
    local Visitor = global.require("pc2coop.visitor")
    local entity, item = Visitor.Pick(n)
    if not entity then return false end
    if role == "client" then
        local gid = sync.EntityToGid(entity)
        if not gid then toast("Dieser Shop ist noch nicht mit dem Host abgeglichen", "ff922b"); return false end
        send(hostId, "buy|" .. gid .. "|" .. item.index)
        return true
    end
    if role == "host" then Session._HostBuy(me, nil, item.index, entity); return true end
    -- Alone: the own park.
    local Shop = global.require("pc2coop.shop")
    if not Shop.IsOpen(entity) then toast("Der Shop ist geschlossen", "ff922b"); return false end
    tasks[#tasks+1] = global.coroutine.create(function() Shop.Credit(item.cost, item.item) end)
    toast("Gekauft: " .. Shop.Readable(item.item) .. " (" .. Shop.Price(item.cost) .. ")")
    Visitor.Ate(item.kind)
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

-- Team board (board.lua): everyone adds; the host keeps it and passes it on.
local function boardWire(wire)
    if not role then return false end
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    return true
end

function Session.BoardAdd(kind, x, y, z, radius, title, text, assignee)
    local f = function(v) return v and global.string.format("%.2f", v) or "" end
    local clip = function(t) return global.string.gsub(global.tostring(t or ""), "[|\n\r]", " ") end
    return boardWire(global.table.concat({"board", "add", global.tostring(kind), f(x), f(y), f(z), f(radius or 0),
        clip(title), clip(text), clip(assignee)}, "|"))
end

function Session.BoardSet(id, field, value)
    return boardWire("board|set|" .. clean(id) .. "|" .. clean(field) .. "|" .. global.string.gsub(global.tostring(value or ""), "[|\n\r]", " "))
end

function Session.BoardRemove(id) return boardWire("board|del|" .. clean(id)) end

-- Short German words for the game's notification kinds (markers and labels in the park).
local EVENT_WORDS = {RideBroken = "Panne", RideNeedsMaintenance = "Wartung fällig", RideServiceExpired = "Wartung überfällig",
    GuestsTrapped = "Gäste eingeschlossen", GuestsStuckInPark = "Gäste stecken fest", LightningStruckRide = "Blitzeinschlag",
    LightningStruckParade = "Blitzeinschlag", ParadeBroken = "Parade kaputt", LowGuestsOnRides = "Wenig Fahrgäste",
    RideNoPower = "Kein Strom", RideUntested = "Nicht getestet"}

function Session.EventLabel(text)
    local kind = global.string.match(text or "", "Notification_([%a]+)")
    local name = global.string.match(text or "", "Name=|([^|]*)|")
    local word = kind and EVENT_WORDS[kind] or "Meldung"
    return name and name ~= "" and (word .. ": " .. name) or word
end

-- Park events with a place (ride broken down, guests trapped ...), newest last.
function Session.Events()
    local out = {}
    for i = #events, 1, -1 do
        local e = events[i]
        if frames - e.frame > EVENT_FRAMES then global.table.remove(events, i)
        else global.table.insert(out, 1, {text = e.text, label = Session.EventLabel(e.text), x = e.x, y = e.y, z = e.z,
            age = (frames - e.frame) / EVENT_FRAMES}) end
    end
    return out
end

-- Competition --------------------------------------------------------------------------
local function entryName(name) return (global.string.gsub(clean(name), ":", "")) end

local function compResults()
    if not comp or comp.phase ~= "done" then return "" end
    local sums = {}
    for _, given in global.pairs(comp.ratings) do
        for target, r in global.pairs(given) do
            local s = sums[target] or {d = 0, t = 0, n = 0}
            s.d, s.t, s.n = s.d + r.d, s.t + r.t, s.n + 1
            sums[target] = s
        end
    end
    local out = {}
    for _, sid in global.ipairs(comp.entries) do
        local s = sums[sid]
        if s then
            out[#out+1] = sid .. ":" .. global.math.floor(s.d * 10 / s.n + 0.5) .. ":" .. global.math.floor(s.t * 10 / s.n + 0.5) .. ":" .. s.n
        else out[#out+1] = sid .. ":0:0:0" end
    end
    return global.table.concat(out, ",")
end

local function compLeft()
    if not comp or comp.phase ~= "build" or not comp.endMs or not nowMs then return comp and comp.minutes * 60 or 0 end
    return global.math.max(0, global.math.floor((comp.endMs - nowMs) / 1000))
end

function Session._CompLine()
    if not comp then return "cp|-" end
    local entries = {}
    for _, sid in global.ipairs(comp.entries) do entries[#entries+1] = sid .. ":" .. entryName(comp.names[sid]) end
    return global.table.concat({"cp", comp.id, comp.mode, comp.phase, global.tostring(compLeft()), comp.topic,
        global.table.concat(entries, ";"), compResults()}, "|")
end

local function broadcastComp()
    local line = Session._CompLine()
    if comp then comp.sent = frames end
    for _, other in global.ipairs(order) do
        if other ~= me and players[other] and not players[other].pending then send(other, line) end
    end
end

function Session._CompRead(payload)
    local f = split(payload, "|")
    if f[2] == "-" or not COMP_MODES[f[3] or ""] then compView = nil; return end
    if not compView or compView.id ~= f[2] then compMine = {} end
    local entries, names = {}, {}
    for sid, name in global.string.gmatch(f[7] or "", "([^:;]+):([^;]*)") do entries[#entries+1] = sid; names[sid] = name end
    local results = {}
    for sid, d, t, n in global.string.gmatch(f[8] or "", "([^:,]+):(%d+):(%d+):(%d+)") do
        results[#results+1] = {sid = sid, d = global.tonumber(d) / 10, t = global.tonumber(t) / 10, n = global.tonumber(n)}
    end
    compView = {id = f[2], mode = f[3], phase = f[4], left = global.tonumber(f[5]) or 0, frame = frames,
        topic = cleanText(f[6] or ""), entries = entries, names = names, results = results}
end

-- Host: a new real time from the DLL (end of the build time, a fresh countdown for everyone).
function Session._CompClock()
    if role ~= "host" or not comp or not nowMs then return end
    if not comp.endMs then comp.endMs = nowMs + comp.minutes * 60000; broadcastComp(); return end
    if comp.phase == "build" and nowMs >= comp.endMs then Session.CompetitionNext()
    elseif frames - (comp.sent or 0) > 1800 then broadcastComp() end
end

-- Host: a duel is rated when everyone has rated everyone else.
function Session._CompCheck()
    if role ~= "host" or not comp or comp.phase ~= "rate" then return end
    for _, rater in global.ipairs(comp.entries) do
        if players[rater] then
            for _, target in global.ipairs(comp.entries) do
                if target ~= rater and not (comp.ratings[rater] and comp.ratings[rater][target]) then broadcastComp(); return end
            end
        end
    end
    Session.CompetitionNext()
end

-- Host: start a competition: mode duel|timer, 1-240 minutes, a topic ("Wikinger", "max. 20.000 €").
function Session.StartCompetition(mode, minutes, topic)
    minutes = global.tonumber(minutes)
    if role ~= "host" or comp or not COMP_MODES[mode or ""] or not minutes or minutes < 1 or minutes > 240 then return false end
    compSerial = compSerial + 1
    local entries, names = {}, {}
    for _, sid in global.ipairs(order) do
        if players[sid] and not players[sid].pending then entries[#entries+1] = sid; names[sid] = nameOf(sid) end
    end
    comp = {id = "c" .. compSerial, mode = mode, phase = "build", minutes = global.math.floor(minutes),
        topic = global.string.gsub(cleanText(topic or ""), "[;:,]", " "), entries = entries, names = names, ratings = {}}
    compMine = {}
    net.NetCommand("now")
    addFeed(COMP_MODES[mode] .. " gestartet: " .. comp.minutes .. " Minuten" .. (comp.topic ~= "" and (", Thema: " .. comp.topic) or ""))
    broadcastComp()
    return true
end

-- Host: build -> rate (duel) or done (timer); rate -> done; done -> over.
function Session.CompetitionNext()
    if role ~= "host" or not comp then return false end
    if comp.phase == "build" then
        comp.phase = comp.mode == "duel" and "rate" or "done"
        addFeed(comp.mode == "duel" and "Die Zeit ist um. Jetzt bewertet ihr die Bauten der anderen." or "Die Zeit ist um.")
    elseif comp.phase == "rate" then
        comp.phase = "done"
        addFeed("Die Bewertung ist abgeschlossen, das Ergebnis steht beim Wettbewerb.")
    else
        comp = nil
    end
    broadcastComp()
    return true
end

-- Rate another player's build: design and technique, 1-5 each.
function Session.RateEntry(target, design, tech)
    design, tech = global.tonumber(design), global.tonumber(tech)
    local current = comp or compView
    if not role or not current or current.phase ~= "rate" or not design or not tech or target == me then return false end
    compMine[target] = {d = global.math.floor(design), t = global.math.floor(tech)}
    local wire = "comp-rate|" .. current.id .. "|" .. clean(target) .. "|" .. compMine[target].d .. "|" .. compMine[target].t
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    return true
end

-- For the panel: {mode, label, phase, left, topic, entries = {{sid, name, me, mine}}, results}.
function Session.Competition()
    if role == "host" and not comp then compView = nil; return nil end   -- closed (or never started)
    if role == "host" then Session._CompRead(Session._CompLine()) end
    local view = compView
    if not view then return nil end
    local left = view.left
    if view.phase == "build" and role ~= "host" then left = global.math.max(0, left - global.math.floor((frames - view.frame) / 60)) end
    local entries = {}
    for _, sid in global.ipairs(view.entries) do
        local mine = compMine[sid]
        entries[#entries+1] = {sid = sid, name = view.names[sid] or "?", me = sid == me, d = mine and mine.d or 0, t = mine and mine.t or 0}
    end
    local results = {}
    for _, r in global.ipairs(view.results) do
        results[#results+1] = {name = view.names[r.sid] or "?", d = r.d, t = r.t, n = r.n}
    end
    global.table.sort(results, function(a, b) return a.d + a.t > b.d + b.t end)
    return {id = view.id, mode = view.mode, label = COMP_MODES[view.mode], phase = view.phase, left = left, topic = view.topic,
        entries = entries, results = results}
end

-- Shared test ride: everyone gets an invitation to ride along.
function Session.InviteRide(key, name)
    if not role or not validRideKey(key) then return false end
    local wire = "ride-invite|" .. key .. "|" .. clean(name or "?")
    if role == "host" then hostChange(me, split(wire, "|")) else send(hostId, wire) end
    return true
end

function Session.Invitation()
    if invitation and frames - invitation.frame > INVITE_RIDE_FRAMES then invitation = nil end
    return invitation
end

function Session.DismissInvitation() invitation = nil end

-- The open takeover question to this player, or nil (it runs out after a minute).
function Session.TakeAsk()
    local ask = Session._takeAsk
    if ask and frames - ask.frame > Session.TAKE_ASK_FRAMES then Session._takeAsk, ask = nil, nil end
    return ask
end

function Session.DismissTakeAsk() Session._takeAsk = nil end

-- Session rules (host): speed all|host, visitors 1|0, foreign free|ask.
function Session.Rules() return rules end

local RULE_WORDS = {
    speed = {all = "Spieltempo: alle", host = "Spieltempo: nur der Host"},
    visitors = {["1"] = "Besucher-Modus: erlaubt", ["0"] = "Besucher-Modus: aus"},
    foreign = {free = "Fremde Bauten abreißen: erlaubt", ask = "Fremde Bauten abreißen: erst fragen"},
}

-- Host: several rules at once ({speed = "host", ...}); one line in the log (label or the changes).
function Session.SetRules(values, label)
    if role ~= "host" then return false end
    local changed = {}
    for _, name in global.ipairs({"speed", "visitors", "foreign"}) do
        local value = values[name]
        if value ~= nil then
            if not RULE_VALUES[name][value] then return false end
            if rules[name] ~= value then rules[name] = value; changed[#changed+1] = RULE_WORDS[name][value] end
        end
    end
    if #changed == 0 then return true end
    remember("rules", rules.speed .. "," .. rules.visitors .. "," .. rules.foreign)
    local line = "rules|" .. rules.speed .. "|" .. rules.visitors .. "|" .. rules.foreign
    for _, sid in global.ipairs(order) do
        if sid ~= me and players[sid] and not players[sid].pending then send(sid, line) end
    end
    addFeed("Regeln" .. (label and (" \"" .. label .. "\"") or "") .. ": " .. global.table.concat(changed, ", "))
    return true
end

function Session.SetRule(name, value)
    if not RULE_VALUES[name or ""] then return false end
    return Session.SetRules({[name] = value})
end

local function ridesNow()
    if rideLister then return rideLister() end
    local out = {}
    local ok, list = global.pcall(function()
        return global.require("pc2coop.visitor").Rides(global.require("pc2coop.sync").RideKey)
    end)
    for _, r in global.ipairs(ok and list or {}) do out[r.key] = r.name end
    return out
end

-- Host: what the player saw when leaving, kept in pc2coop-visits-<park>.txt.
function Session._RememberVisit(sid)
    if role ~= "host" or not sid then return end
    local numbers = World.Numbers() or {}
    local rides = ridesNow()
    lastVisit[sid] = {cash = numbers.cash, rides = rides}
    if visitsFile then
        local entries = {}
        for key, name in global.pairs(rides) do
            entries[#entries+1] = key .. ":" .. global.string.gsub(global.tostring(name), "[|,:\n\r]", " ")
            if #entries >= 120 then break end
        end
        net.NetCommand("note-append|" .. visitsFile .. "|" .. sid .. "|" .. global.tostring(numbers.cash or "")
            .. "|" .. global.table.concat(entries, ",") .. "\n")
    end
end

-- "Since your last visit": new and removed rides, money, done tasks, open problems.
function Session._Since(sid)
    local before = lastVisit[sid]
    if not before then return nil end
    local now, parts = ridesNow(), {}
    local added, gone = {}, {}
    for key, name in global.pairs(now) do if not before.rides[key] then added[#added+1] = name end end
    for key, name in global.pairs(before.rides) do if not now[key] then gone[#gone+1] = name end end
    global.table.sort(added); global.table.sort(gone)
    if #added > 0 then parts[#parts+1] = #added .. " neue Fahrgeschäfte (" .. global.table.concat(added, ", ", 1, global.math.min(#added, 5)) .. ")" end
    if #gone > 0 then parts[#parts+1] = #gone .. " abgerissen (" .. global.table.concat(gone, ", ", 1, global.math.min(#gone, 5)) .. ")" end
    local numbers = World.Numbers() or {}
    if before.cash and numbers.cash and not numbers.unlimited then
        local delta = global.math.floor(numbers.cash - before.cash)
        if delta ~= 0 then parts[#parts+1] = "Kasse " .. (delta > 0 and "+" or "") .. delta .. " EUR" end
    end
    local open, done = 0, 0
    for _, item in global.ipairs(Board.List()) do
        if item.kind == "task" then if item.done then done = done + 1 else open = open + 1 end end
    end
    if open + done > 0 then parts[#parts+1] = "Aufgaben: " .. done .. " erledigt, " .. open .. " offen" end
    local problems = Session.Events()
    if #problems > 0 then parts[#parts+1] = "offene Meldung: " .. problems[#problems].text end
    if #parts == 0 then return "Nichts Neues - der Park ist wie beim letzten Mal." end
    return global.table.concat(parts, "; ")
end

-- "Seit deinem letzten Besuch" once as a message when joining or loading the park (TP-18), and
-- in the session's log for later; the window has no section for it any more.
function Session._ShowSince()
    if not sinceText then return end
    local text = "Seit deinem letzten Besuch: " .. sinceText
    toast(cut(text, 200), "00c6ff")
    -- Only in this player's log (addFeed would send the host's to everyone).
    feed[#feed+1] = text
    while #feed > 30 do global.table.remove(feed, 1) end
end

function Session._SetRideLister(fn) rideLister = fn end

-- Checkpoints (host): a copy of the park next to the game; back to it only by vote.
function Session.Checkpoint()
    if role ~= "host" or not manager then return false end
    local n = (#checkpoints > 0 and checkpoints[#checkpoints].n or 0) + 1
    local name = "Park"
    global.pcall(function() name = global.api.world.GetWorldAPIs().park:GetParkName() end)
    local base = "pc2coop-backup-" .. global.string.sub(global.string.gsub(global.tostring(name), "[^%w%-]", "_"), 1, 30) .. "-" .. n
    local okT = manager:SaveTerrainToFile("/run/" .. base .. ".trn", true)
    local okP = okT and manager:SaveParkToFile("/run/" .. base .. ".bin", true, false)
    if not okP then toast("Sicherungspunkt konnte nicht gespeichert werden.", "ff922b"); return false end
    checkpoints[#checkpoints+1] = {n = n, base = base, label = "Stand " .. n, frame = frames}
    while #checkpoints > 3 do
        local old = global.table.remove(checkpoints, 1)
        net.NetCommand("del|" .. old.base .. ".bin"); net.NetCommand("del|" .. old.base .. ".trn")
    end
    addFeed(nameOf(me) .. " hat einen Sicherungspunkt erstellt (Stand " .. n .. ")")
    return true
end

local function broadcastVote()
    local line = vote and ("vote|" .. vote.id .. "|" .. vote.kind .. "|" .. vote.arg .. "|" .. vote.text .. "|" .. vote.by) or "vote|-"
    for _, sid in global.ipairs(order) do
        if sid ~= me and players[sid] and not players[sid].pending then send(sid, line) end
    end
end

-- Host: everyone present must agree (e.g. back to a checkpoint, which reloads the park).
function Session.Propose(kind, arg)
    if role ~= "host" or vote then return false end
    if kind ~= "restore" then return false end
    local target
    for _, c in global.ipairs(checkpoints) do if global.tostring(c.n) == global.tostring(arg) then target = c end end
    if not target then return false end
    voteSerial = voteSerial + 1
    vote = {id = "v" .. voteSerial, kind = kind, arg = global.tostring(target.n), by = nameOf(me), answers = {[me] = true},
        text = "Park auf " .. target.label .. " zurücksetzen? Alle laden den Park dann neu."}
    broadcastVote()
    Session._VoteCheck()
    return true
end

function Session.Vote(yes)
    if not vote then return false end
    if role == "host" then vote.answers[me] = yes == true; Session._VoteCheck()
    else send(hostId, "vote-answer|" .. vote.id .. "|" .. (yes and "1" or "0")) end
    return true
end

function Session._VoteCheck()
    if role ~= "host" or not vote then return end
    for _, sid in global.ipairs(order) do
        if players[sid] and not players[sid].pending then
            if vote.answers[sid] == false then
                addFeed("Abstimmung abgelehnt (" .. nameOf(sid) .. ")"); vote = nil; broadcastVote(); return
            elseif vote.answers[sid] == nil then return end
        end
    end
    local done = vote
    vote = nil
    broadcastVote()
    if done.kind == "restore" then
        for _, c in global.ipairs(checkpoints) do
            if global.tostring(c.n) == done.arg then
                addFeed("Alle einverstanden: zurück auf " .. c.label)
                global.pcall(function()
                    local world = global.api.world.GetActive()
                    manager:RequestLoadParkFromFile("/run/" .. c.base .. ".bin", world, nil, parkTitle ~= "" and parkTitle or "Park", false)
                end)
            end
        end
    end
end

function Session.VoteView()
    if not vote then return false end
    local mine = vote.answers[me]
    return {id = vote.id, text = vote.text, by = vote.by, answered = mine ~= nil}
end

-- Test seam: the host's ratings file (set when the park session starts).
function Session._RatingsFile(name) ratingsFile = name end
function Session._BoardFile(name) boardFile = name end

-- Kind of the player's emote of the last four seconds (wave, cheer ...), or nil.
local function emoteFrames(kind) return (kind == "eat" or kind == "drink") and 1200 or 240 end

function Session._EmoteKind(sid)
    local e = emotes[sid]
    if e and frames - e.frame < emoteFrames(e.kind) then return e.kind end
    return nil
end

-- This player's look for the visitor figure: everyone in the session sees it (roster), and
-- the own figure uses it. Sent to the host until the roster carries it.
local function shareLook()
    if frames - lookFrame < 300 then return end
    lookFrame = frames
    if not myLook then
        local look = Figure.OwnLook()
        myLook = look and Figure.LookText(look) or nil
        if not myLook then return end
    end
    local colour = nil
    if role == "host" and players[me] then
        players[me].look = myLook
        colour = players[me].color
    elseif role == "client" and hostId and not confirm and not waiting then   -- only once the player agreed to join
        local mine = nil
        for _, pl in global.ipairs(roster.players or {}) do if pl.sid == me then mine = pl end end
        if mine then colour = mine.color end
        if not mine or mine.look ~= myLook then send(hostId, "look|" .. myLook) end
    end
    global.pcall(function() global.require("pc2coop.visitor").SetLook(Figure.ParseLook(myLook), colour) end)
end

-- The avatar is read again (QA, tests: after the profile changed).
function Session._ResetLook() myLook, lookFrame = nil, -100000 end

-- sid -> what the player does right now (emotes of the last four seconds).
function Session.Emotes()
    local out = {}
    for sid, e in global.pairs(emotes) do
        if frames - e.frame < emoteFrames(e.kind) then out[sid] = EMOTES[e.kind] else emotes[sid] = nil end
    end
    return out
end

-- Current pings: {sid, x, y, z, age (0..1)}.
function Session.Pings()
    local list = {}
    for sid, ping in global.pairs(pings) do
        local age = (frames - ping.frame) / PING_FRAMES
        if age >= 1 then pings[sid] = nil
        else list[#list+1] = {sid = sid, x = ping.x, y = ping.y, z = ping.z, age = age, gid = ping.gid} end
    end
    return list
end

-- Refusals shown at the object right now: {gid, text, color, age (0..1)}.
function Session.Conflicts()
    local list = {}
    for _, m in global.ipairs(marks) do
        if m.seen then list[#list+1] = {gid = m.gid, text = m.text, color = m.color, age = (frames - m.frame) / MARK_FRAMES} end
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
    Session._joinLobby, Session._dropLobby = offer.lobby, nil
    net.NetCommand("join|" .. offer.lobby)
end

function Session.ForgetRejoin()
    rejoin = nil
    net.NetCommand("note-write|" .. LAST_SESSION .. "|")
end
function Session.Park() return park end
function Session.Holds() return holds end

-- The player picked up something another one is editing: the tool is reset, the object says who.
function Session._Denied(name, gid)
    local who, named = someone(name)
    markConflict(gid, who .. " baut hier gerade", named and colorOfName(who) or nil,
        who .. " baut hier gerade. Dein Werkzeug wurde zurückgesetzt.")
    World.LeaveTool()
end

-- The local player paused or changed the speed (reported by the HUD hook).
function Session._LocalTime(paused, index)
    if not role then return end
    local wire = "time|" .. (paused and "1" or "0") .. "|" .. index
    if role == "host" then hostChange(me, split(wire, "|")) elseif hostId then send(hostId, wire) end
end

-- Host: a notification of the host's park (ride broken down, ...) goes to everyone.
function Session._ParkNote(text, entity)
    if role ~= "host" or global.type(text) ~= "string" then return end
    if lastNote[text] and frames - lastNote[text] < 600 then return end
    emit("session:park-note|" .. global.string.sub(text, 1, 160))
    lastNote[text] = frames
    text = global.string.gsub(global.string.sub(text, 1, 300), "[\n\r]", " ")
    -- Where it happened (the ride, the stuck guests): a marker in the park for everyone.
    local x, y, z = "", "", ""
    if entity then
        global.pcall(function()
            local p = global.api.transform.CalculateWorldTransform(entity):GetPos()
            x, y, z = num(p:GetX()), num(p:GetY()), num(p:GetZ())
            events[#events+1] = {text = text, x = p:GetX(), y = p:GetY(), z = p:GetZ(), frame = frames}
            while #events > 20 do global.table.remove(events, 1) end
        end)
    end
    for _, sid in global.ipairs(order) do
        if sid ~= me and players[sid] and not players[sid].pending then send(sid, "note|" .. x .. "|" .. y .. "|" .. z .. "|" .. text) end
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
    local why = global.string.find(rest, "invalid-placement", 1, true) and "hier nicht möglich (z. B. außerhalb der Parkgrenze)" or "beim Host nicht möglich"
    local owner = objects[gid] and objects[gid].last or "?"
    if state then
        local current = objects[gid] or {rev = 0, creator = "Park"}
        objects[gid] = {res = state.res, p = state.p, q = state.q, s = state.s, rev = current.rev + 1, last = "Host", creator = current.creator}
        deliver(others(me, upsertLine(gid)))
        addFeed("Änderung von " .. owner .. " zurückgenommen: " .. why)
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

-- Close the notice "Die Sitzung ist beendet".
function Session.DismissEnded() Session._ended = nil end

-- Close the "joining failed" notice; also leaves the lobby the failed join is still in.
function Session.DismissJoin()
    local inLobby = role ~= nil
    if joining then
        Session._dropLobby = Session._joinLobby   -- Steam may still enter it: lobby:entered leaves
    end
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
    Session._starting = nil
    invited, approved, requests, confirm, waiting, joinSource = {}, {}, {}, nil, false, nil
    pings, following, whoCache, hostSilent, selfStalled, authorsFile, dirtyAuthors = {}, nil, {}, false, false, nil, {}
    ratingsFile = nil
    if role == "host" then for _, sid in global.ipairs(order) do global.pcall(Session._RememberVisit, sid) end end
    boardFile, visitsFile, events, sinceText, vote, checkpoints, invitation = nil, nil, {}, nil, nil, {}, nil
    pingContext, lastTakeAsk, marks = nil, {}, {}
    Session._takeAsk, Session._rates = nil, {}
    comp, compView, compMine = nil, nil, {}
    if role == "host" then remember("rules", "") end
    rules.speed, rules.visitors, rules.foreign = "all", "1", "free"
    rules = {speed = "all", visitors = "1", foreign = "free"}
    Board.Reset()
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
                    dlc = p.dlc, mods = p.mods, look = p.look, emote = Session._EmoteKind(sid)}
            end
        end
        return {role = role, me = me, host = me, lobby = lobbyId, players = list, stats = stats, conflicts = conflicts, feed = feed,
            park = context == "park" and World.Numbers() or nil, stage = stage, parkTitle = parkTitle, guard = contentGuard,
            context = context, dlc = myDlc, choice = choice, board = Board.List(), events = Session.Events(),
        rules = rules, since = sinceText or false, checkpoints = checkpoints, vote = Session.VoteView()}
    end
    for _, pl in global.ipairs(roster.players or {}) do pl.hold, pl.emote = holds[pl.sid], Session._EmoteKind(pl.sid) end
    return {role = role, me = me, host = hostId, lobby = lobbyId, players = roster.players or {}, stats = roster.stats or {},
        conflicts = roster.conflicts or 0, feed = feed, park = park, stage = stage, parkTitle = parkTitle, guard = contentGuard,
        context = context, dlc = myDlc, choice = choice, board = Board.List(), events = Session.Events(),
        rules = rules, since = sinceText or false, checkpoints = checkpoints, vote = Session.VoteView()}
end

-- Once per game start (DLL memory): the two ways into the multiplayer features.
local function firstUseHint()
    if not role or context ~= "park" then parkFrames = 0; return end
    parkFrames = parkFrames + 1
    if parkFrames ~= 600 or memory.hinted == "1" then return end
    remember("hinted", "1")
    -- Since P6 the way in is the round button top left (ADR-021), not the build bar.
    toast("Tipp: Markieren zeigt allen eine Stelle und bietet Aktionen dafür an (Kommentar, Testfahrt, Übernahme). "
        .. "Alles Weitere öffnet der runde Knopf „Multiplayer“ links oben.", "4dabf7")
end

function Session.Tick()
    firstUseHint()
    if comp and comp.phase == "build" and frames % 30 == 0 then net.NetCommand("now") end
    frames = frames + 1
    Session._CheckParkArrives()
    if Session._starting and not role and frames - Session._starting > 1800 then
        Session._starting = nil
        failJoin("Steam hat nicht geantwortet. Versuch es noch einmal.", false)
    end
    if Session._report and Session._report.state == "busy" then Session._ReportWait(onNet) end
    if not Session.Available() then return end
    if role and frames % 1800 == 0 then Session._Snapshot() end
    for _ = 1, 64 do
        local event = net.NetPoll()
        if not event then break end
        Session._Remember(event)
        Session._guard.Call("session.net", onNet, event)
    end
    for i = #tasks, 1, -1 do
        local ok, failure = global.coroutine.resume(tasks[i])
        if not ok then Session._TaskError(tasks[i], failure) end
        if not ok or global.coroutine.status(tasks[i]) == "dead" then global.table.remove(tasks, i) end
    end
    if role == "host" then
        flushActions(false)
        if frames % 300 == 0 then flushAuthors() end
    end
    if role then global.pcall(shareLook) end
    checkMarks()
    if role == "client" and memory.phase == "live" and not hostSilent and lastHostFrame > 0 and frames - lastHostFrame > 600 then
        hostSilent = true   -- the connection pill, after 30 s a question (CoopLayer.js)
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

-- Diagnosis (FEAT-222, FEAT-223) --------------------------------------------------------
-- The last 200 network events, oldest first; runs of the same kind count up ("x12").
function Session._Remember(event, outgoing)
    local kind, _, sub = global.string.match(event, "^([^|]*)|?([^|]*)|?([^|]*)")
    if outgoing then kind = "out:" .. global.string.sub(kind or "", 1, 16)
    elseif kind == "msg" then kind = "msg:" .. global.string.sub(sub or "", 1, 16) end
    local ring = Session._ring
    local last = ring[#ring]
    if last and last.kind == kind then
        last.n, last.bytes, last.frame = last.n + 1, last.bytes + #event, frames
        return
    end
    ring[#ring + 1] = {kind = kind, frame = frames, bytes = #event, n = 1}
    if #ring > 200 then global.table.remove(ring, 1) end
end

function Session._DumpRing(reason)
    local ring, parts = Session._ring, {}
    for _, e in global.ipairs(ring) do
        parts[#parts + 1] = e.kind .. "@" .. e.frame .. ":" .. e.bytes .. (e.n > 1 and ("x" .. e.n) or "")
    end
    for i = 1, #parts, 40 do
        emit("session:recent|" .. reason .. "|" .. global.table.concat(parts, ",", i, global.math.min(#parts, i + 39)))
    end
end

-- Every 30 s in a session: one line with the state, for the timeline of a report.
function Session._Snapshot()
    local ok, view = global.pcall(Session.View)
    if not ok or global.type(view) ~= "table" then return end
    local lang = "?"
    global.pcall(function() lang = global.require("pc2coop.lang").Code() end)
    local acts = {}
    for i, p in global.ipairs(view.players or {}) do
        acts[#acts + 1] = i .. ":" .. (global.string.gsub(global.tostring(p.act or "-"), "[|,=%s]", "_"))
    end
    emit("session:snap|role=" .. global.tostring(role) .. "|players=" .. #(view.players or {}) .. "|stage=" .. global.tostring(stage)
        .. "|context=" .. global.tostring(context) .. "|conflicts=" .. global.tostring(view.conflicts or 0) .. "|lang=" .. lang
        .. "|faults=" .. Session._guard.Count() .. "|code=" .. global.tostring(Session._code) .. "|frame=" .. frames
        .. "|acts=" .. global.table.concat(acts, ","))
end

-- Six letters from the lobby id (no Steam id needed in the log to match two reports).
function Session._Code(text)
    local h = 5381
    text = global.tostring(text or "")
    for i = 1, #text do h = (h * 33 + global.string.byte(text, i)) % 2147483647 end
    local chars, out = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", ""
    for _ = 1, 6 do
        local n = h % 32
        out = out .. global.string.sub(chars, n + 1, n + 1)
        h = global.math.floor(h / 32)
    end
    return out
end

function Session._TaskError(task, failure)
    local stack = nil
    global.pcall(function() stack = global.debug.traceback(task, global.tostring(failure)) end)
    Session._guard.Report("session.task", failure, stack)
end

-- "Problembericht erstellen": the DLL writes the newest logs into one file on the desktop and
-- replaces the Steam ids and these names (P0 = this player). outdir only in developer mode.
function Session.Report(outdir)
    local lang, names, seen = "de", {}, {}
    global.pcall(function() lang = global.require("pc2coop.lang").Code() end)
    local function add(sid, name)
        sid = global.tostring(sid or "")
        if sid == "" or seen[sid] then return end
        seen[sid] = true
        names[#names + 1] = clean(sid) .. "=" .. (global.string.gsub(clean(name or ""), "=", ""))
    end
    add(me, myName)
    local ok, view = global.pcall(Session.View)
    if ok and global.type(view) == "table" then
        for _, p in global.ipairs(view.players or {}) do add(p.sid, p.name) end
    end
    add(hostId, hostName)
    Session._DumpRing("report")
    for _, e in global.ipairs(Session._guard.Recent()) do
        emit("session:report-error|" .. e.where .. "|x" .. e.count .. "|" .. global.string.sub(e.message, 1, 200))
    end
    Session._report = {state = "busy", frame = frames}
    emit("session:report|code=" .. global.tostring(Session._code) .. "|faults=" .. Session._guard.Count())
    if not (net and net.HasNet and net.HasNet()) then
        Session._report = {state = "error", reason = "Die Mod-DLL ist nicht geladen."}
        return
    end
    -- clean() would cut a folder to 32 characters; only the separator has to go.
    local folder = global.string.gsub(outdir or "", "[|%c]", "")
    net.NetCommand("report|" .. lang .. "|" .. folder .. "|" .. Session.VERSION .. "|" .. global.table.concat(names, "|"))
end

Session.REPORT_REASONS = {desktop = "Der Desktop-Ordner wurde nicht gefunden.", write = "Die Datei ließ sich nicht schreiben.",
    logs = "Es gibt noch keine Log-Datei."}
function Session._ReportResult(kind, value)
    if kind == "report:done" then
        Session._report = {state = "done", file = global.string.sub((global.string.gsub(value or "", "[|%c]", "")), 1, 120)}
        emit("session:report-done")
    else
        Session._report = {state = "error", reason = Session.REPORT_REASONS[value or ""] or "Unbekannter Fehler."}
        emit("session:report-failed|" .. global.tostring(value))
    end
end

-- Without Steam the session does not poll; the report's answer still has to come in.
function Session._ReportWait(handler)
    if not Session.Available() and net and net.HasNet and net.HasNet() then
        for _ = 1, 16 do
            local event = net.NetPoll()
            if not event then break end
            if global.string.sub(event, 1, 7) == "report:" then handler(event) end
        end
    end
    if Session._report and Session._report.state == "busy" and frames - Session._report.frame > 900 then
        Session._report = {state = "error", reason = "Keine Antwort von der Mod-DLL."}
    end
end

function Session.ReportState() return Session._report end
return Session
