"""shop.lua: buying as a visitor - the shop in front, its items, the sale for the park (fake game)."""
from pathlib import Path
import unittest
try:
    from lupa.lua53 import LuaRuntime
except ImportError:
    LuaRuntime = None

SOURCE = Path(__file__).resolve().parents[1] / 'probe/PC2CoopProbe/Main/pc2coop/shop.lua'

FAKES = r"""
local function vec(x, y, z) return {GetX = function() return x end, GetY = function() return y end, GetZ = function() return z end} end
package.preload.Vector3 = function() return {new = function(_, x, y, z) return vec(x, y, z) end} end
-- A pizza vending machine (facility 4242) whose sign (4244) and body (4243) the rays hit, 4 m
-- ahead along +z; a bench (77) 2 m ahead along +x.
parents = {[4244] = 4243, [4243] = 4242, [4242] = 1}
items = {[0] = {sItem = "Food_CheesePizza", sDefaultName = "[ShopItem_Food_CheesePizza]", nCost = 860, bSold = true},
    [1] = {sItem = "Drink_Cola", sDefaultName = "[ShopItem_Drink_Cola]", nCost = 300, bSold = true},
    [2] = {sItem = "Food_Old", nCost = 100, bSold = false}}
credited, undoState = {}, {busy = 0, valid = true}
apis = {park = {ExpenditureCategory_FoodSales = 58, ExpenditureCategory_DrinkSales = 57, ExpenditureCategory_FacilitySales = 40},
    facilities = {IsFacility = function(_, e) return e == 4242 end, GetShopInventoryEntityID = function(_, e) return e + 1000 end,
        GetShopInventory = function(_, inv) if inv == 5242 then return {1, 2, 3} end return {} end,
        GetShopInventoryItem = function(_, inv, i) return items[i] end, IsOpen = function(_, e) return e == 4242 end},
    editors = {CreateUndoOperationsHierarchy = function() return {
        AddCashDelta = function(_, c, cat) credited[#credited+1] = c .. "@" .. cat end,
        GetFullUndoChangeList = function() return {} end} end}}
api = {world = {GetWorldAPIs = function() return apis end},
    entity = {FindEntityByName = function() return 5 end},
    transform = {GetParent = function(e) return parents[e] end},
    physics = {RayCast = function(world, a, b, flags, n)
        if flags ~= -1 then return {} end
        local dx, dz = b:GetX() - a:GetX(), b:GetZ() - a:GetZ()
        if math.abs(dx) < 1.2 and dz > 0 then return {{nEntityID = 4244, vPos = vec(a:GetX(), a:GetY(), a:GetZ() + 4)}} end
        if dx > 0 and math.abs(dz) < 1.2 then return {{nEntityID = 77, vPos = vec(a:GetX() + 2, a:GetY(), a:GetZ())}} end
        return {}
    end},
    undo = {IsBusy = function() undoState.busy = undoState.busy - 1; return undoState.busy >= 0 end,
        IsPreviewingChangeList = function() return false end, PreviewChangeList = function() return 1, 2 end,
        IsOperationComplete = function() return true end, CanCommitPreview = function() return undoState.valid end,
        CommitPreview = function() undoState.committed = true; return 3 end, CancelPreview = function() undoState.cancelled = true; return 4 end}}
"""


@unittest.skipIf(LuaRuntime is None, 'Optional lupa.lua53 runtime is not installed')
class ShopTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKES)
        self.lua.globals().Shop = self.lua.eval('function(s) return assert(load(s, "shop", "t", _G))() end')(
            SOURCE.read_text(encoding='utf8'))

    def test_names_kinds_and_prices(self):
        self.assertEqual(self.lua.eval('Shop.Readable("Food_CheesePizza")'), 'Cheese Pizza')
        self.assertEqual(self.lua.eval('Shop.Kind("Drink_Cola")'), 'drink')
        self.assertEqual(self.lua.eval('Shop.Kind("Food_CheesePizza")'), 'eat')
        self.assertIsNone(self.lua.eval('Shop.Kind("Souvenir_Hat")'))
        self.assertEqual(self.lua.eval('Shop.Price(860)'), '8,60')
        self.assertEqual(self.lua.eval('Shop.Price(1205.4)'), '12,05')
        self.assertEqual(self.lua.eval('Shop.Category("Souvenir_Hat", apis.park)'), 40)

    def test_items_as_the_info_panel_reads_them_without_what_is_not_sold(self):
        items = [dict(i.items()) for i in self.lua.eval('Shop.Items(4242)').values()]
        self.assertEqual([(i['index'], i['item'], i['cost'], i['kind']) for i in items],
                         [(0, 'Food_CheesePizza', 860, 'eat'), (1, 'Drink_Cola', 300, 'drink')])
        self.assertEqual(items[0]['loc'], '[ShopItem_Food_CheesePizza]')
        self.assertEqual(len(self.lua.eval('Shop.Items(77)')), 0)

    def test_the_shop_in_front_and_nothing_elsewhere(self):
        self.assertEqual(self.lua.eval('Shop.InFront(0, 1, 0, 0)'), 4242)                 # looking along +z
        self.assertIsNone(self.lua.eval('Shop.InFront(0, 1, 0, math.pi / 2)'))           # the bench along +x
        self.assertIsNone(self.lua.eval('Shop.InFront(0, 1, 0, 0, function(e) return e == 4244 end)'))
        self.assertTrue(self.lua.eval('Shop.IsOpen(4242)'))

    def test_the_sale_waits_for_the_editor_and_is_booked_as_food(self):
        self.lua.execute('undoState.busy = 3; co = coroutine.create(function() return Shop.Credit(860, "Food_CheesePizza") end)')
        for _ in range(3):
            self.lua.execute('coroutine.resume(co)')
            self.assertEqual(len(self.lua.eval('credited')), 0)
        self.lua.execute('ok, result = coroutine.resume(co)')
        self.assertTrue(self.lua.eval('result'))
        self.assertEqual(list(self.lua.eval('credited').values()), ['860@58'])
        self.assertTrue(self.lua.eval('undoState.committed'))

    def test_a_refused_sale_is_cancelled(self):
        self.lua.execute('undoState.valid = false; co = coroutine.create(function() return Shop.Credit(300, "Drink_Cola") end)')
        self.lua.execute('ok, result = coroutine.resume(co)')
        self.assertFalse(self.lua.eval('result'))
        self.assertTrue(self.lua.eval('undoState.cancelled'))


if __name__ == '__main__':
    unittest.main()
