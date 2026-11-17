"""ui.lua: the multiplayer window opens and closes in the main menu and in a park; the host in
the main-menu lobby gets the park list and can pick and open a park."""
from pathlib import Path
import json
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/ui.lua'

FAKES = r"""
store = {}
api = {ui2 = {
    GetDataStoreContext = function() return nil end,
    CreateDataStoreContext = function(values, name) return name end,
    SetDataStoreElement = function(ctx, key, value) store[key] = value end,
    RequestRegisterForEvent = function() end}}
view = {role = nil, stage = nil, players = {}, me = "100"}
calls = {list = 0, load = {}, new = {}, choice = {}}
session = {
    View = function() return view end, Available = function() return true end, RefreshFriends = function() end,
    Friends = function() return {} end, JoinState = function() return nil end, Desync = function() return nil end,
    Requests = function() return {} end, Following = function() return nil end, Chat = function() return {} end,
    Toasts = function() return {} end, Avatars = function() return {} end, Notice = function() end,
    SetChoice = function(kind, title, detail) calls.choice[#calls.choice+1] = tostring(kind) .. "|" .. tostring(title) .. "|" .. tostring(detail) end,
    MarkStarting = function() calls.starting = true end}
package.preload["pc2coop.parks"] = function() return {
    List = function(manager) calls.list = calls.list + 1; return {{id = "1", name = "Talpark", world = "Taiga", time = 0}} end,
    Load = function(manager, id) calls.load[#calls.load+1] = id; return true end,
    New = function(menu, biome, creative, name) calls.new[#calls.new+1] = biome .. "|" .. tostring(creative); return true end} end
menuHud = {parkLoadSaveManager = {}}
logs = {}
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class UiTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.ui = self.lua.eval('function(s) return assert(load(s, "ui", "t", _G))() end')(SOURCE.read_text(encoding='utf8'))
        self.lua.globals().ui = self.ui
        self.lua.execute('ui.Init(function(m) logs[#logs+1] = m end, session, {}, nil)')

    def state(self):
        self.lua.execute('ui.Tick()')
        return json.loads(self.lua.eval('store.state'))

    def open_close_open(self):
        self.lua.execute('ui.SetOpen(true)')
        self.assertTrue(self.state()['open'])
        self.lua.execute('ui.SetOpen(false)')
        self.assertFalse(self.state()['open'])
        self.lua.execute('ui.SetOpen(true)')
        self.assertTrue(self.state()['open'])

    def test_host_in_the_menu_lobby_gets_the_park_list(self):
        self.lua.execute('ui.SetFrontend(menuHud); view.role, view.stage = "host", "lobby"')
        self.open_close_open()
        self.assertEqual(self.lua.eval('calls.list'), 2)
        state = self.state()
        self.assertTrue(state['canChoose'])
        self.assertEqual(state['parks'][0]['name'], 'Talpark')

    def test_guest_in_the_menu_and_everyone_in_a_park_get_no_park_list(self):
        self.lua.execute('ui.SetFrontend(menuHud); view.role, view.stage = "client", "lobby"')
        self.open_close_open()
        self.lua.execute('ui.SetFrontend(nil); view.role, view.stage = "host", "park"')
        self.open_close_open()
        self.lua.execute('view.role, view.stage = nil, nil')
        self.open_close_open()
        self.assertEqual(self.lua.eval('calls.list'), 0)
        self.assertFalse(self.state()['canChoose'])

    def test_host_picks_and_opens_a_park(self):
        self.lua.execute('ui.SetFrontend(menuHud); view.role, view.stage = "host", "lobby"; ui.SetOpen(true)')
        self.lua.execute('ui._Request("1|choose|save|1")')
        self.assertEqual(list(self.lua.eval('calls.choice').values()), ['save|Talpark|Gespeicherter Park - Taiga'])
        self.lua.execute('ui._Request("2|start|")')
        self.assertEqual(list(self.lua.eval('calls.load').values()), ['1'])
        self.assertTrue(self.lua.eval('calls.starting'))
        self.assertFalse(self.state()['open'])
        self.lua.execute('ui.SetOpen(true); ui._Request("3|choose|new|Tropical|0"); ui._Request("4|start|")')
        self.assertEqual(list(self.lua.eval('calls.new').values()), ['Tropical|false'])
        self.lua.execute('ui._Request("5|choose|new|Moon|1")')       # unknown biome: nothing picked
        self.assertEqual(len(self.lua.eval('calls.choice')), 2)

    def test_guests_cannot_pick_or_start(self):
        self.lua.execute('ui.SetFrontend(menuHud); view.role, view.stage = "client", "lobby"')
        self.lua.execute('ui._Request("1|choose|save|1"); ui._Request("2|start|")')
        self.assertEqual(len(self.lua.eval('calls.choice')), 0)
        self.assertEqual(len(self.lua.eval('calls.load')), 0)


if __name__ == '__main__':
    unittest.main()
