"""Hook contract tests: real Lua coroutines, errors, nil and inherited methods."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1]/'probe/PC2CoopProbe/Main/pc2coop/capture.lua'

@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.capture = self.lua.eval('function(s) return assert(load(s,"capture","t",{_G=_G}))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().capture = self.capture

    def test_yield_and_all_returns_preserved_and_emitted_only_after_completion(self):
        self.lua.execute('''
            records={}
            local m={CommitPreview=function(self,arg)
                assert(arg==42); coroutine.yield("waiting"); self.moveObject=nil
                return nil,"done",nil,7
            end}
            capture.Install(m,function(s) records[#records+1]=s end)
            local self={sPropToMake="test-rock",previewToken=17,
                moveObject={GetPosition=function() return "(1,2,3)" end},
                sceneryAPI={GetMoveObjectPartIDs=function() return {123,124} end}}
            local c=coroutine.create(function() return m.CommitPreview(self,42) end)
            local ok,wait=coroutine.resume(c)
            assert(ok and wait=="waiting" and #records==1)
            local r=table.pack(coroutine.resume(c))
            assert(r.n==5 and r[1] and r[2]==nil and r[3]=="done" and r[4]==nil and r[5]==7)
            assert(#records==2 and string.find(records[2],"resource=test%-rock"))
            assert(string.find(records[2],"part1=123"))
        ''')

    def test_failed_original_never_emits_commit(self):
        self.lua.execute('''
            records={}; local m={CommitPreview=function() error("engine-failed") end}
            capture.Install(m,function(s) records[#records+1]=s end)
            local ok,err=pcall(m.CommitPreview,{})
            assert(not ok and string.find(err,"engine%-failed") and #records==1)
        ''')

    def test_bad_snapshot_and_bad_logger_cannot_break_editor(self):
        self.lua.execute('''
            local m={CommitPreview=function() return "ok" end}
            capture.Install(m,function(s)
                if string.find(s,"commit%-complete") then error("disk-failed") end
            end)
            assert(m.CommitPreview({moveObject={}})=="ok")
        ''')

    def test_inherited_method_is_wrapped_once(self):
        self.lua.execute('''
            local parent={CommitPreview=function() return "ok" end}
            local child=setmetatable({},{__index=parent})
            local calls=0; local emit=function() calls=calls+1 end
            capture.Install(child,emit); local first=child.CommitPreview
            capture.Install(child,emit)
            assert(first==child.CommitPreview and first~=parent.CommitPreview and calls==1)
            assert(child.CommitPreview({})=="ok" and calls==2)
        ''')

    def test_move_reports_kind_rotation_and_scale(self):
        self.lua.execute('''
            records={}; local m={CommitPreview=function() return "ok" end}
            capture.Install(m,function(s) records[#records+1]=s end)
            local self={sPropToMake="fern",
                editorContext={IsMove=function() return true end,IsClone=function() return false end,
                    IsCreate=function() return false end},
                moveObject={GetPosition=function() return "(1,2,3)" end,
                    GetQuaternion=function() return "(0,0.7,0,0.7)" end,
                    GetScale=function() error("no-scale") end},
                sceneryAPI={GetMoveObjectPartIDs=function() return {5} end}}
            assert(m.CommitPreview(self)=="ok")
            local r=records[2]
            assert(string.find(r,"kind=move",1,true) and string.find(r,"rotation=(0,0.7,0,0.7)",1,true))
            assert(string.find(r,"scale=<error>",1,true) and string.find(r,"part1=5",1,true))
        ''')

    def test_delete_reads_selection_before_and_existence_after(self):
        self.lua.execute('''
            records={}; local present={[7]=true,[8]=true}
            local m={_DeleteSelection=function(self) coroutine.yield(); present[7]=nil; return "done" end}
            capture.InstallSelect(m,function(s) records[#records+1]=s end)
            local self={editorContext={GetSelectionSet=function() return
                    {GetPartIDCollection=function() return {7,8} end} end},
                placementAPI={GetPartResourceName=function(_,id) return "res"..id end,
                    PlacementPartExists=function(_,id) return present[id]==true end}}
            local c=coroutine.create(function() return m._DeleteSelection(self) end)
            assert(coroutine.resume(c)) assert(#records==1)
            local ok,v=coroutine.resume(c); assert(ok and v=="done")
            local r=records[2]
            assert(string.find(r,"total=2",1,true) and string.find(r,"part1=7,res7,exists=false",1,true))
            assert(string.find(r,"part2=8,res8,exists=true",1,true))
        ''')

    def test_delete_with_empty_selection_emits_nothing(self):
        self.lua.execute('''
            records={}; local m={_DeleteSelection=function() end}
            capture.InstallSelect(m,function(s) records[#records+1]=s end)
            m._DeleteSelection({editorContext={GetSelectionSet=function() return
                {GetPartIDCollection=function() return {} end} end}})
            assert(#records==1)
        ''')

if __name__ == '__main__': unittest.main()
