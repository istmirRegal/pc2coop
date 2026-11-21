-- Original MIT code. The player's language for the texts Lua draws itself: the labels at objects
-- in the world ("Erstellt von …", "… baut hier gerade"). Everything in the multiplayer layer is
-- translated there (Texts.js, ADR-022). CoopLayer.js reports the game's language ("lang" request):
-- "de" for German, "en" for every other language. Kept in the shared table: the main menu does not
-- cache modules, and the park manager runs in another module context than the UI bridge.
local global = _G
local shared = global.require("pc2coop.shared")
local Lang = {}

function Lang.Set(code)
    if code == "de" or code == "en" then shared.lang = code end
end

function Lang.Code() return shared.lang or "de" end

-- German label text -> English (Lua patterns; the names stay as they are).
local WORLD = {
    {"^Erstellt von (.+), zuletzt (.+)$", "Built by %1, last edited by %2"},
    {"^Erstellt von (.+)$", "Built by %1"},
    {"^Zuletzt bearbeitet von (.+)$", "Last edited by %1"},
    {"^(.+) baut hier gerade$", "%1 is building here"},
    {"^(.+) war schneller$", "%1 was faster"},
    {"^(.+) hat das gerade geändert$", "%1 just changed this"},
}

-- Words on the labels of marks, the board and park events.
local WORDS = {["hier!"] = "here!", Baugebiet = "Build zone", Aufgabe = "Task", Kommentar = "Comment",
    Treffpunkt = "Meeting point", Meldung = "Notification", ["Meldung des Parks"] = "Park notification",
    Panne = "Breakdown", ["Wartung fällig"] = "Maintenance due", ["Wartung überfällig"] = "Maintenance overdue",
    ["Gäste eingeschlossen"] = "Guests trapped", ["Gäste stecken fest"] = "Guests stuck", Blitzeinschlag = "Lightning strike",
    ["Parade kaputt"] = "Parade broken", ["Wenig Fahrgäste"] = "Few riders", ["Kein Strom"] = "No power",
    ["Nicht getestet"] = "Not tested"}

function Lang.World(text)
    if Lang.Code() ~= "en" or global.type(text) ~= "string" then return text end
    if WORDS[text] then return WORDS[text] end
    -- A park event with the ride's name: "Panne: Conlan".
    local word, name = global.string.match(text, "^([^:]+): (.+)$")
    if word and WORDS[word] then return WORDS[word] .. ": " .. name end
    text = global.string.gsub(text, "^Ein Mitspieler ", "A player ")
    for _, p in global.ipairs(WORLD) do
        local out, n = global.string.gsub(text, p[1], p[2])
        if n > 0 then return out end
    end
    return text
end

return Lang
