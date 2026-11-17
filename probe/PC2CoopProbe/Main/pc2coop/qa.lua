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
    elseif command=="viz-probe" then
        -- Research: which engine pieces can show another player's ghost, marker and locks?
        local apis=testWorld(); if not apis then return end
        local V,Q,T=global.require("Vector3"),global.require("Quaternion"),global.require("TransformQ")
        local E,model=global.api.entity,global.api.model
        local shared=global.require("pc2coop.shared")
        emit("qa:viz:debugAllowed=" .. global.tostring(global.select(2,global.pcall(global.api.debug.IsDebugAllowed))))
        local made={}
        local function spawn(name,x,z,y)
            local token=E.CreateRequestCompletionToken()
            local ok,entity=global.pcall(E.InstantiatePrefab,name,nil,token,T.FromOrPos(Q.Identity,V:new(x,y or 0,z)))
            local done=false
            if ok then
                for i=1,180 do if E.HaveRequestsCompleted(token) then done=true; break end; global.coroutine.yield() end
            end
            local part=ok and global.select(2,global.pcall(function() return apis.placement:EntityIDToPlacementID(entity) end))
            local hasT=ok and global.select(2,global.pcall(function() return global.api.transform.HasTransform(entity) end))
            emit("qa:viz:spawn:" .. name .. "=" .. global.tostring(ok) .. "/" .. global.tostring(entity) .. ";done=" .. global.tostring(done)
                .. ";part=" .. global.tostring(part) .. ";transform=" .. global.tostring(hasT))
            if ok and entity then made[#made+1]=entity end
            return ok and entity or nil
        end
        local rock=spawn("AQ_Rock_04",0,20,1)
        local rockGame=spawn("AQ_Rock_04_game",6,20,1)
        local ring=spawn("Char_Props_PlacementRing",12,20,0.3)
        local arrow=spawn("MovableTrackedRideArrow",18,20,1)
        local gizmo=spawn("TranslateYGizmo",24,20,1)
        -- A ride prefab ("FR_Teacups") instantiated this way ends the game process: never do that.
        local cups=spawn("NAT_Tree_Conifer_Spruce_Black_Large_01",40,36,0)
        local okH,failH=global.pcall(function()
            model.SetHighlightBehaviour(3,model.HighlightDefault)
            model.SetHighlightEdgeColour(3,V:new(1,0.25,0.6),1)
            model.SetHighlightFillColour(3,V:new(1,0.25,0.6),0.45)
            if rock then model.SetHighlighted(rock,3,true,true) end
            if cups then model.SetHighlighted(cups,3,true,true) end
        end)
        emit("qa:viz:highlight=" .. global.tostring(okH) .. "/" .. global.tostring(failH))
        -- A real placed rock, highlighted the same way (a "locked by someone else" look).
        global.pcall(function()
            local list=global.api.spatial.SphereQuery(V:new(10,5,10),6,global.api.spatial.Flag_Scenery)
            emit("qa:viz:placed-nearby=" .. #list)
            if list[1] then model.SetHighlighted(list[1],3,true,true) end
        end)
        shared.vizEntities=made
        local okD,failD=true,nil
        for i=1,420 do
            okD,failD=global.pcall(function()
                global.api.debug.DrawSphere(V:new(-8,3,20),2,"Red")
                global.api.debug.DrawLine(V:new(-8,0,20),V:new(-8,12,26),"Green")
            end)
            if ring and i%10==0 then global.pcall(global.api.transform.SetPosition,ring,V:new(12+i*0.01,0.3,20)) end
            global.coroutine.yield()
        end
        emit("qa:viz:debug-draw=" .. global.tostring(okD) .. "/" .. global.tostring(failD))
        emit("qa:viz-probe:done")
    elseif command=="scale-probe" then
        -- Research: can a display-only entity be scaled, and which flat primitives exist?
        local apis=testWorld(); if not apis then return end
        local V,Q,T=global.require("Vector3"),global.require("Quaternion"),global.require("TransformQ")
        local E,model,X=global.api.entity,global.api.model,global.api.transform
        local function keys(t)
            local out={}
            if global.type(t)=="table" then
                for k in global.pairs(t) do out[#out+1]=global.tostring(k) end
                local mt=global.getmetatable(t)
                if mt and global.type(mt.__index)=="table" then for k in global.pairs(mt.__index) do out[#out+1]="^" .. global.tostring(k) end end
            end
            global.table.sort(out)
            return global.table.concat(out,",")
        end
        emit("qa:scale:transform-api=" .. keys(X))
        emit("qa:scale:TransformQ=" .. keys(T))
        emit("qa:scale:model-api=" .. keys(model))
        emit("qa:scale:entity-api=" .. keys(E))
        local okS,TS=global.pcall(global.require,"TransformQS")
        emit("qa:scale:TransformQS=" .. global.tostring(okS) .. "/" .. keys(okS and TS or nil))
        local function spawn(name,x,z,y)
            local token=E.CreateRequestCompletionToken()
            local ok,entity=global.pcall(E.InstantiatePrefab,name,nil,token,T.FromOrPos(Q.Identity,V:new(x,y or 0,z)))
            if ok then for i=1,180 do if E.HaveRequestsCompleted(token) then break end; global.coroutine.yield() end end
            emit("qa:scale:spawn:" .. name .. "=" .. global.tostring(ok) .. "/" .. global.tostring(entity))
            return ok and entity or nil
        end
        local shapes={"pc_primitive_triangle_game","pc_primitive_circle_game","pc_primitive_cone_game","pc_primitive_circle_half_game","pc_primitive_rectangle_game"}
        local made={}
        for i,name in global.ipairs(shapes) do made[i]=spawn(name,-6+i*7,22,1.5) end
        local first=made[1]
        if first then
            for _,try in global.ipairs({
                {"SetScale",function() X.SetScale(first,4) end},
                {"SetLocalScale",function() X.SetLocalScale(first,4) end},
                {"SetUniformScale",function() X.SetUniformScale(first,4) end},
                {"WithScale",function() X.SetTransform(first,X.GetTransform(first):WithScale(4)) end},
                {"SetTransform3",function() X.SetTransform(first,T.FromOrPos(Q.Identity,V:new(1,1.5,22)),4) end},
            }) do
                local ok,failure=global.pcall(try[2])
                emit("qa:scale:try:" .. try[1] .. "=" .. global.tostring(ok) .. "/" .. global.string.sub(global.tostring(failure),1,90))
            end
        end
        global.pcall(function()
            model.SetHighlightBehaviour(3,model.HighlightDefault)
            model.SetHighlightEdgeColour(3,V:new(0.3,0.75,1),1)
            model.SetHighlightFillColour(3,V:new(0.3,0.75,1),0.35)
            for _,entity in global.pairs(made) do model.SetHighlighted(entity,3,true,true) end
        end)
        global.require("pc2coop.shared").vizEntities=made
        emit("qa:scale-probe:done")
    elseif command=="ghost-test" then
        -- A made-up other player: looks around, carries a rock and a ride, edits the test rock.
        local apis=testWorld(); if not apis then return end
        local viz,labels=global.require("pc2coop.viz"),global.require("pc2coop.labels")
        local locked={}
        if createdPart and apis.placement:PlacementPartExists(createdPart) then
            locked[apis.placement:PlacementIDToEntityID(createdPart)]=true
        end
        local player={sid="qa",name="Vici",color="f06595",x=10,y=45,z=-20,fx=10,fy=0,fz=30,
            hold={label="AQ_Rock_04",gids="",items={
                {resource="AQ_Rock_04",model=true,x=4,y=1,z=34,qx=0,qy=0,qz=0,qw=1,scale=1.5},
                {resource="FR_Teacups",model=false,x=26,y=0,z=40,qx=0,qy=0,qz=0,qw=1,scale=1}}}}
        local tag={key="qa",name="Vici",activity="haelt Rock 04",x=4,y=4,z=34}
        viz.Pin({player},locked)
        labels.Pin({tag})
        for i=1,360 do
            -- the player turns: the wedge sweeps, the ghost follows
            player.fx=10+global.math.sin(i/60)*14
            player.hold.items[1].x=4+global.math.sin(i/60)*6
            tag.x=player.hold.items[1].x
            if i==150 then emit("qa:ghost-test:shown;" .. global.tostring(viz.Stats().entities) .. " entities;failed=" .. global.tostring(viz.Stats().failed)) end
            global.coroutine.yield()
        end
        viz.Pin(nil,nil)
        labels.Pin(nil)
        for i=1,30 do global.coroutine.yield() end
        emit("qa:ghost-test:done;" .. global.tostring(viz.Stats().entities) .. " entities left")
    elseif command=="held-delete-test" then
        -- The crash case: the player holds an existing object while someone else deletes it.
        local apis=testWorld(); if not apis then return end
        local api,sync=global.api,global.require("pc2coop.sync")
        if not createdPart or not apis.placement:PlacementPartExists(createdPart) then emit("qa:held-delete:no-rock"); return end
        if not sync.Stats().active then emit("qa:held-delete:not-hosting"); return end
        local part=createdPart
        local gid=sync.EntityToGid(apis.placement:PlacementIDToEntityID(part))
        local hierarchy=apis.editors:CreateUndoOperationsHierarchy()
        local completion=api.entity.CreateRequestCompletionToken()
        local object=hierarchy:EditExistingPart(part,nil,completion)
        waitFor(function() return api.entity.HaveRequestsCompleted(completion) end,"held-edit")
        local edit=hierarchy:StartEditingPart_Scenery(object)
        edit:SetTransform(global.require("TransformQ").FromOrPos(global.require("Quaternion").Identity,global.require("Vector3"):new(13,5,13)))
        local wait,token=api.undo.PreviewChangeList(hierarchy:GetFullUndoChangeList())
        waitFor(function() return api.undo.IsOperationComplete(wait) end,"held-preview")
        sync._SetHeld({[part]=true})
        emit("qa:held-delete:holding;gid=" .. global.tostring(gid))
        local seq=(sync.Stats().lastSeq or 0)+1
        sync.Receive("D|" .. seq .. "|" .. gid .. "|Vici|0")
        waitFor(function() return (sync.Stats().lastSeq or 0)>=seq end,"held-remote-delete")
        for i=1,30 do global.coroutine.yield() end
        local exists=apis.placement:PlacementPartExists(part)
        -- The editor would now ask about, and end, its preview.
        local valid
        waitFor(function() valid=api.undo.CanCommitPreview(token);return valid~=nil end,"held-validate")
        local wait2=api.undo.CancelPreview(token)
        waitFor(function() return api.undo.IsOperationComplete(wait2) end,"held-cancel")
        emit("qa:held-delete:done;exists=" .. global.tostring(exists) .. ";valid=" .. global.tostring(valid)
            .. ";mayUndo=" .. global.tostring(sync.MayUndo(true)))
    elseif command=="profile-test" then
        local world=global.require("pc2coop.world")
        local ok,failure=world.ApplyGuestProfile()
        local line={}
        global.pcall(function()
            local env=global.api.world.GetScript(global.api.world.GetActive()).tEnvironment
            local settings=env:RequireInterface("Interfaces.ISandboxSettingsManager"):GetCurrentSandboxSettings()
            for _,key in global.ipairs({"bEnabledBreakdowns","bEnabledServiceBadges","bEnabledLightningConsequences","bEnablePlayerCash"}) do
                line[#line+1]=key .. "=" .. global.tostring(settings[key])
            end
        end)
        emit("qa:profile-test:" .. global.tostring(ok) .. "/" .. global.tostring(failure) .. ";" .. global.table.concat(line,","))
    elseif command=="editor-hold-test" then
        -- Enters the game's real flat ride placement tool (as the browser does) and checks
        -- what the mod reads from it; then leaves the tool again. No mouse or keyboard.
        local apis=testWorld(); if not apis then return end
        local world=global.require("pc2coop.world")
        local function report(label)
            local a=world.Activity()
            local h=a.held
            emit("qa:editor-hold:" .. label .. ";ui=" .. global.tostring(a.ui) .. ";edit=" .. global.tostring(a.edit) .. ";text=" .. global.tostring(a.text)
                .. ";held=" .. global.tostring(h ~= nil) .. (h and (";res=" .. global.tostring(h.resource) .. ";parts=" .. #h.parts
                .. global.string.format(";at=%.1f,%.1f,%.1f", h.x, h.y, h.z)) or ""))
        end
        report("before")
        global.require("Editors.Shared.BaseUIMode").SetNewMode("GamefaceRidePlacement","FlatRide")
        global.require("Editors.Shared.BaseEditMode").SetNewMode("FlatRidePlacement","FR_Teacups",nil,true)
        for i=1,150 do global.coroutine.yield() end
        report("placing")
        for i=1,60 do global.coroutine.yield() end
        emit("qa:editor-hold:leave=" .. global.tostring(world.LeaveTool()))
        for i=1,120 do global.coroutine.yield() end
        report("after")
        emit("qa:editor-hold:done")
    elseif command=="ghost-sweep" then
        -- Every scenery type seen in real sessions as a ghost, one after the other: none may
        -- end the game. The name is logged before it is shown.
        local apis=testWorld(); if not apis then return end
        local viz=global.require("pc2coop.viz")
        local names={"FX_Nozzle_Iridescent_Bubbles_Large","FX_Nozzle_Steam_Boiling_Small","NAT_Bush_Rock_Rose_Flowers_Large_01","NAT_Flower_Sunflower_Medium_01","PC_Flag_01","PC_Flag_Bunting_01","PC_Half_Wall_BreezeBlock_2m","PC_Half_Wall_Panel_4m","PC_SingleDoor_02","PC_Wall_Panel_Floor","PC_Wall_Panel_Merge_4m","PC_Wall_Panel_Merge_ShopFront","PC_Wall_Wood_Modern_Merge_2m","PC_Wall_Wood_Modern_Merge_Curve","RE_Balcony_WallTrim_03_4m","RE_Half_Wall_PlasterDivided_2m","RE_Planters_01_03","aq_pipes_1m","aq_pipes_2m","aq_pipes_4m","aq_pipes_cross","aq_pipes_tee","aq_sign_011","aq_sign_02","aq_supportbeams_pillar_03_4m","aq_wall_bevelled_pillar_01_1m","aq_wall_bevelled_pillar_01_base","fdlc1_coaster_support_2_small_4m","nat_bush_hedge_box_crown_01","nat_bush_hedge_box_helix_01","nat_bush_hedge_box_kingcoaster_01","nat_bush_hedge_box_large_4m_01","nat_bush_hedge_box_medium_2m_01","nat_bush_hedge_box_queensplash_01","nat_bush_hedge_box_small_1m_01","nat_bush_hedge_box_small_2m_01","nat_bush_hedge_box_small_4m_01","nat_bush_hedge_box_small_arch_01","nat_flower_beds_straight_4m","pc_3dfont_coaster_e","pc_3dfont_coaster_l","pc_3dfont_coaster_lowercase_l","pc_3dfont_coaster_p","pc_3dfont_coaster_s","pc_3dfont_coaster_u","pc_3dfont_noto_d","pc_3dfont_noto_e","pc_3dfont_noto_m","pc_3dfont_noto_n","pc_3dfont_noto_question_mark","pc_3dfont_noto_r","pc_awnings_01","pc_awnings_03","pc_decal_clipboard","pc_decal_vent_05","pc_decal_vent_06","pc_decal_vent_07","pc_dressing_exterior_outlet","pc_fence_mesh_metal_1m","pc_flume_supports_footer_02","pc_lighting_hanginglight_01","pc_lighting_spot_light_03","pc_lighting_walllamp_04","pc_lighting_walllamp_06","pc_lighting_walllamp_07","pc_modular_planter_cornercurve","pc_modular_planter_edge","pc_planter_02_03","pc_primitive_circle","pc_primitive_circle_half","pc_primitive_cube","pc_primitive_rectangle","pc_recyclingbin","pc_roof_steel_curve_inverse","pc_shopfascia_01","pc_sign_generic_29","pc_sign_generic_38","pc_sign_generic_40","pc_sign_generic_42","pc_sign_generic_44","pc_sign_generic_50","pc_sign_generic_post_02_1m","pc_sign_guest_61","pc_sign_textedit_02","pc_signage_billboard_03","pc_signage_billboard_03b","pc_signage_billboard_04","pc_statue_planetcoaster_01","pc_wall_molding_curve_inverse","pc_wall_molding_flat_4m","pc_wall_molding_round_corner","re_dancingflag_02","re_lighting_metallamp_01","re_pillars_01_1m","re_pillars_01_2m","re_wallpanels_19","re_wallpanels_23","Utility_PowerGenerator_Standard","facility_shops_photokiosk","facility_shops_hayasushi_sign_small","facility_shops_hayasushi"}
        local player={sid="sweep",name="Vici",color="4dabf7",x=10,y=45,z=-20,fx=10,fy=0,fz=30,hold={label="x",gids="",items={}}}
        viz.Pin({player},{})
        local shown=0
        for _,name in global.ipairs(names) do
            emit("qa:sweep:" .. name)
            player.hold.items={{resource=name,model=true,x=10,y=1,z=30,qx=0,qy=0,qz=0,qw=1,scale=1}}
            for i=1,18 do global.coroutine.yield() end
            if viz.Stats().entities>14 then shown=shown+1 end
        end
        viz.Pin(nil,nil)
        for i=1,20 do global.coroutine.yield() end
        emit("qa:ghost-sweep:done;" .. #names .. " names;" .. shown .. " shown as model;failed=" .. global.tostring(viz.Stats().failed)
            .. ";left=" .. viz.Stats().entities)
    elseif command=="extras-test" then
        -- Hosting in the test park: a made-up player "Vici" (sid 777) joins over the session
        -- API, looks around, gets followed and pings; then the author of the test rock.
        local apis=testWorld(); if not apis then return end
        local session,sync,world=global.require("pc2coop.session"),global.require("pc2coop.sync"),global.require("pc2coop.world")
        if session.View().role~="host" then emit("qa:extras:not-hosting"); return end
        session._onNet("msg|777|hello|Vici|-1|live|" .. session.VERSION .. "|")
        emit("qa:extras:request=" .. global.tostring(#session.Requests()))
        session.Answer("777",true)
        local function look(x,y,z,yaw,pitch,fx,fz)
            session._onNet(global.string.format("msg|777|pres|%f|%f|%f|%f|%f|4|Orbit|baut|%f|0|%f",x,y,z,yaw,pitch,fx,fz))
        end
        look(40,30,-10,0.3,-0.6,48,20)
        for i=1,30 do global.coroutine.yield() end
        -- follow: our camera has to end up at Vici's
        session.SetFollow("777")
        for i=1,240 do
            if i==120 then look(60,25,0,0.8,-0.5,70,30) end
            global.coroutine.yield()
        end
        local x,y,z=world.Camera()
        emit(global.string.format("qa:extras:follow camera=%.1f,%.1f,%.1f target=60,25,0 following=%s",x or -1,y or -1,z or -1,global.tostring(session.Following())))
        session.SetFollow(nil)
        -- ping from the cursor (no mouse here: logs where it lands) and from Vici
        local cx,cy,cz=world.CursorPoint()
        emit(global.string.format("qa:extras:cursor=%.1f,%.1f,%.1f",cx or -1,cy or -1,cz or -1))
        global.pcall(function()
            local cam,start,dir=global.api.input.GetMouseRay()
            emit("qa:extras:mouseray=" .. global.tostring(cam) .. ";" .. global.string.format("%.1f,%.1f,%.1f;%.2f,%.2f,%.2f",
                start:GetX(),start:GetY(),start:GetZ(),dir:GetX(),dir:GetY(),dir:GetZ()))
        end)
        session.Ping()
        session._onNet("msg|777|ping|20|0|25")
        session._onNet("msg|777|pres|30|25|-20|0|0.6|4|Orbit|baut|18|0|22")
        for i=1,30 do global.coroutine.yield() end
        local count=0
        for _ in global.ipairs(session.Pings()) do count=count+1 end
        emit("qa:extras:pings=" .. count .. ";viz=" .. global.tostring(global.require("pc2coop.viz").Stats().entities))
        -- author of the test rock, and Vici editing it
        if createdPart and apis.placement:PlacementPartExists(createdPart) then
            -- Vici moves the rock, then the host's attribution is asked as the UI does.
            local gid=sync.GidOfPart(createdPart)
            session._onNet("msg|777|up|0|" .. gid .. "|0|AQ_Rock_04|12|5|12|0|0|0|1|1")
            for i=1,40 do global.coroutine.yield() end
            session.Attribution(gid)
            for i=1,10 do global.coroutine.yield() end
            local who=session.Attribution(gid)
            emit("qa:extras:author gid=" .. global.tostring(gid) .. " creator=" .. global.tostring(who and who.creator) .. " last=" .. global.tostring(who and who.last))
            -- Selected like a click does: the select mode's info window target.
            local okSel=global.pcall(function()
                local mode=apis.GameModeHelperComponent:GetCurrentMode(global.require("Editors.Shared.BaseEditMode").GetModeHelperEntity())
                mode:DebugSelectEntity(apis.placement:PlacementIDToEntityID(createdPart))
            end)
            for i=1,40 do global.coroutine.yield() end
            emit("qa:extras:select=" .. global.tostring(okSel) .. ";selectedPart=" .. global.tostring(world.SelectedPart()) .. ";rock=" .. global.tostring(createdPart))
            global.pcall(function() global.api.world.GetWorldAPIs().CameraModeManager:SetPosYPR(global.require("Vector3"):new(12,14,-6),global.require("Vector3"):new(0,0.6,0)) end)
        end
        emit("qa:extras-test:shown")
        for i=1,240 do global.coroutine.yield() end
        session._onNet("member:leave|777")
        emit("qa:extras-test:done")
    elseif command=="rejoin-test" then
        -- Main menu: pretends this game dropped out of a session whose host is online in PC2.
        local session=frontend and frontendCoop().Session()
        if not session then emit("qa:rejoin-test:not-in-frontend"); return end
        session._LastSession("109775240000000002|76561190000000001|Vici")
        for _,event in global.ipairs({"friends:begin|1","friend|76561190000000001|Vici|1|1","friends:end"}) do session._onNet(event) end
        local state=session.JoinState()
        emit("qa:rejoin-test:phase=" .. global.tostring(state and state.phase) .. ";host=" .. global.tostring(state and state.host))
    elseif command=="rejoin-go" then
        local session=frontend and frontendCoop().Session()
        if session then session.Rejoin() end
        emit("qa:rejoin-go:sent")
    elseif command=="viz-clean" then
        local shared=global.require("pc2coop.shared")
        local n=0
        for _,entity in global.ipairs(shared.vizEntities or {}) do
            if global.pcall(global.api.entity.DestroyEntity,entity) then n=n+1 end
        end
        shared.vizEntities=nil
        emit("qa:viz-clean:destroyed=" .. n)
    elseif command=="world-probe" then
        -- Research: time control, park numbers, undo checkpoint data, editor mode object.
        local world=global.require("pc2coop.world")
        local shared=global.require("pc2coop.shared")
        emit("qa:world:hud=" .. global.type(shared.hud))
        local paused,index=world.Time()
        emit("qa:world:time=" .. global.tostring(paused) .. "/" .. global.tostring(index))
        local seen={}
        shared.onTime=function(p,i) seen[#seen+1]=global.tostring(p) .. "/" .. global.tostring(i) end
        local okSet,failSet=world.SetTime(true,2)
        for i=1,20 do global.coroutine.yield() end
        local p2,i2=world.Time()
        emit("qa:world:set-time=" .. global.tostring(okSet) .. "/" .. global.tostring(failSet) .. ";now=" .. global.tostring(p2) .. "/" .. global.tostring(i2)
            .. ";echoed=" .. #seen)
        -- A change made through the HUD itself (as the player's button does) must be reported.
        global.pcall(function() shared.hud:ChangeSimulationSpeedSettings(false,nil) end)
        global.pcall(function() shared.hud:ChangeSimulationSpeedSettings(nil,1) end)
        for i=1,10 do global.coroutine.yield() end
        emit("qa:world:hud-change-reported=" .. global.table.concat(seen,","))
        shared.onTime=nil
        local numbers=world.Numbers()
        emit("qa:world:numbers=" .. (numbers and (global.tostring(numbers.guests) .. "/" .. global.tostring(numbers.cash) .. "/" .. global.tostring(numbers.unlimited)) or "nil"))
        local activity=world.Activity()
        emit("qa:world:mode=" .. global.tostring(activity.ui) .. "/" .. global.tostring(activity.edit) .. ";text=" .. global.tostring(activity.text)
            .. ";held=" .. global.tostring(activity.held ~= nil))
        local undo=global.api.undo
        local names={}
        for k,v in global.pairs(undo) do names[#names+1]=global.tostring(k) end
        global.table.sort(names)
        emit("qa:world:undo-api=" .. global.table.concat(names,","))
        global.pcall(function()
            undo.Checkpoint({pc2coopOwner="Vici"})
            local data=undo.GetCheckpointData()
            emit("qa:world:checkpoint-data=" .. global.type(data) .. "/" .. global.tostring(global.type(data)=="table" and data.pc2coopOwner))
            emit("qa:world:can-undo=" .. global.tostring(undo.CanUndo()))
        end)
        global.pcall(function()
            local env=global.api.world.GetScript(global.api.world.GetActive()).tEnvironment
            local sandbox=env:RequireInterface("Interfaces.ISandboxSettingsManager")
            local keys={}
            for k,v in global.pairs(sandbox:GetCurrentSandboxSettings() or {}) do
                if global.type(v)=="boolean" then keys[#keys+1]=global.tostring(k) .. "=" .. global.tostring(v) end
            end
            global.table.sort(keys)
            emit("qa:world:sandbox=" .. global.table.concat(keys,","))
        end)
        local notes={}
        shared.onNotification=function(text) notes[#notes+1]=text end
        for i=1,120 do global.coroutine.yield() end
        emit("qa:world:notifications=" .. #notes .. ";" .. global.string.sub(global.table.concat(notes," // "),1,400))
        shared.onNotification=nil
        emit("qa:world-probe:done")
    elseif command=="stale-invite-test" then
        -- Accepts an invite to a lobby that does not exist, like an old Steam invite.
        local session=frontend and frontendCoop().Session() or global.require("pc2coop.session")
        session._onNet("invite:accepted|109775240000000001|0|alt")
        emit("qa:stale-invite-test:sent")
    elseif command=="lobby-close" then
        if frontend then frontendCoop().Ui().SetOpen(false) else global.require("pc2coop.ui").SetOpen(false) end
        emit("qa:lobby-close:done")
    elseif command=="join-dismiss" then
        local session=frontend and frontendCoop().Session() or global.require("pc2coop.session")
        session.DismissJoin()
        emit("qa:join-dismiss:done")
    elseif command=="join-load-test" then
        -- Main menu only: opens pc2coop-join.bin/.trn next to the exe the way a join does.
        local session=frontend and frontendCoop().Session()
        if not session then emit("qa:join-load-test:rejected:not-in-frontend"); return end
        local ok,failure=session._LoadPark("temperateworld","PC2Coop-Test")
        emit("qa:join-load-test:requested=" .. global.tostring(ok) .. ";" .. global.tostring(failure))
    elseif command=="transfer-test" then
        -- Saves this park the way the host does for a joiner (pc2coop-host-qa.bin/.trn next
        -- to the exe). join-load-test opens such files from the main menu.
        local manager=global.api.game.GetEnvironment():RequireInterface("Interfaces.IParkLoadSaveManager")
        local okT=manager:SaveTerrainToFile("/run/pc2coop-host-qa.trn",true)
        local okP=manager:SaveParkToFile("/run/pc2coop-host-qa.bin",true,false)
        emit("qa:transfer-test:saved=" .. global.tostring(okT) .. "/" .. global.tostring(okP)
            .. ";world=" .. global.tostring(global.api.world.GetActive()))
    elseif command=="last-cmd" then
        emit("qa:last-cmd=" .. global.tostring(global.require("pc2coop.sync").Stats().lastCmd))
    elseif command=="sync-stats" then
        local s=global.require("pc2coop.sync").Stats()
        emit("qa:stats:cmdSent=" .. global.tostring(s.cmdSent) .. ";inbound=" .. global.tostring(s.inbound) .. ";lastSeq=" .. global.tostring(s.lastSeq) .. ";known=" .. global.tostring(s.known))
    elseif command=="recorder-on" then
        global.require("pc2coop.recorder").SetEnabled(true)
        emit("qa:recorder:on")
    elseif command=="lobby-test" then
        if frontend then frontendCoop().Ui().SetOpen(true) else global.require("pc2coop.ui").SetOpen(true) end
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
        -- Alex walks 12 m in steps of 4 m; the tag must glide, not jump.
        local tags={{name="Alex",activity="baut",x=10,y=9,z=10},{name="Sam",activity="schaut",x=16,y=9,z=10}}
        labels.Pin(tags)
        for i=1,180 do
            if i%45==0 then tags[1].x=tags[1].x+4 end
            global.coroutine.yield()
        end
        emit("qa:label-test:shown")
        for i=1,240 do global.coroutine.yield() end
        labels.Pin(nil)
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
