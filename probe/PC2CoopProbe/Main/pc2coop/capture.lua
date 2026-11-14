-- Original MIT code. Observe completed editor commits; never creates world objects.
local global = _G
local Capture = {}
local MAX_PARTS = 32
local function pack(...) return { n = global.select("#", ...), ... } end

local function scalar(value)
    local kind = global.type(value)
    if kind == "string" then return global.string.sub(value, 1, 192) end
    if kind == "number" or kind == "boolean" then return global.tostring(value) end
    return "<" .. kind .. ">"
end

-- Each field is read on its own, so one missing accessor never hides the others.
local function field(fields, name, read)
    local ok, value = global.pcall(read)
    if ok then
        if value ~= nil then fields[#fields+1] = name .. "=" .. global.tostring(value) end
    else
        fields[#fields+1] = name .. "=<error>"
    end
end

-- SceneryEditContext.nPlacementType: 0 create, 1 clone, 2 move (build 26255360).
local function kind(self)
    local context = self.editorContext
    if not context then return "unknown" end
    if context:IsMove() then return "move" end
    if context:IsClone() then return "clone" end
    if context:IsCreate() then return "create" end
    return "unknown"
end

local function snapshot(self)
    local fields = {}
    field(fields, "kind", function() return kind(self) end)
    fields[#fields+1] = "resource=" .. scalar(self.sPropToMake)
    fields[#fields+1] = "preview=" .. scalar(self.previewToken)
    local object = self.moveObject
    if object then
        field(fields, "position", function() return object:GetPosition() end)
        field(fields, "rotation", function() return object:GetQuaternion() end)
        field(fields, "scale", function() return object:GetScale() end)
        local ids = self.sceneryAPI:GetMoveObjectPartIDs(object)
        if global.type(ids) == "table" then
            local okScale, scale = global.pcall(function() return object:GetScale() end)
            for i = 1, global.math.min(#ids, MAX_PARTS) do
                fields[#fields+1] = "part" .. i .. "=" .. scalar(ids[i])
                if okScale then
                    global.pcall(function() global.require("pc2coop.sync").NoteScale(ids[i], scale) end)
                end
            end
        end
    else
        fields[#fields+1] = "moveObject=<nil>"
    end
    return global.table.concat(fields, " | ")
end

function Capture.Install(module, emit)
    if module.__PC2CoopCapture then return end
    local original = module.CommitPreview
    if global.type(original) ~= "function" then
        emit("capture-unavailable:CommitPreview")
        return
    end
    module.CommitPreview = function(self, ...)
        -- pcall surrounds diagnostics only. Original coroutine and errors propagate.
        local ok, before = global.pcall(snapshot, self)
        if not ok then before = "snapshot-error:" .. scalar(before) end
        local results = pack(original(self, ...))
        global.pcall(emit, "commit-complete | " .. before)
        return global.table.unpack(results, 1, results.n)
    end
    module.__PC2CoopCapture = true
    emit("capture-installed:Editors.Scenery.SubModeBase.CommitPreview")
end

-- The selection is cleared before SubModeSelect commits a delete, so the part IDs
-- and resources are read beforehand and their absence is checked afterwards.
local function selected(self)
    local parts = {}
    local ids = self.editorContext:GetSelectionSet():GetPartIDCollection()
    for i = 1, global.math.min(#ids, MAX_PARTS) do
        local id = ids[i]
        local ok, resource = global.pcall(function() return self.placementAPI:GetPartResourceName(id) end)
        parts[#parts+1] = {id = id, resource = ok and resource or nil}
    end
    return parts, #ids
end

local function deleteReport(self, parts, total)
    local fields = {"total=" .. global.tostring(total)}
    for i, part in global.ipairs(parts) do
        local ok, exists = global.pcall(function() return self.placementAPI:PlacementPartExists(part.id) end)
        fields[#fields+1] = "part" .. i .. "=" .. scalar(part.id) .. "," .. scalar(part.resource)
            .. ",exists=" .. (ok and global.tostring(exists) or "<error>")
    end
    return global.table.concat(fields, " | ")
end

function Capture.InstallSelect(module, emit)
    if module.__PC2CoopCaptureSelect then return end
    local original = module._DeleteSelection
    if global.type(original) ~= "function" then
        emit("capture-unavailable:_DeleteSelection")
        return
    end
    module._DeleteSelection = function(self, ...)
        local ok, parts, total = global.pcall(selected, self)
        local results = pack(original(self, ...))
        if ok and total > 0 then
            global.pcall(function() emit("delete-complete | " .. deleteReport(self, parts, total)) end)
        elseif not ok then
            global.pcall(emit, "delete-complete | snapshot-error:" .. scalar(parts))
        end
        return global.table.unpack(results, 1, results.n)
    end
    module.__PC2CoopCaptureSelect = true
    emit("capture-installed:Editors.Scenery.SubModeSelect._DeleteSelection")
end

return Capture
