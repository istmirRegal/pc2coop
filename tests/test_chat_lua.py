"""Chat area bottom left (TP-22): messages and player events are tagged for it, Enter (DLL
"key:chat") reaches the UI, and while the chat input is open the visitor keys are text.
Three Lua runtimes over the simulated Steam lobby."""
import unittest

import test_session_lua as base

# Records what reaches the visitor module instead of acting on it.
KEY_SPY = '''
keys = {}
package.loaded["pc2coop.visitor"].OnKey = function(name, down) keys[#keys+1] = name .. (down and "1" or "0") end
'''


@unittest.skipIf(base.LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class ChatTests(unittest.TestCase):
    setUp = base.SessionTests.setUp
    lobby_enter = base.SessionTests.lobby_enter
    pump = base.SessionTests.pump

    def kinds(self, sid):
        return {t['text']: t['kind'] for t in self.peers[sid].lua.eval('session.Toasts()').values()}

    def test_messages_and_player_events_go_to_the_chat_area(self):
        self.peers['200'].lua.execute('session.SendChat("Hallo zusammen")')
        self.pump(4)
        kinds = self.kinds('300')
        self.assertEqual(kinds.get('Alex: Hallo zusammen'), 'chat', kinds)
        joined = [text for text, kind in kinds.items() if kind == 'event']
        self.assertTrue(joined, kinds)
        self.peers['300'].lua.execute('session.Notice("Etwas ging nicht", "ff922b")')
        self.assertEqual(self.kinds('300')['Etwas ging nicht'], 'notice')

    def test_enter_reaches_the_ui_hook(self):
        sam = self.peers['300']
        sam.lua.execute('presses = 0; session.OnChatKey = function() presses = presses + 1 end')
        sam.event('key:chat')
        sam.event('key:chat')
        sam.tick()
        self.assertEqual(sam.lua.eval('presses'), 2)

    def test_visitor_key_presses_are_text_while_typing(self):
        sam = self.peers['300']
        sam.lua.execute(KEY_SPY)
        sam.event('key:v|t|1')
        sam.tick()
        sam.lua.execute('session.SetTyping(true)')
        for event in ('key:v|e|1', 'key:v|e|0', 'key:v|t|0'):
            sam.event(event)
        sam.tick()
        self.assertTrue(sam.lua.eval('session.Typing()'))
        sam.lua.execute('session.SetTyping(false)')
        sam.event('key:v|v|1')
        sam.tick()
        # The press of E while typing is gone; its release and that of T still arrive.
        self.assertEqual(list(sam.lua.eval('keys').values()), ['t1', 'e0', 't0', 'v1'])


if __name__ == '__main__':
    unittest.main()
