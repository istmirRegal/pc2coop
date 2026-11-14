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
    self.session.Init(function(message) self.diagnostic.Write("[PC2CoopSession] " .. message) end,
        self.diagnostic, self.sync, self.parkManager)
    self.labels=global.require("pc2coop.labels")
    self.labels.Init(function(message) self.diagnostic.Write("[PC2CoopLabels] " .. message) end)
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
    -- Name tags of the other players, refreshed a few times per second.
    self.labelFrames=self.labelFrames+1
    if self.labelFrames%10==0 then
        global.pcall(function()
            local view=self.session.View()
            if not view.role or not self.menu.labelsEnabled then return end
            local tags={}
            for _,p in global.pairs(view.players) do
                if p.sid~=view.me and p.x and p.act~="-" then
                    tags[#tags+1]={name=p.name,activity=p.act,x=p.x,y=p.y,z=p.z}
                end
            end
            self.labels.Show(tags)
        end)
    end
end

Manager.Shutdown=function(self)
    self.diagnostic.Write("[PC2CoopQA] park-manager-shutdown")
    self.parkManager=nil
    self.live.Stop()
    self.sync.Stop()
    global.pcall(self.labels.Clear)
    global.pcall(self.menu.Shutdown)
    global.pcall(self.ui.Shutdown)
end

Mutators.VerifyManagerModule(Manager)
