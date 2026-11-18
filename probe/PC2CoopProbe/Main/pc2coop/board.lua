-- Original MIT code. The team board of a park: things players leave in the park for each
-- other. Kinds:
--   area     a build area with a brief ("Familienattraktion, max. 15.000 €, Wikingerstil")
--   task     a to-do, optionally assigned to a player, open or done
--   comment  a note pinned to a spot ("Hier entsteht ein Engpass")
--   meet     a meeting point
--   proposal a build idea at a spot ("Hier eine Wildwasserbahn?"); everyone votes yes or no
-- The host keeps the board (later lines win) and writes every change as one line to
-- pc2coop-board-<park>.txt, so the board survives game starts:
--   bd|<id>|<kind>|<x>|<y>|<z>|<radius>|<title>|<text>|<by>|<assignee>|<done>|<votes>
-- votes: "<name>:1,<name>:0" (proposals only).
--   bd-|<id>
local global = _G
local Board = {}

Board.KINDS = {area = "Baugebiet", task = "Aufgabe", comment = "Kommentar", meet = "Treffpunkt", proposal = "Vorschlag"}
local MAX_ITEMS = 200

local items = {}      -- id -> item
local nextId = 1

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

local function clean(text, limit)
    text = global.string.gsub(global.tostring(text or ""), "[|\n\r]", " ")
    return cut(text, limit or 120)
end

local function number(v)
    local n = global.tonumber(v)
    if not n or n ~= n or global.math.abs(n) > 1e6 then return nil end
    return n
end

function Board.Reset() items, nextId = {}, 1 end

-- Checks a proposed item from a player; returns the item or nil and why.
function Board.Make(kind, x, y, z, radius, title, text, by, assignee)
    if not Board.KINDS[kind or ""] then return nil, "kind" end
    local count = 0
    for _ in global.pairs(items) do count = count + 1 end
    if count >= MAX_ITEMS then return nil, "full" end
    x, y, z = number(x), number(y), number(z)
    if kind ~= "task" and not (x and y and z) then return nil, "place" end
    radius = number(radius) or 0
    if radius < 0 or radius > 200 then return nil, "radius" end
    title = clean(title, 60)
    if title == "" then title = Board.KINDS[kind] end
    return {kind = kind, x = x or false, y = y or false, z = z or false, radius = radius, title = title,
        text = clean(text, 160), by = clean(by, 32), assignee = clean(assignee, 32), done = false, votes = {}}
end

local function votesText(votes)
    local out = {}
    for name, yes in global.pairs(votes or {}) do out[#out+1] = name .. ":" .. (yes and "1" or "0") end
    global.table.sort(out)
    return global.table.concat(out, ",")
end

local function parseVotes(text)
    local votes = {}
    for name, yes in global.string.gmatch(text or "", "([^,:]+):([01])") do votes[clean(name, 32)] = yes == "1" end
    return votes
end

-- Yes and no votes of a proposal.
function Board.Tally(item)
    local yes, no = 0, 0
    for _, v in global.pairs(item.votes or {}) do if v then yes = yes + 1 else no = no + 1 end end
    return yes, no
end

function Board.Add(item)
    local id = "b" .. nextId
    nextId = nextId + 1
    item.id = id
    items[id] = item
    return item
end

function Board.Get(id) return items[id] end

-- done / assignee / text / title; returns the item when it changed.
function Board.Set(id, field, value)
    local item = items[id]
    if not item then return nil end
    if field == "done" then item.done = value == "1" or value == true
    elseif field == "assignee" then item.assignee = clean(value, 32)
    elseif field == "text" then item.text = clean(value, 160)
    elseif field == "title" then item.title = clean(value, 60)
    elseif field == "vote" and item.kind == "proposal" then
        -- value "<name>:<1|0>" - the host puts in the name of the sender
        local name, yes = global.string.match(global.tostring(value or ""), "^([^:,]+):([01])$")
        if not name then return nil end
        item.votes = item.votes or {}
        item.votes[clean(name, 32)] = yes == "1"
    else return nil end
    return item
end

function Board.Remove(id)
    if not items[id] then return false end
    items[id] = nil
    return true
end

local function n(v) return v and global.string.format("%.2f", v) or "" end

function Board.Line(item)
    return global.table.concat({"bd", item.id, item.kind, n(item.x), n(item.y), n(item.z), n(item.radius), item.title,
        item.text, item.by, item.assignee, item.done and "1" or "0", votesText(item.votes)}, "|")
end

-- A "bd" or "bd-" line from the host or the board file; returns the item (or id, true).
function Board.Apply(line)
    local f = {}
    for field in global.string.gmatch(line .. "|", "([^|]*)|") do f[#f+1] = field end
    if f[1] == "bd-" and f[2] then items[f[2]] = nil; return f[2], true end
    if f[1] ~= "bd" or not global.string.match(f[2] or "", "^b%d+$") then return nil end
    local item = Board.Make(f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11])
    if not item then return nil end
    item.id, item.done, item.votes = f[2], f[12] == "1", parseVotes(f[13])
    items[item.id] = item
    local number_id = global.tonumber(global.string.sub(item.id, 2))
    if number_id and number_id >= nextId then nextId = number_id + 1 end
    return item
end

-- Sorted for the panel: open tasks first, then by kind and title.
function Board.List()
    local out = {}
    for _, item in global.pairs(items) do out[#out+1] = item end
    local order = {task = 1, proposal = 2, area = 3, comment = 4, meet = 5}
    global.table.sort(out, function(a, b)
        if a.done ~= b.done then return not a.done end
        if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
        return a.id < b.id
    end)
    return out
end

function Board.Lines()
    local out = {}
    for _, item in global.ipairs(Board.List()) do out[#out+1] = Board.Line(item) end
    return out
end

return Board
