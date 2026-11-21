-- Original MIT code. ACSE manager lifecycle for the actual park environment.
local global=_G
local Mutators=global.require("Environment.ModuleMutators")
local Manager=global.module(...,Mutators.Manager())

Manager.Init=function(self,properties,environment)
    self.environment=environment
    self.parkManager=environment:RequireInterface("Interfaces.IParkLoadSaveManager")
    self.qa=global.require("pc2coop.qa")
    self.diagnostic=global.require("pc2coop.diagnostic")
    self.live=global.require("pc2coop.live")
    self.live.Init(function(message) self.diagnostic.Write("[PC2CoopLive] " .. message) end)
    -- Park managers receive a fresh Lua module instance after frontend transition.
    -- The separate QA.IsOwnTestPark gate still requires this session's new testpark.
    self.live.AuthorizeNewPark()
    self.qa.Init(function(message) self.diagnostic.Write("[PC2CoopQA] " .. message) end)
    self.sync=global.require("pc2coop.sync")
    -- Labels at objects in the player's language (ADR-022); German if the module is missing.
    local okLang,lang=global.pcall(global.require,"pc2coop.lang")
    self.lang=okLang and global.type(lang)=="table" and lang or {World=function(text) return text end}
    self.session=global.require("pc2coop.session")
    self.sync.Init(function(message)
        -- Camera presence is frequent; it goes to the session only, not into the log.
        if global.string.sub(message,1,10)~="sync:pres|" and global.string.sub(message,1,9)~="sync:cmd|" then
            self.diagnostic.Write("[PC2CoopSync] " .. message)
        end
        global.pcall(self.session.OnSyncLine, message)
    end)
    self.session.SetContext("park")
    self.session.Init(function(message) self.diagnostic.Write("[PC2CoopSession] " .. message) end,
        self.diagnostic, self.sync, self.parkManager)
    self.labels=global.require("pc2coop.labels")
    self.labels.Init(function(message) self.diagnostic.Write("[PC2CoopLabels] " .. message) end)
    self.viz=global.require("pc2coop.viz")
    self.viz.Init(function(message) self.diagnostic.Write("[PC2CoopViz] " .. message) end)
    global.pcall(self.viz.Clear)
    self.labelFrames=0
    self.recorder=global.require("pc2coop.recorder")
    self.recorder.Init(function(message) self.diagnostic.Write("[PC2CoopRec] " .. message) end)
    self.menu=global.require("pc2coop.menu")
    self.menu.Init(function(message) self.diagnostic.Write("[PC2CoopMenu] " .. message) end,
        environment, self.session, self.sync, self.labels)
    self.ui=global.require("pc2coop.ui")
    self.ui.Init(function(message) self.diagnostic.Write("[PC2CoopUI] " .. message) end, self.session, self.sync, self.menu)
    -- F7: multiplayer window inside the HUD; F8: developer dialog.
    self.session.OnMenuKey=function() self.ui.Toggle() end
    self.session.OnDevKey=function() self.menu.Toggle() end
    -- Enter: chat input bottom left (the UI decides whether it opens).
    self.session.OnChatKey=function() self.ui.ChatKey() end
    self.diagnostic.Write("[PC2CoopQA] park-manager-init")
end

Manager.Advance=function(self,delta)
    local ok,failure=global.pcall(self.qa.Tick,self.parkManager)
    if not ok then self.diagnostic.Write("[PC2CoopQA] tick-error:" .. global.tostring(failure)) end
    ok,failure=global.pcall(self.live.Tick,self.qa.IsOwnTestPark())
    if not ok then self.diagnostic.Write("[PC2CoopLive] live:tick-error:" .. global.tostring(failure)) end
    ok,failure=global.pcall(self.sync.Tick)
    if not ok then self.diagnostic.Write("[PC2CoopSync] sync:tick-error|" .. global.tostring(failure)) end
    ok,failure=global.pcall(self.session.Tick)
    if not ok then self.diagnostic.Write("[PC2CoopSession] session:tick-error|" .. global.tostring(failure)) end
    global.pcall(self.ui.Tick)
    -- The other players in the park: name tag, ground marker, view wedge, ghost of what
    -- they hold, tint on what they edit. Eased every frame.
    global.pcall(function()
        local view=self.session.View()
        local tags,remote,locked={}, {}, {}
        local colour=nil
        if view.role and self.menu.labelsEnabled then
            local placement=global.api.world.GetWorldAPIs().placement
            for _,p in global.pairs(view.players) do
                local act=global.tostring(p.act or "-")
                local joining=act=="-" or act=="laedt" or global.string.sub(act,1,4)=="holt"
                if p.sid~=view.me and (p.fx or p.x) and not joining then
                    local hold=p.hold
                    local at=hold and hold.items and hold.items[1]
                    -- Only the name in the player's colour (TP-14); what they do is in the
                    -- player bar's tooltip and in the window.
                    tags[#tags+1]={key=p.sid,name=p.name,activity="",color=p.color,
                        x=at and at.x or p.fx or p.x,y=(at and at.y or p.fy or p.y)+3,z=at and at.z or p.fz or p.z}
                    remote[#remote+1]=p
                    colour=colour==nil and p.color or "ffa94d"
                    for gid in global.string.gmatch(hold and hold.gids or "","[^,]+") do
                        local part=self.sync.LocalPart(gid)
                        if part and placement:PlacementPartExists(part) then locked[placement:PlacementIDToEntityID(part)]=true end
                    end
                end
            end
        end
        -- Pings: a tag above each beacon.
        local pings,names={}, {}
        for _,p in global.pairs(view.players or {}) do names[p.sid]=p end
        if view.role then
            for _,ping in global.ipairs(self.session.Pings()) do
                local who=names[ping.sid]
                if who then
                    -- A mark on an object: that object is outlined (viz.lua), the tag stands above it.
                    local lx,ly,lz=ping.x,ping.y+3,ping.z
                    if ping.gid then
                        local okE,entity=global.pcall(self.sync.GidToEntity,ping.gid)
                        ping.entity=okE and entity or nil
                        local okP,at=global.pcall(function() return global.api.transform.CalculateWorldPosition(ping.entity) end)
                        if ping.entity and okP and at then lx,ly,lz=at:GetX(),at:GetY()+3,at:GetZ() end
                    end
                    pings[#pings+1]=ping
                    tags[#tags+1]={key="ping:" .. ping.sid,name=who.name,activity=self.lang.World("hier!"),color=who.color,x=lx,y=ly,z=lz}
                    colour=colour or who.color
                end
            end
        end
        -- Team board and park events: a beacon and a label each (the nearest 15 within 300 m).
        if view.role then
            local cam=global.api.world.GetWorldAPIs().CameraModeManager
            local okC,camPos=global.pcall(function() return cam:GetPosYPRZoom() end)
            local near={}
            local words={area="Baugebiet",task="Aufgabe",comment="Kommentar",meet="Treffpunkt"}
            for _,item in global.ipairs(view.board or {}) do
                if item.x and item.x~=false and not (item.kind=="task" and item.done) then
                    local d=okC and camPos and ((item.x-camPos:GetX())^2+(item.z-camPos:GetZ())^2) or 0
                    if d<90000 then near[#near+1]={d=d,item=item} end
                end
            end
            global.table.sort(near,function(a,b) return a.d<b.d end)
            for i=1,global.math.min(15,#near) do
                local item=near[i].item
                pings[#pings+1]={sid="board:" .. item.id,x=item.x,y=item.y,z=item.z,age=0,radius=item.kind=="area" and item.radius or nil}
                local what=self.lang.World(words[item.kind] or "")
                if item.assignee and item.assignee~="" then what=what .. " - " .. item.assignee end
                tags[#tags+1]={key="board:" .. item.id,name=item.title,activity=what,x=item.x,y=item.y+9,z=item.z}
            end
            for i,e in global.ipairs(view.events or {}) do
                pings[#pings+1]={sid="event:" .. i,x=e.x,y=e.y,z=e.z,age=e.age}
                tags[#tags+1]={key="event:" .. i,name=self.lang.World(e.label or "Meldung"),activity=self.lang.World("Meldung des Parks"),x=e.x,y=e.y+12,z=e.z}
            end
        end
        -- Author of what the local player selects or holds.
        self.authorFrames=(self.authorFrames or 0)+1
        if view.role and self.authorFrames%10==0 then
            local world=global.require("pc2coop.world")
            local part=world.SelectedPart()
            if not part then for held in global.pairs(self.sync.HeldParts()) do part=held; break end end
            local gid=part and self.sync.GidOfPart(part)
            local who=self.session.Attribution(gid)
            self.authorTag=nil
            if gid and who and (who.creator~="" or who.last~="") then
                local text
                if who.creator~="" and who.creator~="Park" then
                    text="Erstellt von " .. who.creator
                    if who.last~="" and who.last~=who.creator then text=text .. ", zuletzt " .. who.last end
                elseif who.last~="" and who.last~="Park" then
                    text="Zuletzt bearbeitet von " .. who.last
                end
                local placement=global.api.world.GetWorldAPIs().placement
                if text and placement:PlacementPartExists(part) then
                    local at=global.api.transform.CalculateWorldPosition(placement:PlacementIDToEntityID(part))
                    self.authorTag={key="author",name=self.lang.World(text),activity="",x=at:GetX(),y=at:GetY()+2.5,z=at:GetZ()}
                end
            end
        end
        if self.authorTag then tags[#tags+1]=self.authorTag end
        -- Refused changes (TP-16): a line at the object, which flashes in the other
        -- player's colour for the first two seconds.
        if view.role and self.session.Conflicts then
            for _,c in global.ipairs(self.session.Conflicts()) do
                local entity=self.sync.GidToEntity(c.gid)
                if entity then
                    local at=global.api.transform.CalculateWorldPosition(entity)
                    tags[#tags+1]={key="conflict:" .. c.gid,name=self.lang.World(c.text),activity="",color=c.color,x=at:GetX(),y=at:GetY()+4,z=at:GetZ()}
                    if c.age<0.4 then
                        locked[entity]=global.math.floor(c.age*20)%2==0 or nil
                        colour=c.color or "ff922b"
                    end
                end
            end
        end
        self.labels.Show(tags,delta)
        self.viz.Update(remote,locked,colour,delta,pings)
        -- Follow another player's camera until the player moves it.
        local target=self.session.Following()
        if target then
            local world=global.require("pc2coop.world")
            local p=names[target]
            if not p or not p.x or not view.role then
                self.session.SetFollow(nil)
            elseif world.PlayerMovesCamera() then
                self.session.SetFollow(nil)
                self.session.Notice("Du folgst " .. p.name .. " nicht mehr.")
            else
                local x,y,z,yaw,pitch=world.Camera()
                if x then
                    local k=1-global.math.exp(-(delta or 1/60)*5)
                    local turn=((p.yaw or yaw)-yaw+global.math.pi)%(2*global.math.pi)-global.math.pi
                    world.SetCamera(x+(p.x-x)*k,y+(p.y-y)*k,z+(p.z-z)*k,yaw+turn*k,pitch+((p.pitch or pitch)-pitch)*k)
                end
            end
        end
    end)
end

Manager.Shutdown=function(self)
    self.diagnostic.Write("[PC2CoopQA] park-manager-shutdown")
    self.parkManager=nil
    self.live.Stop()
    self.sync.Stop()
    global.pcall(self.labels.Clear)
    global.pcall(self.viz.Clear)
    global.pcall(self.menu.Shutdown)
    global.pcall(self.ui.Shutdown)
end

Mutators.VerifyManagerModule(Manager)
