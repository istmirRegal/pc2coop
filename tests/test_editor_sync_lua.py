"""sync.lua and the editor: what the player holds, locks of other players, giving up a
preview whose object a remote change removed, and undo of one's own steps only."""
import unittest

import test_sync_lua as base

# The editor tool as the game hands it out: scenery sub mode holding one object.
HOLD_PART = '''
local part = ...
local entity = api.world.GetWorldAPIs().placement:PlacementIDToEntityID(part)
local object = {held = part,
    GetTransform = function() return api.transform.CalculateWorldTransform(entity) end,
    GetScale = function() return 1 end}
editor.mode = {subMode = {moveObject = object, sPropToMake = "AQ_Rock_04"}}
editor.ui, editor.edit = "GamefaceSceneryPlacement", "SceneryEdit"
'''


@unittest.skipIf(base.LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class EditorSyncTests(unittest.TestCase):
    setUp = base.SyncTests.setUp
    records = base.SyncTests.records
    tick = base.SyncTests.tick
    local_build = base.SyncTests.local_build

    def shared_rock(self):
        """A rock built here and acknowledged by the host as g7; returns its part id."""
        self.local_build()
        part = self.records('sync:up|')[0].split('|')[1]
        self.lua.execute(f'sync.Receive("M|1|g7|{part}|1")')
        self.tick(3)
        return part

    def hold(self, part):
        # The fake scenery API reports the object's part ids like the game does.
        self.lua.execute('api.world.GetWorldAPIs().scenery.GetMoveObjectPartIDs = function(_, o) return {o.held or o.part} end')
        self.lua.eval('function(code, part) assert(load(code))(part) end')(HOLD_PART, int(part))

    def test_holding_a_shared_object_is_reported_with_its_id_and_place(self):
        part = self.shared_rock()
        self.hold(part)
        self.tick(10)
        self.assertEqual(self.records('sync:hold|'), ['sync:hold|AQ_Rock_04|g7|AQ_Rock_04,10.00,5.00,10.00,0,0,0,1,1.00'])
        self.assertTrue(self.lua.eval(f'sync.HeldParts()[{part}]'))
        self.assertIn('|baut', self.records('sync:pres|')[-1])
        # Put down: reported once.
        self.lua.execute('editor.mode = nil; editor.ui, editor.edit = "Select", "Select"')
        self.tick(10)
        self.assertEqual(self.records('sync:hold|')[-1], 'sync:hold|')
        self.assertIsNone(self.lua.eval(f'sync.HeldParts()[{part}]'))

    def test_a_ride_on_the_cursor_is_reported_without_a_model(self):
        self.lua.execute('''
            local T, Q, V = require("TransformQ"), require("Quaternion"), require("Vector3")
            local composite = {GetTransform = function() return T.FromOrPos(Q.Identity, V:new(109.86, -0.23, 457.38)) end}
            api.world.GetWorldAPIs().scenery.GetMoveObjectPartIDs = function() error("not a scenery object") end
            editor.mode = {cMoveObject = composite, sFlatRideName = "FR_Teacups"}
            editor.ui, editor.edit = "GamefaceRidePlacement", "FlatRidePlacement"
        ''')
        self.tick(10)
        self.assertEqual(self.records('sync:hold|'), ['sync:hold|FR_Teacups||!FR_Teacups,109.86,-0.23,457.38,0,0,0,1,1.00'])
        self.assertIn('|platziert ein Fahrgeschaeft|', self.records('sync:pres|')[-1])

    def test_object_held_by_someone_else_cannot_be_picked_up(self):
        part = self.shared_rock()
        self.lua.execute('sync.SetRemoteLocks({g7 = "Vici"})')
        self.hold(part)
        self.tick(10)
        self.assertEqual(self.records('sync:hold-denied|'), ['sync:hold-denied|Vici'])
        self.assertEqual(self.lua.eval('editor.left'), 1)
        self.assertEqual(self.records('sync:hold|'), [])

    def preview_held(self, part):
        self.lua.execute(f'''
            local h = api.world.GetWorldAPIs().editors:CreateUndoOperationsHierarchy()
            h:EditExistingPart({part})
            api.undo.PreviewChangeList(h:GetFullUndoChangeList())
            previewingNow = true
            sync._SetHeld({{[{part}] = true}})
        ''')

    def test_remote_delete_of_the_held_object_gives_the_preview_up(self):
        part = self.shared_rock()
        self.preview_held(part)
        self.lua.execute('sync.Receive("D|2|g7|Vici|2")')
        self.tick(40)
        self.assertEqual(self.records('sync:hold-lost'), ['sync:hold-lost'])
        self.assertEqual(self.records('sync:preview-resumed'), [])
        self.assertIsNone(self.lua.eval(f'game.parts[{part}]'))
        self.assertEqual(self.lua.eval('#previewLists[#previewLists].hierarchy.ops'), 0)   # an empty preview
        self.assertEqual(self.lua.eval('editor.left'), 1)

    def test_remote_change_elsewhere_keeps_the_players_preview(self):
        part = self.shared_rock()
        self.preview_held(part)
        self.lua.execute('sync.Receive("U|2|g9|Vici|1|Fern|30|0.5|30|0|0|0|1|1")')
        self.tick(40)
        self.assertEqual(self.records('sync:preview-resumed'), ['sync:preview-resumed'])
        self.assertEqual(self.records('sync:hold-lost'), [])
        self.assertEqual(self.lua.eval('#previewLists[#previewLists].hierarchy.ops'), 1)   # the player's list again
        self.assertEqual(self.lua.eval('editor.left'), 0)

    def test_only_ones_own_newest_step_can_be_undone(self):
        self.lua.execute('sync.Receive("U|1|g1|Vici|1|Fern|30|0.5|30|0|0|0|1|1")')
        self.tick(20)
        self.assertFalse(self.lua.eval('sync.MayUndo(true)'))
        self.assertEqual(self.records('sync:undo-blocked|'), ['sync:undo-blocked|undo'])
        self.local_build()
        self.lua.execute('api.undo.Checkpoint({sMode = "Scenery"})')   # the editor's own checkpoint
        self.assertTrue(self.lua.eval('sync.MayUndo(true)'))
        self.lua.execute('undone = {pc2coopRemote = true}')
        self.assertFalse(self.lua.eval('sync.MayUndo(false)'))

    def test_undo_is_reported_like_any_other_change(self):
        self.local_build()
        part = self.records('sync:up|')[0].split('|')[1]
        self.lua.execute('api.undo.Undo()')
        self.tick(10)
        self.assertEqual(self.records('sync:del|'), [f'sync:del|{part}||0'])

    def test_state_of_an_object_for_the_hosts_corrections(self):
        self.lua.execute('sync.Receive("U|1|g1|Vici|1|Fern|30|0.5|32|0|0|0|1|2")')
        self.tick(20)
        state = self.lua.eval('sync.StateOf("g1")')
        self.assertEqual((state['res'], state['p'][1], state['p'][3], state['s']), ('Fern', 30, 32, 2))
        self.assertIsNone(self.lua.eval('sync.StateOf("nope")'))


if __name__ == '__main__':
    unittest.main()
