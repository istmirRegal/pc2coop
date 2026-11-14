-- Original MIT code. Developer API recorder (F7 -> Entwickler): logs mutating calls of the
-- path, ride and coaster editors with their arguments, to learn how to replay them.
-- Generated method lists come from the decompiled editors (see tools notes).
local global = _G
local Recorder = {}

local METHODS = {
    ["volumes"] = {"AddDrawingHeightStick", "AddDrawingLine", "AddDrawingPoint", "AllocDrawingID", "AppendBrushHandles", "BeginDrawing", "CalcPathCourseControls", "ClearSplineControlPoint", "CreateDrawingShape", "CreateMoveObjectForVolumeOutline", "CreateMoveObjectForVolumeSpline", "CreateMoveObjectHeightStick", "CreateMoveObjectPlatformFlumeJoin", "CreateMoveObjectPlatformGateJoin", "CreateMoveObjectsForControlHandles", "CreateMoveObjectsForSelection", "CreateSelectionAfterTranslation", "CreateSelectionFromRaycast", "CreateSelectionWithMovedSitePos", "CreateTrimmedSelection", "DestroyDrawingShape", "EndDrawing", "EraseDrawing", "ExpandSelectionUsingRaycast", "GridObjectsAreCompatible", "SetModifyVolumesLabelView", "SetPlatformGateJoinRaycastToGround", "SetSplineBorderData", "SetSplineBuildingOptions", "SetSplineControlPoint", "SetSplinePathData", "SetToUseGridObject", "SetVCAngleSnapActive", "SetVCAngleSnapDegrees", "SetVCDepth", "SetVCEdgeType", "SetVCOutlineRenderType", "SetVCOutlineType", "SetVCRoundingRadius", "SetVCSplineCurve", "SetVCSplineHeightSnap", "SetVCSplineHeightSnapActive", "SetVCSplineLengthFixed", "SetVCSplineLengthFixedActive", "SetVCSplineLengthSnap", "SetVCSplineLengthSnapActive", "SetVCSplineRoundedEnds", "SubdivideOutlines"},
    ["trackedrides"] = {"AddToDuel", "CompleteBlueprintSerialisationLoad", "NotifyTrackedRideOfTrackEdit", "ProcessEntities", "RemoveEntity", "RemoveFromDuel", "RequestRemoveNormalTrainsOnTrackedRide", "RequestRemoveNormalTrainsOnTrackedRide_IsPending"},
    ["flatrides"] = {"AddFlatRide", "AddRideAndRecursiveSequenceItemsToMultiSelection", "CreateFlatRideEditToken", "MoveFlatRide"},
    ["flumes"] = {"AddEntrance", "AddFlumePlatformSection", "AttachFlumeToPlatform", "CreateFlumePlatformSectionEditToken", "MoveEntrance", "MoveFlumePlatform", "RemoveEntrance"},
    ["infrastructure"] = {"CompleteBlueprintLoad", "CreatePlacementPreview", "EntityIsUtilityComponent", "SetComponentOnState", "UpdateInRemoveSubmode", "UpdatePlacementPreview"},
    ["scenery_group"] = {"CalculateDefaultGridForGroup", "TryGetBuildingGroupForPart"},
    ["scenery_grid"] = {"AlignLocalGridForMoveObject", "CalculateLocalGridForMoveObject", "SnapToSnapPoint", "SnapToSurfaceCentre", "TryStackGridObjectVertically"},
    ["complex"] = {"ProcessEntities"},
    ["park"] = {"AddObjectToBrush", "FlagStationForRezoning", "SetBrushIntensity", "SetBrushSize", "SetParkZoneIcon", "SetParkZoneName_PlayerOverride", "SetParkZonesVisibility", "SetVC_ParkZoneBrushRadius", "ToggleAllCrimeAffecterGUIShapes", "UpdateAllBrushObjectLists"},
    ["@track"] = {"AddAndMoveTrack", "AddGatesToEmptyStations", "AddRideAndRecursiveSequenceItemsToMultiSelection", "AddRideConnectedTargetsToMultiSelection", "AddSelection", "AreEntitiesStable", "CalcSectionLength", "ClearTrackElementCache", "CombineSelection", "CombineSelectionShortest", "CreateAutoComplete", "CreateAutoCompleteParams", "CreateJoinPoint", "CreateModifiedBankSelection", "CreateModifiedStartSelection", "CreateModifiedStation", "CreateModifiedTypeSelection", "CreatePerJoinTranslatedSelection", "CreateRescaledSelection", "CreateSelection", "CreateSelectionOfSingleSection", "CreateSelectionOfWholeTrack", "CreateSelectionOfWholeTrack_CommittedOnly", "CreateSmoothedSelection", "CreateSpecial", "CreateStation", "CreateTranslatedSelection", "FinishedEditing", "MakeTrackSelectionFromLocation", "MoveTrack", "NewSelection", "PreviewAdd", "PreviewLooksReal", "PreviewReplace", "RemoveHolder", "RemoveSelection", "ReplaceSelection", "ReverseSelection", "SectionLocation_Station_Front", "SelectContiguousWithElement", "SelectContiguousWithParam", "SetRideDesignerOverride", "SetRideName", "SetSelectionMaterialColourForSemanticTag", "StaticBestTwist", "StationCount", "TrackDirection_Both", "TrackDirection_In", "TrackDirection_None", "TrackDirection_Out", "TrackEditConstrainableAction_Delete", "TrackEditConstrainableAction_Move", "TrackParam_AltBoosterAcceleration", "TrackParam_AltBoosterMaxSpeed", "TrackParam_BackwardsBoosterAcceleration", "TrackParam_BackwardsBoosterMaxSpeed", "TrackParam_BankOnlyIntoTurns", "TrackParam_BankPivotRange", "TrackParam_BankingRange", "TrackParam_BlockSectionMaxSpeed", "TrackParam_BoosterAcceleration", "TrackParam_BoosterDirection", "TrackParam_BoosterMaxSpeed", "TrackParam_BrakeDeceleration", "TrackParam_BrakeDirection", "TrackParam_BrakeMinSpeed", "TrackParam_CabinAngle", "TrackParam_CabinAngleSet", "TrackParam_CabinPitch", "TrackParam_CabinRoll", "TrackParam_CabinRollSet", "TrackParam_CabinYaw", "TrackParam_CabinYawSet", "TrackParam_CatchOnReturnProportion", "TrackParam_ChainLiftSpeed", "TrackParam_CurveRange", "TrackParam_DefaultStationLength", "TrackParam_DropSupports", "TrackParam_DualDirectionBrakeLap", "TrackParam_ECSDirection", "TrackParam_ECSSpeed", "TrackParam_FlumePlacementOffsetY", "TrackParam_FlumePlacementOffsetZ", "TrackParam_GridSize", "TrackParam_HideTrackHandles", "TrackParam_HideTrackPlacementHandles", "TrackParam_HoldingSectionMaxTime", "TrackParam_HoldingSectionMinTime", "TrackParam_HoldingSectionReleaseAcceleration", "TrackParam_HoldingSectionReleaseSpeed", "TrackParam_HydraulicLaunchAcceleration", "TrackParam_HydraulicLaunchDelay", "TrackParam_HydraulicLaunchLauchSpeed", "TrackParam_HydraulicLaunchReturnSpeed", "TrackParam_LengthRange", "TrackParam_OptionalBlockMode", "TrackParam_ParadeEndStation", "TrackParam_ParadeStartStation", "TrackParam_ScaleRange", "TrackParam_SlopeRange", "TrackParam_StationBanking", "TrackParam_StationEntrySpeed", "TrackParam_StationExitSpeed", "TrackParam_SwapToDefaultWhenSlopedDown", "TrackParam_TrackMeshIndex", "TrackParam_UseChairliftSpline", "TrackParam_WaitToReturnDelay", "TrackSmoothType_SmoothAll", "TrackSmoothType_SmoothBank", "TrackSmoothType_SmoothHeight", "TrackSmoothType_SmoothTurn", "UpdateActiveTrackDirectionArrows", "UpdateAllTrackDirectionArrows", "UseLooseFlumeRestrictions", "UseLooseTrackRestrictions"},
}

local emit = function() end
local enabled = false
local installed = false
local counts = {}
local last
local LIMIT = 400

local function describe(value)
    local kind = global.type(value)
    if kind == "number" or kind == "boolean" then return global.tostring(value) end
    if kind == "string" then return '"' .. global.string.sub(value, 1, 40) .. '"' end
    if kind == "nil" then return "nil" end
    local ok, x, y, z = global.pcall(function() return value:GetX(), value:GetY(), value:GetZ() end)
    if ok and global.type(x) == "number" then return global.string.format("v(%.3f,%.3f,%.3f)", x, y, z) end
    if kind == "table" then
        local n = 0
        for _ in global.pairs(value) do n = n + 1 end
        return "table[" .. n .. "]"
    end
    return "<" .. kind .. ":" .. global.string.sub(global.tostring(value), 1, 24) .. ">"
end

local function record(name, args, results)
    if not enabled then return end
    counts[name] = (counts[name] or 0) + 1
    if counts[name] > LIMIT then return end
    local parts = {}
    for i = 1, global.math.min(args.n, 12) do parts[i] = describe(args[i]) end
    local out = {}
    for i = 1, global.math.min(results.n, 4) do out[i] = describe(results[i]) end
    local line = name .. "(" .. global.table.concat(parts, ",") .. ") -> " .. global.table.concat(out, ",")
    if line ~= last then emit(line) end
    last = line
end

local function wrapTable(target, prefix, names, method)
    local count = 0
    for _, name in global.ipairs(names) do
        local original = target[name]
        if global.type(original) == "function" then
            local ok = global.pcall(function()
                target[name] = function(...)
                    local results = global.table.pack(original(...))
                    local args = global.table.pack(...)
                    if method then
                        -- Drop "self" for method-style APIs.
                        global.table.remove(args, 1)
                        args.n = args.n - 1
                    end
                    global.pcall(record, prefix .. name, args, results)
                    return global.table.unpack(results, 1, results.n)
                end
            end)
            if ok then count = count + 1 end
        end
    end
    return count
end

function Recorder.Init(logger) emit = logger end

function Recorder.Install()
    if installed then return end
    installed = true
    local apis = global.api.world.GetWorldAPIs()
    local count = 0
    for key, names in global.pairs(METHODS) do
        if key == "@track" then
            count = count + wrapTable(global.api.track, "api.track.", names, false)
        elseif apis[key] then
            count = count + wrapTable(apis[key], key .. ".", names, true)
        end
    end
    emit("installed|" .. count)
end

-- Marks undo steps so recorded calls can be grouped (called from sync's undo wrappers).
function Recorder.Mark(text)
    if enabled then emit("@" .. text) end
end

function Recorder.SetEnabled(value)
    if value and not installed then global.pcall(Recorder.Install) end
    enabled = value == true
    counts, last = {}, nil
    emit(enabled and "on" or "off")
end

function Recorder.IsEnabled() return enabled end

return Recorder
