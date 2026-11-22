-- Original MIT code. Catches errors in the mod's own frame work and writes where they
-- happened (the Lua call stack), so a problem report shows the line, not only the message.
-- Each kind of error is written at the 1st, 10th, 100th and every 1000th time (with "x<n>"),
-- at most 100 kinds: a broken frame cannot fill the log. The game always keeps running.
local global = _G
local Guard = {}

local write = function() end
local onFirst = nil
local seen, kinds, total = {}, 0, 0
local recent = {}

function Guard.Init(writer, firstError)
    write = writer or write
    onFirst = firstError
end

local function trace(failure)
    local text = global.tostring(failure)
    local debug = global.debug
    if debug and global.type(debug.traceback) == "function" then
        local ok, stack = global.pcall(debug.traceback, text, 3)
        if ok and global.type(stack) == "string" then text = stack end
    end
    -- One log record holds 4 KB; the top of the stack is what matters.
    return global.string.sub(text, 1, 3000)
end

local function shouldWrite(count)
    return count == 1 or count == 10 or count == 100 or count % 1000 == 0
end

-- where: short name of the work ("session.tick"); failure: the error; stack: optional.
function Guard.Report(where, failure, stack)
    total = total + 1
    local message = global.tostring(failure)
    local key = where .. "|" .. global.string.sub(message, 1, 160)
    local entry = seen[key]
    if not entry then
        if kinds >= 100 then return end
        kinds = kinds + 1
        entry = {where = where, message = message, count = 0}
        seen[key] = entry
        recent[#recent + 1] = entry
        if #recent > 20 then global.table.remove(recent, 1) end
    end
    entry.count = entry.count + 1
    if shouldWrite(entry.count) then
        write("error|" .. where .. "|x" .. entry.count .. "|" .. (stack or message))
    end
    if total == 1 and onFirst then global.pcall(onFirst, where) end
end

-- Like pcall, but a failure is reported with its stack. Returns ok, results...
function Guard.Call(where, fn, ...)
    local stack
    local function handler(failure)
        stack = trace(failure)
        return failure
    end
    local result = global.table.pack(global.xpcall(fn, handler, ...))
    if not result[1] then Guard.Report(where, result[2], stack) end
    return global.table.unpack(result, 1, result.n)
end

function Guard.Count() return total end

-- The newest kinds of errors for the problem report summary.
function Guard.Recent()
    local out = {}
    for i, entry in global.ipairs(recent) do out[i] = {where = entry.where, message = entry.message, count = entry.count} end
    return out
end

function Guard._Reset()
    seen, kinds, total, recent = {}, 0, 0, {}
end

return Guard
