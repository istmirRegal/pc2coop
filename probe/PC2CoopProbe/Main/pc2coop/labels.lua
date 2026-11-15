-- Original MIT code. Floating name tags for other players, drawn by the game's own
-- in-world label system (the "coaster labels" billboard widget of UIBillboardWidgetsManager).
-- Each tag floats above the spot the other player looks at and reads "<name> - <activity>".
local global = _G
local Labels = {}

local emit = function() end
local shown = {}          -- index -> "label|value" currently set
local count = 0
local failed = false

local ACTIVITY = {baut = "baut", schaut = "schaut zu", empfaengt = "uebernimmt", ["-"] = ""}

local function widgets()
    local script = global.api.world.GetScript(global.api.world.GetActive())
    local environment = script and script.tEnvironment
    return environment and environment:RequireInterface("Interfaces.IUIBillboardWidgetsManager")
end

local function widgetType()
    return global.api.world.GetWorldAPIs().billboardwidgets.WidgetType_CoasterLabels
end

function Labels.Init(logger) emit = logger end

-- Positions arrive a few times per second; each tag glides to its newest one instead of
-- jumping. A far jump (camera cut, "Hinspringen") is taken at once.
local smooth = {}         -- key -> {x, y, z}
local SNAP_DISTANCE = 150

local function eased(tag, dt)
    local key = tag.key or tag.name
    local at = smooth[key]
    if not at then at = {tag.x, tag.y, tag.z}; smooth[key] = at; return at end
    local dx, dy, dz = tag.x - at[1], tag.y - at[2], tag.z - at[3]
    if dx * dx + dy * dy + dz * dz > SNAP_DISTANCE * SNAP_DISTANCE then
        at[1], at[2], at[3] = tag.x, tag.y, tag.z
    else
        local k = 1 - global.math.exp(-(dt or 1 / 60) * 9)
        at[1], at[2], at[3] = at[1] + dx * k, at[2] + dy * k, at[3] + dz * k
    end
    return at
end

-- Test tags that stay visible next to the live ones (developer check), nil to remove.
local pinned
function Labels.Pin(tags) pinned = tags end

-- tags: list of {key, name, activity, x, y, z}; dt: seconds since the last call
function Labels.Show(tags, dt)
    if failed then return end
    if pinned then
        local all = {}
        for _, tag in global.ipairs(tags) do all[#all+1] = tag end
        for _, tag in global.ipairs(pinned) do all[#all+1] = tag end
        tags = all
    end
    local ok, failure = global.pcall(function()
        if #tags == 0 then
            if count > 0 then
                local manager = widgets()
                if manager then manager:ClearBillboardWidgetData(widgetType(), true) end
            end
            count, shown, smooth = 0, {}, {}
            return
        end
        local manager = widgets()
        if not manager then return end
        local Vector3 = global.require("Vector3")
        local positions, live = {}, {}
        for i, tag in global.ipairs(tags) do
            local at = eased(tag, dt)
            live[tag.key or tag.name] = true
            positions[i] = Vector3:new(at[1], at[2], at[3])
        end
        for key in global.pairs(smooth) do if not live[key] then smooth[key] = nil end end
        if #positions ~= count then shown = {} end
        manager:SetBillboardWidgetData(widgetType(), positions)
        for i, tag in global.ipairs(tags) do
            -- The label UI translates text; literal text uses the game's STRING_LITERAL form.
            -- No value: the label then shows only this text (CoasterLabelItem.js).
            local activity = ACTIVITY[tag.activity or "-"] or tag.activity or ""
            -- The leading bullet marks the tag as the mod's (quieter look, see DebugToolImports.js).
            local text = "\226\128\162 " .. tag.name .. (activity ~= "" and (" - " .. activity) or "")
            text = global.string.gsub(text, "[|%[%]]", "")
            if shown[i] ~= text then
                manager:SetBillboardWidgetUIInfo(widgetType(), i, {sLabel = "[STRING_LITERAL:Value=|" .. text .. "|]",
                    sValueType = "Distance", nOpacity = 0.85})
                shown[i] = text
            end
        end
        count = #positions
    end)
    if not ok then
        failed = true
        emit("labels:error|" .. global.tostring(failure))
    end
end

function Labels.Clear()
    Labels.Show({})
end

return Labels
