-- Original MIT code. Floating name tags for other players, drawn by the game's own
-- in-world label system (the "coaster labels" billboard widget of UIBillboardWidgetsManager).
-- Each tag sits at the other player's camera and reads "<name>  <activity>".
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

-- tags: list of {name, activity, x, y, z}
function Labels.Show(tags)
    if failed then return end
    local ok, failure = global.pcall(function()
        local manager = widgets()
        if not manager then return end
        local Vector3 = global.require("Vector3")
        local positions = {}
        for i, tag in global.ipairs(tags) do positions[i] = Vector3:new(tag.x, tag.y, tag.z) end
        if #positions == 0 then
            if count > 0 then manager:ClearBillboardWidgetData(widgetType(), true) end
            count, shown = 0, {}
            return
        end
        manager:SetBillboardWidgetData(widgetType(), positions)
        for i, tag in global.ipairs(tags) do
            -- The label UI translates text; literal text uses the game's STRING_LITERAL form.
            -- No value: the label then shows only this text (CoasterLabelItem.js).
            local activity = ACTIVITY[tag.activity or "-"] or ""
            local text = tag.name .. (activity ~= "" and (" - " .. activity) or "")
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
