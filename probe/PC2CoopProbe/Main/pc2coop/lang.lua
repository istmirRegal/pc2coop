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

function Lang.World(text)
    if Lang.Code() ~= "en" or global.type(text) ~= "string" then return text end
    text = global.string.gsub(text, "^Ein Mitspieler ", "A player ")
    for _, p in global.ipairs(WORLD) do
        local out, n = global.string.gsub(text, p[1], p[2])
        if n > 0 then return out end
    end
    return text
end

return Lang
