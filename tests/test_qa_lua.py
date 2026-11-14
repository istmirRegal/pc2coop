"""Local command gates and game-thread scheduling; no actual game or file IO."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime=None
SOURCE=Path(__file__).resolve().parents[1]/'probe/PC2CoopProbe/Main/pc2coop/qa.lua'

@unittest.skipIf(LuaRuntime is None,'Optional lupa.lua53 runtime is not installed')
class QATests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            messages={}; input=nil
            api={world={GetWorldAPIs=function() return {scenery={}} end,GetActive=function() return "frontend" end}}
            package.loadlib=function() return function() local r=input;input=nil;return r end end
            package.loaded["pc2coop.live"]={AuthorizeNewPark=function() end,Enqueue=function(s) liveMessage=s end}
        ''')
        qa=self.lua.eval('function(s) return assert(load(s,"qa","t",{_G=_G}))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().qa=qa
        self.lua.execute('''
            qa.Init(function(s) messages[#messages+1]=s end)
            manager={}; tick=function() for i=1,32 do qa.Tick(manager) end end
            function contains(s)
                for _,m in ipairs(messages) do if string.find(m,s,1,true) then return true end end
                return false
            end
        ''')

    def test_new_park_rejected_outside_frontend(self):
        self.lua.execute('''input="1|new-test-park";tick();assert(contains("rejected:not-in-frontend"))''')

    def test_creation_rejected_without_own_park_session(self):
        self.lua.execute('''input="1|create-test-rock";tick();assert(contains("rejected:not-own-test-park"))''')

    def prepare_fake_park(self):
        self.lua.execute('''
            local module={Init=function() end,Shutdown=function() end}
            qa.HookFrontend(module)
            local self={parkLoadSaveManager=manager,OnSandboxConfirmNewParkSetup=function() end}
            module.Init(self);input="1|new-test-park";tick();module.Shutdown(self)
            sampleCount=0;flipPosition=false
            local function vector(x,y,z)
                return {GetX=function() return x end,GetY=function() return y end,GetZ=function() return z end}
            end
            package.loaded.Vector3={new=function(_,x,y,z) return vector(x,y,z) end}
            package.loaded.Quaternion={Identity={}}
            package.loaded.TransformQ={FromOrPos=function(_,p) return p end}
            local edit={SetTransform=function() end,GetPosition=function() return vector(10,5,10) end}
            local hierarchy={CreateNewPart=function() return {} end,StartEditingPart_Scenery=function() return edit end,
                GetFullUndoChangeList=function() return {} end}
            local apis={park={GetParkName=function() return "PC2Coop-Test" end},
                editors={CreateUndoOperationsHierarchy=function() return hierarchy end},
                scenery={GetMoveObjectPartIDs=function() return {988} end},
                placement={HasPartsRequiringUpdate=function() return false end,
                    PlacementPartExists=function(_,id) assert(id==988);return true end,
                    GetPartResourceName=function() return "AQ_Rock_04" end,
                    PlacementIDToEntityID=function() return 12 end}}
            api.world.GetWorldAPIs=function() return apis end
            api.world.GetActive=function() return "temperateworld" end
            api.entity={CreateRequestCompletionToken=function() return 1 end,HaveRequestsCompleted=function() return true end}
            api.undo={IsBusy=function() return false end,IsPreviewingChangeList=function() return false end,
                PreviewChangeList=function() return 1,2 end,IsOperationComplete=function() return true end,
                CanCommitPreview=function() return true end,CommitPreview=function() return 3 end,Checkpoint=function() end}
            api.transform={GetPosition=function() error("Local entity position is not world position") end,CalculateWorldPosition=function()
                sampleCount=sampleCount+1
                return vector(flipPosition and sampleCount>1 and -10 or 10,5,10)
            end}
        ''')

    def test_create_requires_delayed_position_readback(self):
        self.prepare_fake_park()
        self.lua.execute('''
            input="2|create-test-rock";tick()
            assert(contains("qa:create:committed") and not contains("qa:verify:position-passed"))
            for i=1,250 do qa.Tick(manager) end
            assert(sampleCount>=6 and contains("qa:verify:position-passed"))
        ''')

    def test_delayed_coordinate_change_fails_verification(self):
        self.prepare_fake_park()
        self.lua.execute('''
            flipPosition=true;input="2|create-test-rock"
            for i=1,300 do qa.Tick(manager) end
            assert(contains("qa:task-error:") and contains("Test position mismatch"))
            assert(not contains("qa:verify:position-passed"))
        ''')

    def test_move_and_delete_require_own_park_session(self):
        self.lua.execute('''
            input="1|move-test-rock";tick();input="2|delete-test-rock";tick()
            assert(contains("qa:rejected:not-own-test-park"))
        ''')

    def test_save_and_reload_rejected_without_own_park_session(self):
        self.lua.execute('''
            input="1|save-test-park";tick();assert(contains("rejected:not-own-test-park"))
            input="2|reload-test-park";tick();assert(contains("rejected:no-completed-test-save"))
        ''')

    def test_new_park_calls_original_flow_with_fixed_parameters(self):
        self.lua.execute('''
            local module={Init=function() end,Shutdown=function() end}
            qa.HookFrontend(module)
            local self={parkLoadSaveManager=manager,
                OnSandboxConfirmNewParkSetup=function(self,preset,biome,difficulty,scenario)
                    assert(self.sNewParkName=="PC2Coop-Test" and preset==3 and biome=="Temperate")
                    assert(difficulty==nil and scenario==nil);requested=true
                end}
            module.Init(self);input="1|new-test-park";tick();assert(requested)
            module.Shutdown(self);input="2|new-test-park";tick()
            assert(contains("rejected:not-in-frontend"))
        ''')

    def test_malformed_and_unknown_commands_never_run_code(self):
        self.lua.execute('''
            input="1|inspect;error('execute')";tick();assert(#messages==0)
            input="2|execute";tick();assert(contains("rejected:unknown-command"))
            input="3|inspect";tick();assert(contains("world-api:scenery=table"))
        ''')

    def test_manager_hook_keeps_original_results(self):
        self.lua.execute('''
            local module={Advance=function(self,arg) assert(arg==7);return nil,42,nil end}
            qa.HookManager(module);local first=module.Advance;qa.HookManager(module)
            assert(module.Advance==first)
            local r=table.pack(module.Advance(manager,7))
            assert(r.n==3 and r[1]==nil and r[2]==42 and r[3]==nil)
        ''')

    def test_already_loaded_manager_gets_poll_loop(self):
        self.lua.execute('''
            local module={Advance=function() return 17 end}
            package.loaded["Managers.ParkLoadSaveManager"]=module
            qa.AttachLoaded();input="1|inspect"
            for i=1,32 do assert(module.Advance(manager)==17) end
            assert(contains("world-api:scenery=table"))
        ''')

    def test_frontend_run_polls_when_manager_preloaded_elsewhere(self):
        self.lua.execute('''
            local module={Init=function() end,Shutdown=function() end,Run=function() return 17 end}
            qa.HookFrontend(module)
            local self={parkLoadSaveManager=manager};module.Init(self)
            input="1|inspect"
            for i=1,32 do assert(module.Run(self)==17) end
            assert(contains("world-api:scenery=table"))
        ''')

if __name__=='__main__': unittest.main()
