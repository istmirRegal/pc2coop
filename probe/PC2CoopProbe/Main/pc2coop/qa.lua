-- Local development controls. Fixed commands only; no eval, network or arbitrary paths.
local global = _G
local QA = {}
local emit = function() end
local poll
local frontend
local task
local frames = 0
local lastID
local managerIsTicking=false
local createdPart
local expectedPosition={10,5,10}
local testDeleted=false
local testParkRequested = false
local testSaveWorld
local testSaveComplete=false
local held
local coopFrontend -- required once: the menu's require does not cache modules
local function frontendCoop()
    if not coopFrontend then coopFrontend=global.require("pc2coop.frontend") end
    return coopFrontend
end
local function pack(...) return {n=global.select("#",...),...} end

function QA.Init(logger)
    emit = logger
    if not poll and global.package and global.type(global.package.loadlib)=="function" then
        poll = global.package.loadlib(".\\Win64\\ovldata\\PC2CoopProbe\\PC2CoopDiagnostic.dll", "pc2_poll")
    end
end

local function inspect()
    local api = global.api
    local apis = api.world.GetWorldAPIs()
    for _,key in global.ipairs({"scenery","placement","transform","editors","worldserialisation","CameraModeManager"}) do
        emit("qa:world-api:" .. key .. "=" .. global.type(apis and apis[key]))
    end
    emit("qa:frontend=" .. global.tostring(frontend~=nil))
    emit("qa:active-world=" .. global.tostring(api.world.GetActive()))
    if apis and apis.park then emit("qa:park-name=" .. global.tostring(apis.park:GetParkName())) end
    for _,key in global.ipairs({"GetTransform","GetPos","GetPosition","GetWorldTransform"}) do
        emit("qa:api.transform." .. key .. "=" .. global.type(api.transform and api.transform[key]))
    end
end

local function testWorld()
    local apis=global.api.world.GetWorldAPIs()
    if not testParkRequested or frontend or not apis or not apis.park
        or apis.park:GetParkName()~="PC2Coop-Test" then
        emit("qa:rejected:not-own-test-park");return nil
    end
    return apis
end

local function waitFor(predicate, stage)
    for i=1,900 do
        if predicate() then return end
        global.coroutine.yield()
    end
    global.error("qa:timeout:" .. stage)
end

local function samplePart(apis,label)
    local entity=apis.placement:PlacementIDToEntityID(createdPart)
    local position=global.api.transform.CalculateWorldPosition(entity)
    local x,y,z=position:GetX(),position:GetY(),position:GetZ()
    emit("qa:sample:" .. label .. "; entity=" .. global.tostring(entity)
        .. "; xyz=" .. global.tostring(x) .. "," .. global.tostring(y) .. "," .. global.tostring(z))
    return x,y,z
end

local function inspectPart(apis)
    if not createdPart then emit("qa:inspect:no-test-part");return end
    emit("qa:inspect:part=" .. global.tostring(createdPart)
        .. "; exists=" .. global.tostring(apis.placement:PlacementPartExists(createdPart)))
    if not apis.placement:PlacementPartExists(createdPart) then return end
    samplePart(apis,"inspect")
    local entity=apis.placement:PlacementIDToEntityID(createdPart)
    for _,name in global.ipairs({"GetTransform","GetWorldTransform"}) do
        local method=global.api.transform[name]
        if global.type(method)=="function" then
            local ok,value=global.pcall(function()
                local p=method(entity):GetPosition()
                return global.tostring(p:GetX()) .. "," .. global.tostring(p:GetY()) .. "," .. global.tostring(p:GetZ())
            end)
            emit("qa:inspect:" .. name .. "; ok=" .. global.tostring(ok) .. "; xyz=" .. global.tostring(value))
        end
    end
end

local function verifyPart(apis)
    if not createdPart then emit("qa:verify:no-test-part");return end
    local exists=apis.placement:PlacementPartExists(createdPart)
    if testDeleted then
        global.assert(not exists,"Deleted test part still exists")
        emit("qa:verify:deleted; part=" .. global.tostring(createdPart));return
    end
    local resource=exists and apis.placement:GetPartResourceName(createdPart) or "<absent>"
    emit("qa:verify:part=" .. global.tostring(createdPart) .. "; exists=" .. global.tostring(exists)
        .. "; resource=" .. global.tostring(resource))
    global.assert(exists and resource=="AQ_Rock_04","Saved test part missing or resource mismatch")
    local x,y,z=samplePart(apis,"verify")
    global.assert(global.math.abs(x-expectedPosition[1])<0.01 and global.math.abs(y-expectedPosition[2])<0.01
        and global.math.abs(z-expectedPosition[3])<0.01,"Test position mismatch")
    emit("qa:verify:position-passed")
end

local function commitHierarchy(apis,hierarchy,label)
    local api=global.api
    local wait,preview=api.undo.PreviewChangeList(hierarchy:GetFullUndoChangeList())
    waitFor(function() return api.undo.IsOperationComplete(wait) end,label .. "-preview")
    waitFor(function() return not apis.placement:HasPartsRequiringUpdate() end,label .. "-placement-update")
    local canCommit
    waitFor(function() canCommit=api.undo.CanCommitPreview(preview);return canCommit~=nil end,label .. "-validation")
    if canCommit~=true then
        wait=api.undo.CancelPreview(preview)
        waitFor(function() return api.undo.IsOperationComplete(wait) end,label .. "-cancel")
        global.error("Invalid test placement:" .. label)
    end
    wait=api.undo.CommitPreview(preview)
    waitFor(function() return api.undo.IsOperationComplete(wait) end,label .. "-commit")
    api.undo.Checkpoint({})
end

local function settledSamples(apis,label)
    for _,delay in global.ipairs({1,2,30,120}) do
        for i=1,delay do global.coroutine.yield() end
        samplePart(apis,label .. "-after-" .. global.tostring(delay))
    end
end

local function createRock(apis)
    local api=global.api
    if createdPart or api.undo.IsBusy() or api.undo.IsPreviewingChangeList() then
        emit("qa:create:rejected:already-created-or-editor-busy");return
    end
    local hierarchy=apis.editors:CreateUndoOperationsHierarchy()
    local completion=api.entity.CreateRequestCompletionToken()
    local object=hierarchy:CreateNewPart("AQ_Rock_04",completion)
    waitFor(function() return api.entity.HaveRequestsCompleted(completion) end,"create")
    local edit=hierarchy:StartEditingPart_Scenery(object)
    local Vector3=global.require("Vector3")
    local Quaternion=global.require("Quaternion")
    local TransformQ=global.require("TransformQ")
    edit:SetTransform(TransformQ.FromOrPos(Quaternion.Identity,Vector3:new(10,5,10)))
    local ids=apis.scenery:GetMoveObjectPartIDs(edit)
    global.assert(global.type(ids)=="table" and #ids==1,"Expected one scenery part")
    local part=ids[1]
    local position=edit:GetPosition()
    emit("qa:create:prepared; part=" .. global.tostring(part) .. "; position=" .. global.tostring(position))
    commitHierarchy(apis,hierarchy,"create")
    createdPart=part
    emit("qa:create:committed; part=" .. global.tostring(part))
    samplePart(apis,"create-immediate")
    settledSamples(apis,"create")
    verifyPart(apis)
end

local function editRock(apis,deleting)
    local api=global.api
    global.assert(createdPart and not testDeleted,"No live test part")
    global.assert(not api.undo.IsBusy() and not api.undo.IsPreviewingChangeList(),"Editor busy")
    local hierarchy=apis.editors:CreateUndoOperationsHierarchy()
    if deleting then
        local selection=apis.scenery:CreateBuildingPartSet()
        selection:Add(createdPart)
        local objects=hierarchy:DestroyExistingParts(selection)
        local edits=hierarchy:StartEditingParts_Scenery(objects)
        global.assert(#edits==1,"Expected one delete target")
        edits[1]:Destroy()
    else
        local completion=api.entity.CreateRequestCompletionToken()
        local object=hierarchy:EditExistingPart(createdPart,nil,completion)
        waitFor(function() return api.entity.HaveRequestsCompleted(completion) end,"move-edit")
        local edit=hierarchy:StartEditingPart_Scenery(object)
        emit("qa:move:before=" .. global.tostring(edit:GetPosition()))
        edit:SetTransform(global.require("TransformQ").FromOrPos(global.require("Quaternion").Identity,
            global.require("Vector3"):new(20,5,15)))
    end
    commitHierarchy(apis,hierarchy,deleting and "delete" or "move")
    testSaveComplete=false
    if deleting then
        testDeleted=true
        for i=1,30 do global.coroutine.yield() end
        emit("qa:delete:committed")
    else
        expectedPosition={20,5,15}
        settledSamples(apis,"move")
        emit("qa:move:committed")
    end
    verifyPart(apis)
end

local function execute(command, manager)
    if command == "inspect" then
        inspect()
    elseif command == "introspect" then
        if testWorld() then global.require("pc2coop.introspect").Run(emit) end
    elseif command == "new-test-park" then
        if not frontend or frontend.parkLoadSaveManager ~= manager then
            emit("qa:new-test-park:rejected:not-in-frontend"); return
        end
        -- Invoke the current game's existing single-player creation flow.
        frontend.sNewParkName = "PC2Coop-Test"
        frontend:OnSandboxConfirmNewParkSetup(3, "Temperate", nil, nil)
        testParkRequested=true
        createdPart=nil
        expectedPosition={10,5,10}
        testDeleted=false
        testSaveWorld=nil
        testSaveComplete=false
        global.require("pc2coop.live").AuthorizeNewPark()
        emit("qa:new-test-park:requested")
    elseif command=="terrain-stroke" then
        -- Same calls as TerrainEditMode.AdvanceTerrainEdit for one "pull" frame.
        local apis=global.api.world.GetWorldAPIs()
        local h=apis.editors:CreateUndoOperationsHierarchy()
        local op=h:GetTerrainEditOperation()
        apis.gameterrain:SetTerrainEditOpCollisionFlags(op,true,false,false,false,false,false)
        apis.gameterrain:AddPushPullToChangeList(op,global.require("Vector3"):new(0,0,0),12,1,0.5)
        local wait,preview=global.api.undo.PreviewChangeList(h:GetFullUndoChangeList())
        waitFor(function() return global.api.undo.IsOperationComplete(wait) end,"terrain-preview")
        local valid
        waitFor(function() valid=global.api.undo.CanCommitPreview(preview);return valid~=nil end,"terrain-validate")
        emit("qa:terrain:valid=" .. global.tostring(valid))
        wait=global.api.undo.CommitPreview(preview)
        waitFor(function() return global.api.undo.IsOperationComplete(wait) end,"terrain-commit")
        emit("qa:terrain:committed")
    elseif command=="terrain-height" then
        local apis=global.api.world.GetWorldAPIs()
        local Vector3=global.require("Vector3")
        local out={}
        for _,xz in global.ipairs({{10,10},{0,0},{200,200}}) do
            local id,distance=apis.voxelterrain:RayCastAll(Vector3:new(xz[1],500,xz[2]),Vector3:new(0,-1,0),2000)
            out[#out+1]=xz[1] .. "," .. xz[2] .. "=" .. global.tostring(distance and (500-distance))
        end
        emit("qa:height:" .. global.table.concat(out,";"))
    elseif command=="rename-park" then
        global.api.world.GetWorldAPIs().park:SetParkName("Co-op Testpark")
        emit("qa:park-name=" .. global.tostring(global.api.world.GetWorldAPIs().park:GetParkName()))
    elseif command=="park-name" then
        emit("qa:park-name=" .. global.tostring(global.api.world.GetWorldAPIs().park:GetParkName()))
    elseif command=="path-test" then
        -- Rebuilds VolumeSplineMode + VolumeEditHelper by hand to find what a path commit needs.
        local apis=global.api.world.GetWorldAPIs()
        local V,Q,T=global.require("Vector3"),global.require("Quaternion"),global.require("TransformQ")
        local undo=global.api.undo
        for variant=1,3 do
            local z=330+variant*12
            local h=apis.editors:CreateUndoOperationsHierarchy()
            h:BeginVolumeModificationsBlock()
            h:SetPerformTerrainModificationsModifyVolumes(false)
            apis.gameterrain:SetTerrainEditOpCollisionFlags(h:GetTerrainEditOperation(),true,false,false,false,true,true)
            local mo=apis.volumes:CreateMoveObjectForVolumeSpline(h,T.FromOrPos(Q.Identity,V:new(70,-0.23,z)),false,false,true,false)
            h:SetErrorOnPathMergeUnchangedModifyVolumes(true)
            apis.volumes:SetSplinePathData(mo,"Path","Path_01","PathEdge_NoRails",2,1,2,5,true,{V:new(0.4,0.36,0.29)},{})
            if variant==3 then mo:SetTransform(mo:GetTransform():WithPos(V:new(95,-0.23,z+4))) end
            h:EndVolumeModificationsBlock()
            local wait,preview=undo.PreviewChangeList(h:GetFullUndoChangeList())
            waitFor(function() return undo.IsOperationComplete(wait) end,"path-preview")
            for frame=1,(variant==1 and 1 or 40) do
                apis.volumes:SetSplineBuildingOptions(mo,true,true,false,5)
                mo:SetTransform(mo:GetTransform():WithPos(V:new(95,-0.23,z+4)))
                global.coroutine.yield()
            end
            for i=1,10 do global.coroutine.yield() end
            h:SetPerformTerrainModificationsModifyVolumes(true)
            local valid
            waitFor(function() valid=undo.CanCommitPreview(preview);return valid~=nil end,"path-validate")
            local reasons={}
            if not valid then
                for k,v in global.pairs(undo.GetCommitFailReasons(preview) or {}) do if v==true then reasons[#reasons+1]=k end end
            end
            local okStart,s=global.pcall(function() local a,b=apis.volumes:GetSplineResultData(mo); return global.tostring(a) .. "/" .. global.tostring(b) end)
            emit("qa:path-test:variant=" .. variant .. ";valid=" .. global.tostring(valid) .. ";reasons=" .. global.table.concat(reasons,",") .. ";result=" .. global.tostring(s))
            if valid then
                wait=undo.CommitPreview(preview)
                waitFor(function() return undo.IsOperationComplete(wait) end,"path-commit")
                undo.Checkpoint({})
            else
                wait=undo.CancelPreview(preview)
                waitFor(function() return undo.IsOperationComplete(wait) end,"path-cancel")
            end
        end
        emit("qa:path-test:done")
    elseif command=="ui-test" then
        -- Own Gameface view from the mod's UI package (coui://UIGameface/PC2CoopOverlay.html).
        local ui2=global.api.ui2
        -- The game mounts its UI packages by name at start (GameScript.Init); ours likewise.
        local okMap,mapResult=global.pcall(ui2.MapResources,"PC2CoopUI")
        emit("qa:ui-test:map=" .. global.tostring(okMap) .. "/" .. global.tostring(mapResult))
        -- Same construction as the game's DialogUI (registered with the UI manager).
        local Wrapper=global.require("UI.GamefaceUIWrapper")
        local readyWrapped=false
        local wrapper=Wrapper.new(Wrapper)
        wrapper:Init({sViewName="PC2CoopOverlay",sViewAddress="coui://UIGameface/PC2CoopOverlay.html",
            bStartEnabled=true,nViewDepth=25,fnOnReadyCallback=function() readyWrapped=true end})
        for i=1,300 do if readyWrapped then break end global.coroutine.yield() end
        emit("qa:ui-test:wrapper-ready=" .. global.tostring(readyWrapped))
        if readyWrapped then wrapper:TriggerEventAtNextAdvance("SetText","PC2 Co-op: eigene Spielansicht aktiv") end
        for n,address in global.ipairs({}) do
            local view=ui2.CreateView("PC2CoopTest" .. n,1920,1080)
            ui2.UpdateViewRenderToScreenDepth(view,30)
            ui2.UpdateViewRenderToScreenFullScreen(view,true)
            ui2.EnableViewRenderToScreen(view)
            local bound,ready=false,false
            ui2.SetViewReadyForBindingsCallback(view,function()
                bound=true
                ui2.RegisterForEvent(view,"OnReady",0,function() ready=true end,{})
            end,{})
            ui2.RequestViewLoad(view,address)
            for i=1,300 do if ready then break end global.coroutine.yield() end
            emit("qa:ui-test:" .. address .. ";bound=" .. global.tostring(bound) .. ";ready=" .. global.tostring(ready))
            if ready and n>1 then ui2.TriggerEventAtNextAdvance(view,"SetText","Hallo aus Lua - PC2 Co-op")
            else ui2.DestroyView(view) end
        end
    elseif command=="focus-paths" then
        global.api.world.GetWorldAPIs().CameraModeManager:RequestMode("Focus",{vFocusPos=global.require("Vector3"):new(83,0,385)})
        emit("qa:focused")
    elseif command=="ride-probe" then
        -- What the game offers for finding flat ride names (research, read-only).
        local okR,RDB=global.pcall(global.require,"Helpers.RideDatabaseUtils")
        emit("qa:ride-probe:rdb=" .. global.tostring(okR) .. "/" .. global.type(RDB))
        if okR and global.type(RDB)=="table" then
            local keys={}
            for k,v in global.pairs(RDB) do keys[#keys+1]=global.tostring(k) .. ":" .. global.type(v) end
            global.table.sort(keys)
            emit("qa:ride-probe:keys=" .. global.table.concat(keys,","))
            for k,v in global.pairs(RDB) do
                if global.type(v)=="function" and global.string.match(global.tostring(k),"^Get") then
                    local okC,res=global.pcall(v)
                    if okC and global.type(res)=="table" then
                        local sample,n={},0
                        for kk,vv in global.pairs(res) do
                            n=n+1
                            if #sample<12 then sample[#sample+1]=global.tostring(kk) .. "=" .. (global.type(vv)=="table" and "{" .. global.tostring(vv.sName or vv.name or vv[1] or "") .. "}" or global.tostring(vv)) end
                        end
                        emit("qa:ride-probe:" .. global.tostring(k) .. "#" .. n .. "=" .. global.table.concat(sample,","))
                    end
                end
            end
        end
        local okS,st=global.pcall(function() return global.api.database.GetPreparedStatementInstance("FlatRides","GetAllFlatRides") end)
        emit("qa:ride-probe:stmt=" .. global.tostring(okS) .. "/" .. global.tostring(st))
        emit("qa:ride-probe:done")
    elseif command=="flatride-test" then
        -- Places a flat ride exactly like FlatRidePlacementMode.CreateNew in the own test park.
        local apis=testWorld(); if not apis then return end
        local V,Q,T=global.require("Vector3"),global.require("Quaternion"),global.require("TransformQ")
        local RDB=global.require("Helpers.RideDatabaseUtils")
        local undo=global.api.undo
        local name
        for _,candidate in global.ipairs({"FR_Teacups","fr_teacups","Teacups","FR_GrandCarousel","fr_grandcarousel"}) do
            local ok,cost=global.pcall(RDB.GetRideBuildCost,candidate)
            emit("qa:flatride-test:cost:" .. candidate .. "=" .. global.tostring(ok) .. "/" .. global.tostring(cost))
            if ok and global.type(cost)=="number" and cost>0 and not name then name=candidate end
        end
        name=name or "FR_Teacups"
        local token=apis.flatrides:CreateFlatRideEditToken(name)
        local h=apis.editors:CreateUndoOperationsHierarchy()
        local mo=h:CreateCompositeObject({})
        apis.flatrides:AddFlatRide(h,mo,token,apis.editors.TerrainActionType_PathJoinPartFlatten,false)
        global.pcall(function() mo:AlignCompositeRotation() end)
        mo:SetTransform(T.FromOrPos(Q.Identity,V:new(60,-0.23,300)))
        local wait,preview=undo.PreviewChangeList(h:GetFullUndoChangeList())
        waitFor(function() return undo.IsOperationComplete(wait) end,"ride-preview")
        for i=1,20 do mo:SetTransform(T.FromOrPos(Q.Identity,V:new(60,-0.23,300))); global.coroutine.yield() end
        local valid
        waitFor(function() valid=undo.CanCommitPreview(preview);return valid~=nil end,"ride-validate")
        local reasons={}
        if not valid then for k,v in global.pairs(undo.GetCommitFailReasons(preview) or {}) do if v==true then reasons[#reasons+1]=k end end end
        if valid then
            wait=undo.CommitPreview(preview)
            waitFor(function() return undo.IsOperationComplete(wait) end,"ride-commit")
            undo.Checkpoint({})
        else
            wait=undo.CancelPreview(preview)
            waitFor(function() return undo.IsOperationComplete(wait) end,"ride-cancel")
        end
        for i=1,10 do global.coroutine.yield() end
        local rideID=apis.flatrides:GetRideIDForToken(token)
        local okP,part=global.pcall(function() return apis.placement:EntityIDToPlacementID(rideID) end)
        local okS,stations=global.pcall(function() return #(apis.ridestation:GetAllStations() or {}) end)
        emit("qa:flatride-test:name=" .. name .. ";valid=" .. global.tostring(valid) .. ";reasons=" .. global.table.concat(reasons,",")
            .. ";ride=" .. global.tostring(rideID) .. ";part=" .. global.tostring(okP and part) .. ";stations=" .. global.tostring(okS and stations))
        emit("qa:flatride-test:cmd=" .. global.tostring(global.require("pc2coop.sync").Stats().lastCmd))
        emit("qa:flatride-test:done")
    elseif command=="gate-test" then
        -- Adds an entrance to the newest station like EntranceExitPlacementMode (New) does.
        local apis=testWorld(); if not apis then return end
        local V=global.require("Vector3")
        local undo,rs=global.api.undo,apis.ridestation
        local list=rs:GetAllStations() or {}
        -- The westernmost station: replay-last then rebuilds the gate 30 m further east.
        local station,bestX
        for _,candidate in global.ipairs(list) do
            local x=global.api.transform.CalculateWorldTransform(candidate):GetPos():GetX()
            if not bestX or x<bestX then station,bestX=candidate,x end
        end
        if not station then emit("qa:gate-test:no-station"); return end
        local rideTransform=global.api.transform.CalculateWorldTransform(station)
        local center=rideTransform:GetPos()
        local rideInfo=rs:GetRideStationEditToken(station)
        local group=rs:GetPathJoinPartGroupIDForToken(rideInfo)
        local gate=rs:CreateEntranceExitEditToken("FlatRideEntranceGate",rs.RideGateType_Entrance)
        local h=apis.editors:CreateUndoOperationsHierarchy()
        h:SetPerformTerrainModificationsModifyVolumes(false)
        local previewToken=rs:AddEntranceExit(h:GetFullUndoChangeList(),rideInfo,gate)
        local join=apis.volumes:CreateMoveObjectPlatformGateJoin(h,group,gate,false)
        apis.volumes:SetPlatformGateJoinRaycastToGround(join,true)
        local op=h:GetTerrainEditOperation()
        apis.gameterrain:SetTerrainEditOpCollisionFlags(op,true,true,false,false,true,true)
        local wait,preview=undo.PreviewChangeList(h:GetFullUndoChangeList())
        waitFor(function() return undo.IsOperationComplete(wait) end,"gate-preview")
        local success,valid
        local reasons={}
        -- Like a player moving the mouse around the platform until the gate snaps validly.
        for _,offset in global.ipairs({{9,0},{12,0},{0,9},{0,12},{-9,0},{6,0},{15,0},{0,-9}}) do
            for frame=1,25 do
                h:BeginVolumeModificationsBlock()
                join:SetPosition(V:new(center:GetX()+offset[1]+frame*0.01,center:GetY(),center:GetZ()+offset[2]))
                success=apis.volumes:GetPlatformGateJoinSuccess(join)
                if success then apis.placement:UpdatePreviewTransform(previewToken,rideTransform:ToLocal(join:GetTransform())) end
                h:EndVolumeModificationsBlock()
                global.coroutine.yield()
            end
            h:SetPerformTerrainModificationsModifyVolumes(true)
            valid=nil
            waitFor(function() valid=undo.CanCommitPreview(preview);return valid~=nil end,"gate-validate")
            reasons={}
            if not valid then for k,v in global.pairs(undo.GetCommitFailReasons(preview) or {}) do if v==true then reasons[#reasons+1]=k end end end
            emit("qa:gate-test:try=" .. offset[1] .. "," .. offset[2] .. ";join=" .. global.tostring(success) .. ";valid=" .. global.tostring(valid) .. ";reasons=" .. global.table.concat(reasons,","))
            if valid then break end
            h:SetPerformTerrainModificationsModifyVolumes(false)
        end
        if valid then
            wait=undo.CommitPreview(preview)
            waitFor(function() return undo.IsOperationComplete(wait) end,"gate-commit")
            undo.Checkpoint({})
        else
            wait=undo.CancelPreview(preview)
            waitFor(function() return undo.IsOperationComplete(wait) end,"gate-cancel")
        end
        for i=1,10 do global.coroutine.yield() end
        local sync=global.require("pc2coop.sync")
        emit("qa:gate-test:station=" .. global.tostring(station) .. ";gid=" .. global.tostring(sync.EntityToGid(station))
            .. ";join=" .. global.tostring(success) .. ";valid=" .. global.tostring(valid) .. ";reasons=" .. global.table.concat(reasons,",")
            .. ";hasGate=" .. global.tostring(rs:HasRideGate(station,rs.RideGateType_Entrance)))
        emit("qa:gate-test:cmd=" .. global.tostring(sync.Stats().lastCmd))
        emit("qa:gate-test:done")
    elseif command=="gate-check" then
        local rs=global.api.world.GetWorldAPIs().ridestation
        local parts={}
        for _,station in global.ipairs(rs:GetAllStations() or {}) do
            parts[#parts+1]=global.tostring(global.require("pc2coop.sync").EntityToGid(station)) .. "="
                .. global.tostring(rs:HasRideGate(station,rs.RideGateType_Entrance))
        end
        emit("qa:gate-check:" .. global.table.concat(parts,","))
    elseif command=="replay-last" then
        -- Replays the last recorded batch 30 m further along x, as a friend's game would.
        local sync=global.require("pc2coop.sync")
        local batch=global.tostring(sync.Stats().lastCmd or "")
        if batch=="" then emit("qa:replay-last:none"); return end
        local shifted=global.string.gsub(batch,"SetTransform%(t([%-%d%.e]+):",function(x) return "SetTransform(t" .. (global.tonumber(x)+30) .. ":" end)
        shifted=global.string.gsub(shifted,"SetPosition%(v([%-%d%.e]+):",function(x) return "SetPosition(v" .. (global.tonumber(x)+30) .. ":" end)
        shifted=global.string.gsub(shifted,"e([FS])(%-?%d+)_",function(kind,x) return "e" .. kind .. (global.tonumber(x)+300) .. "_" end)
        local before=0
        global.pcall(function() before=#(global.api.world.GetWorldAPIs().ridestation:GetAllStations() or {}) end)
        if not sync.Stats().active then sync.Receive("S|QA") end
        local seq=(sync.Stats().lastSeq or 0)+1
        sync.Receive("K|" .. seq .. "|" .. shifted)
        waitFor(function() return (sync.Stats().lastSeq or 0)>=seq end,"replay")
        for i=1,20 do global.coroutine.yield() end
        local after=0
        global.pcall(function() after=#(global.api.world.GetWorldAPIs().ridestation:GetAllStations() or {}) end)
        emit("qa:replay-last:stations " .. before .. "->" .. after)
        emit("qa:replay-last:done")
    elseif command=="transfer-test" then
        -- Sends this park to ourselves over Steam (loopback), like a join does. Needs coop-host.
        local manager=global.api.game.GetEnvironment():RequireInterface("Interfaces.IParkLoadSaveManager")
        local me=global.require("pc2coop.session").View().me
        if not me then emit("qa:transfer-test:no-session"); return end
        local okT=manager:SaveTerrainToFile("/run/pc2coop-host-qa.trn",true)
        local okP=manager:SaveParkToFile("/run/pc2coop-host-qa.bin",true,false)
        emit("qa:transfer-test:saved=" .. global.tostring(okT) .. "/" .. global.tostring(okP))
        local diag=global.require("pc2coop.diagnostic")
        diag.NetCommand("file|" .. me .. "|pc2coop-host-qa.trn|pc2coop-qa.trn")
        diag.NetCommand("file|" .. me .. "|pc2coop-host-qa.bin|pc2coop-qa.bin")
        emit("qa:transfer-test:queued")
    elseif command=="last-cmd" then
        emit("qa:last-cmd=" .. global.tostring(global.require("pc2coop.sync").Stats().lastCmd))
    elseif command=="sync-stats" then
        local s=global.require("pc2coop.sync").Stats()
        emit("qa:stats:cmdSent=" .. global.tostring(s.cmdSent) .. ";inbound=" .. global.tostring(s.inbound) .. ";lastSeq=" .. global.tostring(s.lastSeq) .. ";known=" .. global.tostring(s.known))
    elseif command=="recorder-on" then
        global.require("pc2coop.recorder").SetEnabled(true)
        emit("qa:recorder:on")
    elseif command=="lobby-test" then
        global.require("pc2coop.ui").SetOpen(true)
        emit("qa:lobby-test:open")
    elseif command=="chat-test" then
        global.require("pc2coop.session").SendChat("Hallo zusammen, das ist ein Test")
        emit("qa:chat-test:sent")
    elseif command=="menu-test" then
        global.require("pc2coop.menu").Toggle()
        emit("qa:menu-test:toggled")
    elseif command=="label-test" then
        local labels=global.require("pc2coop.labels")
        labels.Init(emit)
        local Vector3=global.require("Vector3")
        global.api.world.GetWorldAPIs().CameraModeManager:RequestMode("Focus",{vFocusPos=Vector3:new(10,5,10)})
        local tags={{name="Alex",activity="baut",x=10,y=9,z=10},{name="Sam",activity="schaut",x=16,y=9,z=10}}
        for i=1,120 do
            labels.Show(tags)
            global.coroutine.yield()
        end
        emit("qa:label-test:shown")
    elseif command=="list-rocks" then
        -- Part IDs near the test rock position; used to check ID stability across reloads.
        local apis=global.api.world.GetWorldAPIs()
        local entities=global.api.spatial.SphereQuery(global.require("Vector3"):new(10,5,10),4,global.api.spatial.Flag_Scenery)
        local found={}
        for i=1,#entities do
            local part=apis.placement:EntityIDToPlacementID(entities[i])
            if part then found[#found+1]=global.tostring(part) .. "=" .. global.tostring(apis.placement:GetPartResourceName(part)) end
        end
        emit("qa:rocks:" .. global.table.concat(found,","))
    elseif command=="save-probe" then
        -- Where do script saves land on disk? Try a relative and an absolute-looking name.
        for _,name in global.ipairs({"pc2coop-xfer-relative","/run/pc2coop-xfer-run","Win64/ovldata/PC2CoopProbe/pc2coop-xfer-mod"}) do
            local ok,result=manager:SaveParkToFile(name,true,false)
            emit("qa:save-probe:" .. name .. "; ok=" .. global.tostring(ok) .. "; result=" .. global.tostring(result))
            local okT,resultT=manager:SaveTerrainToFile(name .. "-terrain",true)
            emit("qa:save-probe-terrain:" .. name .. "; ok=" .. global.tostring(okT) .. "; result=" .. global.tostring(resultT))
        end
        emit("qa:save-probe:done")
    elseif command=="coop-host" then
        global.require("pc2coop.session").Host()
        emit("qa:coop:host-requested")
    elseif command=="coop-invite" then
        global.require("pc2coop.session").Invite()
        emit("qa:coop:invite-opened")
    elseif command=="coop-leave" then
        global.require("pc2coop.session").Leave()
        emit("qa:coop:left")
    elseif command=="hold-test-rock" then
        -- Simulates a player holding an object: preview stays open until commit-held-rock.
        local apis=testWorld()
        if apis then
            local api=global.api
            local hierarchy=apis.editors:CreateUndoOperationsHierarchy()
            local completion=api.entity.CreateRequestCompletionToken()
            local object=hierarchy:CreateNewPart("AQ_Rock_04",completion)
            waitFor(function() return api.entity.HaveRequestsCompleted(completion) end,"hold-create")
            local edit=hierarchy:StartEditingPart_Scenery(object)
            edit:SetTransform(global.require("TransformQ").FromOrPos(global.require("Quaternion").Identity,
                global.require("Vector3"):new(15,5,15)))
            held={hierarchy=hierarchy,part=apis.scenery:GetMoveObjectPartIDs(edit)[1]}
            local wait
            wait,held.token=api.undo.PreviewChangeList(hierarchy:GetFullUndoChangeList())
            waitFor(function() return api.undo.IsOperationComplete(wait) end,"hold-preview")
            emit("qa:held:previewing; part=" .. global.tostring(held.part))
        end
    elseif command=="commit-held-rock" then
        local apis=testWorld()
        if apis and held then
            local api=global.api
            local valid
            waitFor(function() valid=api.undo.CanCommitPreview(held.token);return valid~=nil end,"held-validation")
            global.assert(valid==true,"Held rock no longer valid")
            local wait=api.undo.CommitPreview(held.token)
            waitFor(function() return api.undo.IsOperationComplete(wait) end,"held-commit")
            api.undo.Checkpoint({})
            for i=1,10 do global.coroutine.yield() end
            local exists=apis.placement:PlacementPartExists(held.part)
            emit("qa:held:committed; part=" .. global.tostring(held.part) .. "; exists=" .. global.tostring(exists))
            global.assert(exists,"Held rock missing after commit")
            held=nil
        end
    elseif command=="create-test-rock" then
        local apis=testWorld()
        if apis then createRock(apis) end
    elseif command=="verify-test-rock" then
        local apis=testWorld()
        if apis then verifyPart(apis) end
    elseif command=="inspect-test-rock" then
        local apis=testWorld()
        if apis then inspectPart(apis) end
    elseif command=="move-test-rock" or command=="delete-test-rock" then
        local apis=testWorld()
        if apis then editRock(apis,command=="delete-test-rock") end
    elseif command=="save-test-park" then
        local apis=testWorld()
        if apis and createdPart then
            verifyPart(apis)
            local ok,failure=manager:SaveTerrainToFile("/run/pc2coop-test.trn",true)
            global.assert(ok,"Test terrain save failed:" .. global.tostring(failure))
            ok,failure=manager:SaveParkToFile("/run/pc2coop-test.bin",true,false)
            global.assert(ok,"Test park save failed:" .. global.tostring(failure))
            testSaveWorld=global.api.world.GetActive()
            testSaveComplete=true
            emit("qa:save:completed; world=" .. global.tostring(testSaveWorld))
        end
    elseif command=="reload-test-park" then
        local apis=testWorld()
        if apis and testSaveComplete then
            local nextData=global.api.game.GetEnvironment():RequireInterface("Interfaces.INextWorldDataManager")
            nextData:SetGameMode("Sandbox","ScenarioEdit")
            nextData:SetParkName("PC2Coop-Test")
            local ok,failure=manager:RequestLoadParkFromFile("/run/pc2coop-test.bin",testSaveWorld,nil,"PC2Coop-Test",false)
            global.assert(ok,"Test reload failed:" .. global.tostring(failure))
            emit("qa:reload:requested")
        else
            emit("qa:reload:rejected:no-completed-test-save")
        end
    else
        emit("qa:rejected:unknown-command")
    end
end

function QA.Tick(manager)
    if task then
        local ok, failure = global.coroutine.resume(task)
        if not ok then emit("qa:task-error:" .. global.tostring(failure)); task=nil
        elseif global.coroutine.status(task)=="dead" then task=nil end
        return
    end
    frames = frames+1
    if frames%6 ~= 0 or global.type(poll)~="function" then return end
    local message = poll()
    if global.type(message)~="string" or #message>4096 then return end
    if global.string.match(message,"^%d+|sync\n") then
        global.require("pc2coop.sync").Receive(global.string.match(message,"^%d+|sync\n(.*)$"));return
    end
    if global.string.match(message,"^%d+|live|") then
        global.require("pc2coop.live").Enqueue(message);return
    end
    local id, command = global.string.match(message, "^(%d+)|([a-z-]+)$")
    if not id or id==lastID then return end
    lastID = id
    emit("qa:command:" .. id .. ":" .. command)
    task = global.coroutine.create(function() execute(command,manager) end)
end

function QA.IsOwnTestPark()
    if not testParkRequested or frontend then return false end
    local apis=global.api.world.GetWorldAPIs()
    return apis and apis.park and apis.park:GetParkName()=="PC2Coop-Test"
end

function QA.HookManager(module)
    if module.__PC2CoopQA then return end
    local original = module.Advance
    if global.type(original)~="function" then emit("qa:manager-advance-missing");return end
    module.Advance = function(self,...)
        local results = pack(original(self,...))
        managerIsTicking=true
        local ok, failure = global.pcall(QA.Tick,self)
        if not ok then emit("qa:tick-error:" .. global.tostring(failure)) end
        return global.table.unpack(results,1,results.n)
    end
    module.__PC2CoopQA = true
    emit("qa:manager-hook-installed")
end

function QA.HookFrontend(module)
    if module.__PC2CoopQA then return end
    local originalInit, originalShutdown, originalRun = module.Init, module.Shutdown, module.Run
    if global.type(originalInit)~="function" or global.type(originalShutdown)~="function" then return end
    module.Init = function(self,...)
        local results=pack(originalInit(self,...))
        frontend=self
        emit("qa:frontend-ready")
        return global.table.unpack(results,1,results.n)
    end
    module.Shutdown = function(self,...)
        if frontend==self then frontend=nil end
        global.pcall(function() frontendCoop().Shutdown() end)
        return originalShutdown(self,...)
    end
    if global.type(originalRun)=="function" then
        module.Run=function(self,...)
            local results=pack(originalRun(self,...))
            -- Multiplayer in the main menu: accept invites and load the host's park from here.
            local okCoop,coopFailure=global.pcall(function() frontendCoop().Tick(self) end)
            if not okCoop then emit("qa:frontend-coop-error:" .. global.tostring(coopFailure)) end
            if not managerIsTicking then
                local ok,failure=global.pcall(QA.Tick,self.parkLoadSaveManager)
                if not ok then emit("qa:frontend-tick-error:" .. global.tostring(failure)) end
            end
            return global.table.unpack(results,1,results.n)
        end
    end
    module.__PC2CoopQA=true
    emit("qa:frontend-hook-installed")
end

function QA.AttachLoaded()
    local loaded=global.package and global.package.loaded
    if global.type(loaded)~="table" then return end
    for name,module in global.pairs(loaded) do
        if global.type(name)=="string" and global.type(module)=="table" then
            local lower=global.string.lower(name)
            if lower=="managers.parkloadsavemanager" then QA.HookManager(module) end
            if lower=="startscreen.shared.sandboxmenuhud" then QA.HookFrontend(module) end
        end
    end
end
return QA
