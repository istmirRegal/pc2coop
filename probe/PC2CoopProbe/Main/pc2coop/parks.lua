-- Original MIT code. Park choice for the lobby, in the main menu (host only): the host's
-- saved sandbox parks and new sandbox parks, opened through the game's own calls
-- (ParkLoadSaveManager:LoadParkFromSaveToken, SandboxMenuHUD:OnSandboxConfirmNewParkSetup).
local global = _G
local Parks = {}

local tokens = {}   -- id -> save token of the last listing (never leaves this game)
-- Preset indices of the game's SandboxSettings: 0 default rules, 1 creative (no money limit).
local DEFAULT, CREATIVE = 0, 1
Parks.BIOMES = {"Temperate", "Mediterranean", "Taiga", "Tropical"}

local function text(value)
    return global.string.sub(global.string.gsub(global.tostring(value or ""), "[|;,\n\r]", " "), 1, 48)
end

-- Saved sandbox parks, newest first: {id, name, world, time}.
function Parks.List(manager)
    local list = {}
    tokens = {}
    if not manager then return list end
    local ok, saves = global.pcall(function()
        local okEnum, found = manager:EnumerateParkSaves(global.api.save.GetExistingSaves_SortOldestFirst, "park2")
        return okEnum and found or {}
    end)
    if not ok or global.type(saves) ~= "table" then return list end
    for i = #saves, 1, -1 do
        local token = saves[i]
        local okMeta, meta = global.pcall(global.api.save.GetSaveMetadata, token)
        local save = okMeta and global.type(meta) == "table" and meta.tSave or nil
        if save and save.sGameMode == "sandbox" and #list < 60 then
            local okName, name = global.pcall(global.api.save.GetSaveCustomName, token)
            local id = global.tostring(#list + 1)
            tokens[id] = token
            list[#list+1] = {id = id, name = text(okName and name or "Park"), world = text(save.sWorldName),
                time = global.tonumber(meta.nTimestamp or meta.nSaveTime or save.nTimestamp or 0) or 0}
        end
    end
    return list
end

function Parks.Load(manager, id)
    local token = tokens[id]
    if not token or not manager then return false, "unknown park" end
    local ok, result, failure = global.pcall(function() return manager:LoadParkFromSaveToken(token) end)
    if not ok then return false, global.tostring(result) end
    return result ~= false, failure
end

-- creative: unlimited money and everything unlocked; else the game's default rules.
function Parks.New(menu, biome, creative, name)
    if not menu or not menu.OnSandboxConfirmNewParkSetup then return false, "no sandbox menu" end
    local known = false
    for _, b in global.ipairs(Parks.BIOMES) do known = known or b == biome end
    if not known then return false, "unknown biome" end
    menu.sNewParkName = text(name ~= "" and name or "PC2Coop Park")
    local ok, failure = global.pcall(function() return menu:OnSandboxConfirmNewParkSetup(creative and CREATIVE or DEFAULT, biome, nil, nil) end)
    return ok, failure
end

return Parks
