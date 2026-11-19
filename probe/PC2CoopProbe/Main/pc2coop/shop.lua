-- Original MIT code. Buying as a visitor: the shop in front of the player, its items as the
-- game's shop info panel reads them (facilities API: GetShopInventoryEntityID,
-- GetShopInventory, GetShopInventoryItem), and the sale for the park's cash (an editor change
-- with AddCashDelta in the game's own income category: food, drinks or facility sales).
-- Tested in the test copy (build 26255360): a vending machine lists its pizzas with price
-- (nCost, in the game's cash units: 860 = 8.60), and a credit raised the cash by the price.
local global = _G
local Shop = {}

Shop.REACH = 6          -- metres in front of the player
Shop.MAX_ITEMS = 6      -- keys 1-6

local function apis() return global.api.world.GetWorldAPIs() end
local function V(x, y, z) return global.require("Vector3"):new(x, y, z) end

-- "Food_CheesePizza" -> "Cheese Pizza"
function Shop.Readable(item)
    local name = global.string.gsub(global.tostring(item or "?"), "^[^_]*_", "")
    name = global.string.gsub(name, "_", " ")
    name = global.string.gsub(name, "(%l)(%u)", "%1 %2")
    return name
end

-- Food is eaten, drinks are drunk; anything else (souvenirs, balloons) is just bought.
function Shop.Kind(item)
    item = global.tostring(item or "")
    if global.string.find(item, "^Drink_") then return "drink" end
    if global.string.find(item, "^Food_") or global.string.find(item, "^Dessert_") or global.string.find(item, "^Snack_") then return "eat" end
    return nil
end

function Shop.Category(item, park)
    local kind = Shop.Kind(item)
    if kind == "drink" then return park.ExpenditureCategory_DrinkSales end
    if kind == "eat" then return park.ExpenditureCategory_FoodSales end
    return park.ExpenditureCategory_FacilitySales
end

-- 860 -> "8,60"
function Shop.Price(cost)
    cost = global.math.floor((global.tonumber(cost) or 0) + 0.5)
    return global.string.format("%d,%02d", cost // 100, cost % 100)
end

-- The items a shop sells: {index (0-based, the game's), loc (name as a loc key), item, cost, kind}.
function Shop.Items(entity)
    local out = {}
    global.pcall(function()
        local F = apis().facilities
        local inventory = F:GetShopInventoryEntityID(entity)
        if inventory == nil then return end
        local all = F:GetShopInventory(inventory) or {}
        for i = 0, #all - 1 do
            local item = F:GetShopInventoryItem(inventory, i)
            if global.type(item) == "table" and item.bSold ~= false and global.tonumber(item.nCost) then
                out[#out+1] = {index = i, loc = global.tostring(item.sDefaultName or ""), item = global.tostring(item.sItem or "?"),
                    cost = global.tonumber(item.nCost), kind = Shop.Kind(item.sItem)}
                if #out >= Shop.MAX_ITEMS then break end
            end
        end
    end)
    return out
end

-- The facility a hit belongs to (the ray hits one of its parts).
local function facilityOf(entity)
    local F = apis().facilities
    for _ = 1, 8 do
        if entity == nil then return nil end
        local ok, is = global.pcall(function() return F:IsFacility(entity) end)
        if ok and is then return entity end
        local okP, parent = global.pcall(global.api.transform.GetParent, entity)
        entity = okP and parent or nil
    end
    return nil
end

-- The nearest shop with items within reach in front of (x, y, z) looking along yaw
-- (radians, 0 = +z): a fan of rays at chest height, like the select mode's "everything" ray.
function Shop.InFront(x, y, z, yaw, skip)
    local world = global.api.entity.FindEntityByName("MainPhysicsWorld")
    local ph = global.api.physics
    local best, bestD = nil, nil
    for step = -3, 3 do
        local a = yaw + step * global.math.pi / 18
        local from = V(x, y, z)
        local to = V(x + global.math.sin(a) * Shop.REACH, y, z + global.math.cos(a) * Shop.REACH)
        for _, hit in global.ipairs(ph.RayCast(world, from, to, ~0, 4) or {}) do
            if not (skip and skip(hit.nEntityID)) then
                local facility = facilityOf(hit.nEntityID)
                if facility then
                    local p = hit.vPos or hit.vPosition or hit.vHitPos
                    local d = p and global.math.sqrt((p:GetX() - x) ^ 2 + (p:GetZ() - z) ^ 2) or Shop.REACH
                    if (not bestD or d < bestD) and #Shop.Items(facility) > 0 then best, bestD = facility, d end
                    break
                end
            end
        end
    end
    return best
end

function Shop.IsOpen(entity)
    local ok, open = global.pcall(function() return apis().facilities:IsOpen(entity) end)
    return ok and open == true
end

-- Host: the sale goes into the park's cash, booked as the game books shop sales. Runs as an
-- editor change; waits while the editor is busy. Call from a coroutine.
function Shop.Credit(cost, item)
    local undo = global.api.undo
    while undo.IsBusy() or undo.IsPreviewingChangeList() do global.coroutine.yield() end
    local h = apis().editors:CreateUndoOperationsHierarchy()
    h:AddCashDelta(cost, Shop.Category(item, apis().park))
    local wait, preview = undo.PreviewChangeList(h:GetFullUndoChangeList())
    while not undo.IsOperationComplete(wait) do global.coroutine.yield() end
    local valid
    repeat valid = undo.CanCommitPreview(preview); if valid == nil then global.coroutine.yield() end until valid ~= nil
    if not valid then
        wait = undo.CancelPreview(preview)
        while not undo.IsOperationComplete(wait) do global.coroutine.yield() end
        return false
    end
    wait = undo.CommitPreview(preview)
    while not undo.IsOperationComplete(wait) do global.coroutine.yield() end
    return true
end

return Shop
