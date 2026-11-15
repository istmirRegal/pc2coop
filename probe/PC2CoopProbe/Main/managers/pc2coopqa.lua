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
                    -- "AQ_Rock_04" reads better as "Rock 04"
                    local what=hold and global.string.gsub(global.string.gsub(hold.label,"^%w+_",""),"_"," ")
                    tags[#tags+1]={key=p.sid,name=p.name,activity=hold and ("h\195\164lt " .. what) or act,
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
        self.labels.Show(tags,delta)
        self.viz.Update(remote,locked,colour,delta)
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
