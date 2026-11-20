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
    MarkStarting = function() calls.starting = true end,
    Ratings = function() return {F1_0_2 = {avg = 4.5, count = 2, mine = 5, comments = {{who = "Vici", stars = 4, text = "mehr Schatten"}}}} end,
    Emotes = function() return {["200"] = "winkt"} end,
    Emote = function(kind) calls.emote = kind end,
    Rate = function(key, stars, name, text) calls.rate = key .. "|" .. stars .. "|" .. name .. "|" .. text end,
    SetTyping = function(on) calls.typing = on end}
visitor = {active = false, ticks = 0}
package.preload["pc2coop.visitor"] = function() return {
    Tick = function() visitor.ticks = visitor.ticks + 1 end,
    Start = function() visitor.active = true end, Stop = function() visitor.active = false end,
    Active = function() return visitor.active end, Riding = function() return nil end,
    Ride = function(key, find) calls.ride = key; return true end,
    Rides = function(keyOf, cache) return {{key = "F1_0_2", name = "Conlan", kind = "Achterbahn", e = 6.5, f = 4.2, n = 1.8, dist = 40}} end} end
package.preload["pc2coop.sync"] = function() return {RideKey = function() return "F1_0_2" end, GidToEntity = function() return 1 end} end
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

    def test_visitor_mode_in_a_park(self):
        state = self.state()
        ride = state['visitor']['rides'][0]
        self.assertEqual((ride['name'], ride['avg'], ride['mine'], ride['comments'][0]['text']), ('Conlan', 4.5, 5, 'mehr Schatten'))
        self.assertEqual(state['visitor']['emotes'], {'200': 'winkt'})
        self.lua.execute('ui.SetOpen(true)')
        self.ui._Request('91|visitor|1')
        self.assertTrue(self.lua.eval('visitor.active'))
        self.assertFalse(self.state()['open'], 'the window closes when the walk starts')
        self.ui._Request('92|rate|F1_0_2|4|mehr Schatten')
        self.ui._Request('93|emote|wave')
        self.ui._Request('94|ride|F1_0_2')
        self.assertEqual((self.lua.eval('calls.rate'), self.lua.eval('calls.emote'), self.lua.eval('calls.ride')),
                         ('F1_0_2|4|Conlan|mehr Schatten', 'wave', 'F1_0_2'))
        self.assertGreater(self.lua.eval('visitor.ticks'), 0)
        self.ui._Request('95|visitor|0')
        self.assertFalse(self.lua.eval('visitor.active'))

    def test_board_vote_of_this_player(self):
        # Before: a proposal nobody had voted on showed "Dagegen" as chosen.
        self.lua.execute('view.role = "host"; view.context = "park"; view.players = {{sid = "100", name = "Ada"}}; '
                         'view.board = {{id = "b1", kind = "proposal", title = "See", votes = {}}, '
                         '{id = "b2", kind = "proposal", title = "Bahn", votes = {Ada = true}}, '
                         '{id = "b3", kind = "proposal", title = "Turm", votes = {Ada = false}}, '
                         '{id = "b4", kind = "task", title = "Wege"}}')
        votes = {item['id']: item['myVote'] for item in self.state()['team']['board']}
        self.assertEqual(votes, {'b1': False, 'b2': '1', 'b3': '0', 'b4': False})

    def test_enter_counts_up_and_the_chat_input_switches_typing(self):
        before = self.state()['chatKey']
        self.lua.execute('ui.ChatKey(); ui.ChatKey()')
        self.assertEqual(self.state()['chatKey'], before + 2)
        self.ui._Request('81|chatinput|1')
        self.assertTrue(self.lua.eval('calls.typing'))
        self.ui._Request('82|chatinput|0')
        self.assertFalse(self.lua.eval('calls.typing'))
        self.ui._Request('83|chatinput|1')
        self.ui._Request('84|hello|hud')
        self.assertFalse(self.lua.eval('calls.typing'), 'a fresh view has no open chat input')
        self.assertFalse(any('chatinput' in line for line in self.lua.eval('logs').values()), 'typing is not logged')

    def test_name_tags_are_switched_in_the_window(self):
        self.lua.execute('mymenu = {labelsEnabled = true}; cleared = 0; '
                         'package.loaded["pc2coop.labels"] = {Clear = function() cleared = cleared + 1 end}; '
                         'ui.Init(function(m) logs[#logs+1] = m end, session, {}, mymenu)')
        self.assertTrue(self.state()['labels'])
        self.ui._Request('71|labels|0')
        self.assertFalse(self.state()['labels'])
        self.assertEqual(self.lua.eval('cleared'), 1, 'the tags in the world go at once')
        self.ui._Request('72|labels|1')
        self.assertTrue(self.lua.eval('mymenu.labelsEnabled'))

    def test_qa_look_is_off_unless_a_dev_script_sets_it(self):
        self.assertFalse(self.state()['qaLook'])
        self.ui._QaLook('4|-1|0.7')
        self.assertEqual(self.state()['qaLook'], '4|-1|0.7|1')

    def test_an_unanswered_invitation_is_sent_with_its_frame(self):
        self.lua.execute('session.Friends = function() return {{sid = "7", name = "Vici", state = 1, pc2 = true, invited = false, invitedAt = 120},'
                         ' {sid = "8", name = "Kim", state = 1, pc2 = false, invited = false}} end')
        friends = {f['name']: f for f in self.state()['friends']}
        self.assertEqual((friends['Vici']['asked'], friends['Kim']['asked']), (120, False))

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

    def test_host_opening_a_park_on_the_game_pages(self):
        # TP-08: the spinner screens of the host's front end tell everyone a park is being opened.
        self.lua.execute('ui.SetFrontend(menuHud); view.role, view.stage = "client", "lobby"')
        self.ui._Request('1|opening|')
        self.assertEqual(len(self.lua.eval('calls.choice')), 0, 'a guest opens nothing')
        self.lua.execute('view.role = "host"')
        self.ui._Request('2|opening|')
        self.assertEqual(list(self.lua.eval('calls.choice').values()), ['game|einen Park|'])
        self.assertTrue(self.lua.eval('calls.starting'))

    def test_guests_cannot_pick_or_start(self):
        self.lua.execute('ui.SetFrontend(menuHud); view.role, view.stage = "client", "lobby"')
        self.lua.execute('ui._Request("1|choose|save|1"); ui._Request("2|start|")')
        self.assertEqual(len(self.lua.eval('calls.choice')), 0)
        self.assertEqual(len(self.lua.eval('calls.load')), 0)


if __name__ == '__main__':
    unittest.main()
