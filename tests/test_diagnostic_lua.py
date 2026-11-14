"""Exercise the byte channel with Lua-side loader failures and binary strings."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None
SOURCE = Path(__file__).resolve().parents[1]/'probe/PC2CoopProbe/Main/pc2coop/diagnostic.lua'

@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            records={}; loads=0; bootstraps=0; pending={}
            package.loadlib=function(path,name)
                loads=loads+1
                if name==missing then return nil,"missing export" end
                if name=="pc2_bootstrap" then return function() bootstraps=bootstraps+1 end end
                if name=="pc2_log_begin" then return function() pending={} end end
                if name=="pc2_log_end" then return function()
                    local s=""
                    for i=1,#pending,2 do s=s..string.char(pending[i]*16+pending[i+1]) end
                    records[#records+1]=s
                end end
                local digit=tonumber(string.sub(name,-1),16)
                return function() pending[#pending+1]=digit end
            end
        ''')
        self.module = self.lua.eval('function(s) return assert(load(s,"diag","t",{_G=_G}))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().diag = self.module

    def test_binary_strings_and_limit_roundtrip(self):
        self.lua.execute('''
            assert(diag.Init())
            local s=""; for n=0,255 do s=s..string.char(n) end
            diag.Write(s); assert(records[1]==s)
            diag.Write(""); assert(records[2]=="")
            diag.Write(string.rep("x",5000)); assert(#records[3]==4096)
            assert(diag.Init() and bootstraps==1 and loads==21)
        ''')

    def test_missing_export_disables_channel(self):
        self.lua.execute('''
            missing="pc2_nibble_b"
            assert(not diag.Init() and not diag.ready)
            diag.Write("no partial record"); assert(#records==0 and bootstraps==0)
        ''')

if __name__ == '__main__': unittest.main()
