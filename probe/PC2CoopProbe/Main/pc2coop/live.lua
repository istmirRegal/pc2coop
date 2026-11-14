-- Original MIT code. Narrow scenery-only LAN alpha, game-thread operations only.
local global=_G
local Live={}
local objects={}
local lastSequence=0
local lastMessage
local pending
local task
local authorized=false
local ready=false
local emit=function() end

function Live.Init(logger) emit=logger end
function Live.Stop()
    authorized=false;ready=false;pending=nil;task=nil
    emit("live:not-ready")
end
function Live.AuthorizeNewPark()
    objects={};lastSequence=0;lastMessage=nil;pending=nil;task=nil
    authorized=true;ready=false
end
function Live.Enqueue(message)
    if pending or task then emit("live:protocol-error:busy");return end
    pending=message
end

local function waitFor(predicate,label)
    for i=1,1800 do
        if predicate() then return end
        global.coroutine.yield()
    end
    global.error("timeout-" .. label)
end
local function commit(apis,hierarchy)
    local undo=global.api.undo
    local wait,preview=undo.PreviewChangeList(hierarchy:GetFullUndoChangeList())
    waitFor(function() return undo.IsOperationComplete(wait) end,"preview")
    waitFor(function() return not apis.placement:HasPartsRequiringUpdate() end,"placement")
    local valid
    waitFor(function() valid=undo.CanCommitPreview(preview);return valid~=nil end,"validation")
    if valid~=true then
        wait=undo.CancelPreview(preview)
        waitFor(function() return undo.IsOperationComplete(wait) end,"cancel")
        global.error("invalid-placement")
    end
    wait=undo.CommitPreview(preview)
    waitFor(function() return undo.IsOperationComplete(wait) end,"commit")
    undo.Checkpoint({})
    for i=1,3 do global.coroutine.yield() end
end
local function position(edit,x,y,z)
    edit:SetTransform(global.require("TransformQ").FromOrPos(global.require("Quaternion").Identity,
        global.require("Vector3"):new(x,y,z)))
end
local function apply(apis,op,id,x,y,z)
    local api=global.api
    global.assert(not api.undo.IsBusy() and not api.undo.IsPreviewingChangeList(),"editor-busy")
    local hierarchy=apis.editors:CreateUndoOperationsHierarchy()
    local part=objects[id]
    if op=="create" then
        global.assert(not part,"object-already-exists")
        local token=api.entity.CreateRequestCompletionToken()
        local object=hierarchy:CreateNewPart("AQ_Rock_04",token)
        waitFor(function() return api.entity.HaveRequestsCompleted(token) end,"create")
        local edit=hierarchy:StartEditingPart_Scenery(object)
        position(edit,x,y,z)
        local ids=apis.scenery:GetMoveObjectPartIDs(edit)
        global.assert(global.type(ids)=="table" and #ids==1,"unexpected-part-count")
        part=ids[1]
    elseif op=="move" then
        global.assert(part and apis.placement:PlacementPartExists(part),"object-missing")
        local token=api.entity.CreateRequestCompletionToken()
        local object=hierarchy:EditExistingPart(part,nil,token)
        waitFor(function() return api.entity.HaveRequestsCompleted(token) end,"edit")
        position(hierarchy:StartEditingPart_Scenery(object),x,y,z)
    elseif op=="delete" then
        global.assert(part and apis.placement:PlacementPartExists(part),"object-missing")
        local selection=apis.scenery:CreateBuildingPartSet();selection:Add(part)
        local edits=hierarchy:StartEditingParts_Scenery(hierarchy:DestroyExistingParts(selection))
        global.assert(#edits==1,"unexpected-delete-count");edits[1]:Destroy()
    else global.error("unsupported-operation") end
    commit(apis,hierarchy)
    if op=="delete" then
        global.assert(not apis.placement:PlacementPartExists(part),"delete-readback-failed")
        objects[id]=nil
    else
        global.assert(apis.placement:PlacementPartExists(part),"create-readback-failed")
        global.assert(apis.placement:GetPartResourceName(part)=="AQ_Rock_04","resource-mismatch")
        local entity=apis.placement:PlacementIDToEntityID(part)
        local p=api.transform.CalculateWorldPosition(entity)
        global.assert(global.math.abs(p:GetX()-x)<0.01 and global.math.abs(p:GetY()-y)<0.01
            and global.math.abs(p:GetZ()-z)<0.01,"world-position-mismatch")
        objects[id]=part
    end
end

function Live.Tick(ownPark)
    if not authorized or not ownPark then
        if ready then emit("live:not-ready");ready=false end
        return
    end
    local apis=global.api.world.GetWorldAPIs()
    if not ready then emit("live:ready");ready=true end
    if task then
        local ok,error=global.coroutine.resume(task)
        if not ok then
            emit("live:ack:" .. global.tostring(lastSequence+1) .. ":error:" .. global.tostring(error))
            task=nil;authorized=false;ready=false
        elseif global.coroutine.status(task)=="dead" then task=nil end
        return
    end
    if not pending then return end
    local message=pending;pending=nil
    local request,sequence,op,id,sx,sy,sz=global.string.match(message,
        "^(%d+)|live|(%d+)|([a-z]+)|([%w:_%-]+)|([^|]+)|([^|]+)|([^|]+)$")
    sequence=global.tonumber(sequence)
    local x,y,z=global.tonumber(sx),global.tonumber(sy),global.tonumber(sz)
    if not request or not sequence or sequence%1~=0 or #id>64 or not x or not y or not z
        or x~=x or y~=y or z~=z or global.math.abs(x)>10000 or global.math.abs(y)>10000
        or global.math.abs(z)>10000 or (op~="create" and op~="move" and op~="delete") then
        emit("live:protocol-error:invalid-command");return
    end
    local payload=global.string.match(message,"^%d+|(.+)$")
    if sequence==lastSequence and payload==lastMessage then
        emit("live:ack:" .. global.tostring(sequence) .. ":ok");return
    end
    if sequence~=lastSequence+1 then emit("live:ack:" .. global.tostring(sequence) .. ":error:sequence-gap");return end
    task=global.coroutine.create(function()
        apply(apis,op,id,x,y,z)
        lastSequence=sequence;lastMessage=payload
        emit("live:ack:" .. global.tostring(sequence) .. ":ok")
    end)
end
return Live
