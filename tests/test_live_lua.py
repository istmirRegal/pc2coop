"""Game-thread protocol tests with fake engine APIs, not a PC2 multiplayer proof."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime=None
SOURCE=Path(__file__).resolve().parents[1]/'probe/PC2CoopProbe/Main/pc2coop/live.lua'

@unittest.skipIf(LuaRuntime is None,'Optional Lua 5.3 missing')
class LiveLuaTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        module=self.lua.eval('function(s) return assert(load(s,"live","t",{_G=_G}))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().live=module
        self.lua.execute('''
            messages={};live.Init(function(s) messages[#messages+1]=s end)
            function contains(s) for _,m in ipairs(messages) do if m:find(s,1,true) then return true end end return false end
            function advance(n) for i=1,n do live.Tick(true) end end
            function vector(x,y,z) return {GetX=function() return x end,GetY=function() return y end,GetZ=function() return z end} end
            current=vector(0,0,0);exists=false;creates=0
            local edit={SetTransform=function(_,p) current=p end,Destroy=function() exists=false end}
            local hierarchy={CreateNewPart=function(_,r) assert(r=="AQ_Rock_04");exists=true;creates=creates+1;return {} end,
                StartEditingPart_Scenery=function() return edit end,GetFullUndoChangeList=function() return {} end,
                EditExistingPart=function(_,part) assert(part==77);return {} end,
                DestroyExistingParts=function() return {} end,StartEditingParts_Scenery=function() return {edit} end}
            local apis={editors={CreateUndoOperationsHierarchy=function() return hierarchy end},
                scenery={GetMoveObjectPartIDs=function() return {77} end,CreateBuildingPartSet=function() return {Add=function() end} end},
                placement={HasPartsRequiringUpdate=function() return false end,PlacementPartExists=function() return exists end,
                    GetPartResourceName=function() return "AQ_Rock_04" end,PlacementIDToEntityID=function() return 99 end}}
            api={world={GetWorldAPIs=function() return apis end},
                entity={CreateRequestCompletionToken=function() return 1 end,HaveRequestsCompleted=function() return true end},
                undo={IsBusy=function() return false end,IsPreviewingChangeList=function() return false end,
                    PreviewChangeList=function() return 1,2 end,IsOperationComplete=function() return true end,
                    CanCommitPreview=function() return true end,CommitPreview=function() return 1 end,Checkpoint=function() end},
                transform={CalculateWorldPosition=function() return current end,GetPosition=function() error("local position forbidden") end}}
            package.loaded.Vector3={new=function(_,x,y,z) return vector(x,y,z) end}
            package.loaded.Quaternion={Identity={}}
            package.loaded.TransformQ={FromOrPos=function(_,p) return p end}
        ''')

    def test_requires_explicit_new_testpark_authorization(self):
        self.lua.execute('''live.Enqueue("1|live|1|create|p1:1|1|5|3");advance(30);assert(creates==0 and not contains("live:ready"))''')

    def test_create_move_delete_readback_and_order(self):
        self.lua.execute('''
            live.AuthorizeNewPark();advance(1);assert(contains("live:ready"))
            live.Enqueue("1|live|1|create|p1:1|10|5|10");advance(30);assert(contains("live:ack:1:ok"))
            live.Enqueue("2|live|2|move|p1:1|20|5|15");advance(30);assert(contains("live:ack:2:ok"))
            live.Enqueue("3|live|3|delete|p1:1|0|0|0");advance(30);assert(contains("live:ack:3:ok") and not exists)
        ''')

    def test_repeated_event_does_not_create_twice(self):
        self.lua.execute('''
            live.AuthorizeNewPark();live.Enqueue("1|live|1|create|p1:1|10|5|10");advance(30)
            live.Enqueue("2|live|1|create|p1:1|10|5|10");advance(30);assert(creates==1)
        ''')

    def test_gap_rejected_before_engine_calls(self):
        self.lua.execute('''live.AuthorizeNewPark();live.Enqueue("1|live|2|create|p1:1|10|5|10");advance(30);assert(creates==0 and contains("sequence-gap"))''')

    def test_invalid_numeric_and_lua_text_rejected(self):
        self.lua.execute('''
            live.AuthorizeNewPark();live.Enqueue("1|live|1|create|p1:1|1e999|5|10");advance(30)
            live.Enqueue("2|live|1|create|p1:1|error('bad')|5|10");advance(30)
            assert(creates==0 and contains("invalid-command"))
        ''')

    def test_world_readback_failure_disables_operations(self):
        self.lua.execute('''
            live.AuthorizeNewPark();api.transform.CalculateWorldPosition=function() return vector(-10,5,10) end
            live.Enqueue("1|live|1|create|p1:1|10|5|10");advance(30)
            assert(contains("world-position-mismatch") and not contains("live:ack:1:ok"))
            live.Enqueue("2|live|1|create|p1:2|10|5|10");advance(30);assert(creates==1)
        ''')

    def test_shutdown_clears_pending_commands(self):
        self.lua.execute('''
            live.AuthorizeNewPark();live.Enqueue("1|live|1|create|p1:1|10|5|10");live.Stop();advance(30)
            assert(creates==0 and contains("live:not-ready"))
        ''')

if __name__=='__main__':unittest.main()
