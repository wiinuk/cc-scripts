local Memoried = require "memoried"
local Logger = require "logger"
local pretty = require "pretty"
local Vec3 = require "vec3"
local M = require "memoried_extensions"
local findItemInNearDrop = M.findItemInNearDrop
local directionToNormal = M.directionToNormal
local findNearMovablePath = M.findNearMovablePath
local goToGoal = M.goToGoal
local compactItems = M.compactItems
local findLastEmptySlot = M.findLastEmptySlot
local suckIf = M.suckIf
local getNeedFuelLevel = M.getNeedFuelLevel
local distanceToHome = M.distanceToHome
local globalDirectionToPosition = M.globalDirectionToPosition
local maybeAir = M.maybeAir
local isMapMissing = M.isMapMissing
local collectMissingMapAt = M.collectMissingMapAt

local Left = Memoried.Left
local Right = Memoried.Right

local DisableDig = true
local DisableAttack = true
local EnableAttack = false

local Torch = "minecraft:torch"
local CraftingTable = "minecraft:crafting_table"
local Stick = "minecraft:stick"
local Coal = "minecraft:coal"
local Planks = "minecraft:planks"
local Log = "minecraft:log"
local Chest = "minecraft:chest"

local collectMapInfoPriority = 0.1
local setTorchPriority = 1.2


local function findItemSlotBy(predicate)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and predicate(item) then return i end
    end
    return
end

local function findSlotByName(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then return i end
    end
    return
end

local function findLastSlotByName(name)
    for i = 16, 1, -1 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then return i end
    end
    return
end

---@class Recipe
---@field public tag string
---@field public width integer simple
---@field public height integer simple
---@field public names table<integer, string> simple

---@return Recipe
local function simpleRecipe(width, height, ...)
    return {
        tag = "simple",
        width = width,
        height = height,
        names = { ... },
    }
end

---@type table<string, Recipe>
local recipes = {
    [Torch] = simpleRecipe(1, 2, Coal, Stick),
    [Stick] = simpleRecipe(1, 2, Planks, Planks),
    [Planks] = simpleRecipe(1, 1, Log),
}

---@class CraftTree
---@field public item string
---@field public recipe Recipe
---@field public materials table<integer, CraftTree>

---@return CraftTree|nil
local function createCraftTree(itemName)
    if findSlotByName(itemName) then return { item = itemName } end

    local recipe = recipes[itemName]
    if not recipe then
        Logger.logDebug("recipe not found", itemName)
        return
    end

    local tag = recipe.tag
    if tag == "simple" then
        local names = recipe.names
        local tree = {
            item = itemName,
            recipe = recipe,
            materials = {},
        }
        for i = 1, #names do
            local t = createCraftTree(names[i])
            if not t then return end

            tree.materials[#tree.materials+1] = t
        end
        return tree
    end
    Logger.logDebug("unknown recipe tag: ", tag)
    return
end

local function canSingleCraft(tree)
    local deepTree = false
    local materials = tree.materials
    if materials then
        for i = 1, #materials do
            local childMaterials = materials[i].materials
            if childMaterials and 0 < #childMaterials then
                deepTree = true
                break
            end
        end
    end
    return not deepTree and not findItemSlotBy(function(item)
        for i = 1, #materials do
            if materials[i].name ~= item.name then
                return true
            end
        end
        return false
    end)
end

local function findCanDropDirection()
    -- 自分の周り
    for d = 1, 6 do
        local tx, ty, tz = globalDirectionToPosition(d)
        if maybeAir(Memoried.getLocation(tx, ty, tz)) then
            -- 空気
            return d
        end
    end
end

local function createCraftInfo(itemName)
    -- そもそも作業台を持っていない
    if
        Memoried.equippedItemName(Left) ~= CraftingTable and
        Memoried.equippedItemName(Right) ~= CraftingTable and
        not findSlotByName(CraftingTable)
    then
        return false
    end

    -- 原料を持っていない
    local tree = createCraftTree(itemName)
    if not tree then return false end

    -- 多段クラフトが必要なく、その原料のほかにアイテムを持っていないときは、アイテムを捨てる必要がない
    if canSingleCraft(tree) then return tree end

    -- チェストを持ってない
    if not findSlotByName(Chest) then return false end

    -- チェストを置ける場所を検索
    local direction = findCanDropDirection()
    if not direction then return false end

    return tree, direction
end

local function equipByName(name)
    -- 既に装備していた
    for d = 1, 6 do
        if Memoried.equippedItemName(d) == name then return true end
    end

    -- そもそもアイテムを持っていなかった
    local slot = findSlotByName(name)
    if not slot then return false, "item not found" end

    -- ダメージのあるアイテムだった
    if 0 < turtle.getItemDetail(slot).damage then return false, "damaged item" end

    -- 装備する方向を決定
    local side = Left
    if Memoried.equippedItemName(Left) then side = Right end

    -- 装備
    turtle.select(slot)
    Logger.logDebug("equip", Memoried.equippedItemName(side))
    return Memoried.getOperation(side).equip()
end

---@param materials table<integer, CraftTree>
---@param dropDirection integer
local function dropWithoutNeededMaterials(materials, dropDirection)
    local neededItemCounts = {}
    for i = 1, #materials do
        local name = materials[i].item
        neededItemCounts[name] = (neededItemCounts[name] or 0) + 1
    end

    local currentItemCounts = {}

    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            local name = item.name
            local currentCount = (currentItemCounts[name] or 0) + item.count
            currentItemCounts[name] = currentCount

            local remainingCount = currentCount - (neededItemCounts[name] or 0)
            if 0 < remainingCount then
                turtle.select(slot)
                local dropCount = math.min(remainingCount, turtle.getItemCount(slot))
                local ok, reason = Memoried.getOperationAt(dropDirection).drop(dropCount)
                if not ok then return ok, reason end
            end
        end
    end
    return true
end

local function suckMany(globalDirection)
    while true do
        local ok, reason = Memoried.getOperationAt(globalDirection).suck()
        if not ok then return reason end
    end
end

--- スロットにレシピの材料が必要
--- スロットに1つ以上の空きが必要
local function transferItemsOfRecipe(recipe)
    for sy = 1, recipe.height do
        for sx = 1, recipe.width do
            local slot = 4 * (sy - 1) + sx
            local item = turtle.getItemDetail(slot)
            local name = recipe.names[recipe.width * (sy - 1) + sx]
            if (item and item.name) ~= name then

                -- 空きを作る
                local emptySlot = findLastEmptySlot()
                if not emptySlot then return false, "empty slot not found" end

                turtle.select(slot)
                turtle.transferTo(emptySlot)

                if name ~= "" and name ~= nil then

                    -- 配置
                    local fromSlot = findLastSlotByName(name)
                    if not fromSlot then return false, "item not found '"..name.."'" end

                    turtle.select(fromSlot)
                    turtle.transferTo(slot, 1)
                end
            end
        end
    end
    return true
end

--- - 作業台を装備している必要がある
--- - 指定された方向に一時的にアイテムをドロップする
local function craftOfTree(tree, dropDirection)
    local materials = tree.materials

    -- 原料が無い場合、既に持っている
    if not materials or #materials == 0 then
        Logger.logDebug("inv", tree.item)
        return true
    end

    -- まず原料をクラフトする
    for i = 1, #materials do
        local ok, reason = craftOfTree(materials[i], dropDirection)
        if not ok then return ok, reason end
    end

    -- 原料がそろったので、必要な原料以外を捨てる
    local ok, reason = dropWithoutNeededMaterials(materials, dropDirection)
    if not ok then
        Logger.logError("craftOfTree", reason)
        suckMany(dropDirection)
        return ok, reason
    end

    -- レシピを基にクラフトする
    local recipe = tree.recipe
    if recipe.tag == "simple" then

        -- 原料を配置する
        local ok, reason = transferItemsOfRecipe(recipe)
        if not ok then suckMany(dropDirection) return ok, reason end

        -- クラフト
        local ok, reason = turtle.craft(1)
        if not ok then suckMany(dropDirection) return ok, reason end

        Logger.logDebug("new", tree.item, "from", pretty(recipe))

        -- 拾う
        suckMany(dropDirection)
        return true
    end

    suckMany(dropDirection)
    return false, "unknown recipe tag: '"..recipe.tag.."'"
end

local function findCombustibleInInventory()
    if turtle.getFuelLimit() == "unlimited" then return false end

    local itemToFuelLevel = Memoried.memory.itemToFuelLevel
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            local name = item.name
            local combustible = itemToFuelLevel[name]
            if combustible == nil then
                if turtle.getSelectedSlot() ~= i then
                    turtle.select(i)
                end
                local oldLevel = turtle.getFuelLevel()
                turtle.refuel(1)
                itemToFuelLevel[name] = turtle.getFuelLevel() - oldLevel
            end
            if 0 < itemToFuelLevel[name] then
                return i
            end
        end
    end
    return
end

local function combustible(item)
    local l = Memoried.memory.itemToFuelLevel[item.name]
    return l and 0 < l
end

---@type Rule
local collectAroundMapRule = {
    name = "collect around map",
    when = function()
        local lastCollectClock = Memoried.memory.lastCollectMapClock or 0
        if lastCollectClock + 5 < os.clock() then
            return collectMapInfoPriority
        end

        for globalDirection = 1, 6 do
            local x, y, z = globalDirectionToPosition(globalDirection)
            local location = Memoried.getLocation(x, y, z)
            if isMapMissing(location) then
                return collectMapInfoPriority, globalDirection
            end
        end
        return false
    end,
    action = function (_, gd)
        Memoried.memory.lastCollectMapClock = os.clock()
        if gd then return collectMissingMapAt(gd) end
        for i = 1, 6 do collectMissingMapAt(i) end
    end,
}
---@type Rule
local craftTorchRule = {
    name = "craft torch",
    when = function()
        if findSlotByName(Torch) then return false end

        local tree, direction = createCraftInfo(Torch)
        if not tree then return false end
        return 1, tree, direction
    end,
    action = function(self, tree, direction)

        -- チェストを設置
        if direction then
            local slot = findSlotByName(Chest)
            if not slot then
                Logger.logDebug(self.name, "chest not found in inventory")
                return
            end

            turtle.select(slot)
            Memoried.getOperationAt(direction).place()
        end

        -- 装備
        local ok, reason = equipByName(CraftingTable)
        if not ok then
            Logger.logDebug(self.name, "equip", reason)

            -- チェストを撤去
            Memoried.getOperationAt(direction).dig()
            Memoried.getOperationAt(direction).suck()
            return
        end

        -- クラフト
        compactItems()
        local ok, reason = craftOfTree(tree, direction)
        if not ok then Logger.logDebug(self.name, "craftOfTree", reason) end

        -- チェストを撤去
        Memoried.getOperationAt(direction).dig()
        Memoried.getOperationAt(direction).suck()
    end
}
local setTorchRule = {
    name = "set torch",
    when = function()

        -- トーチを持っていて
        local slot = findSlotByName(Torch)
        if not slot then return false end

        -- 近くにトーチを置いたことがなく
        local x, y, z = Memoried.currentPosition()
        local history = Memoried.memory.setTorchHistory
        for i = #history, math.max(1, #history - 10), -1 do
            local p = history[i]
            local tx, ty, tz = p[1], p[2], p[3]
            local location = Memoried.getLocation(tx, ty, tz)
            if location and (location.move == true or (location.inspect and location.inspect.name ~= Torch)) then
                -- トーチでないので削除
                table.remove(history, i)
                Logger.logInfo("remove torch history", tx, ty, tz)
            end
            if Vec3.manhattanDistance(x, y, z, tx, ty, tz) < 6 then return false end
        end

        for gd = 1, 6 do
            local tx, ty, tz = globalDirectionToPosition(gd)
            local location = Memoried.getLocation(tx, ty, tz)

            -- トーチを設置できる空間があり
            if maybeAir(location) then
                local hasBaseBlock = false

                -- トーチが刺さるブロックがあるか探す ( 天井を除く )
                for baseDirection = 1, 5 do
                    local nx, ny, nz = directionToNormal(baseDirection)
                    local baseLocation = Memoried.getLocation(tx + nx, ty + ny, tz + nz)
                    if baseLocation and baseLocation.detect == true then
                        hasBaseBlock = true
                        break
                    end
                end
                if hasBaseBlock then return setTorchPriority, slot, gd end
            end
        end
        return false
    end,
    action = function(self, slot, gd)
        if turtle.getSelectedSlot() ~= slot then
            turtle.select(slot)
        end

        local ok, reason = Memoried.getOperationAt(gd).place()
        if not ok then
            Logger.logError("["..self.name.."]", "place failure", reason)
        end
    end
}
local refuelRule = {
    name = "refuel",
    when = function()
        if getNeedFuelLevel() < turtle.getFuelLevel() then return false end

        -- インベントリを探す
        local slotNumber = findCombustibleInInventory()
        if slotNumber then
            return 1, "inventory", slotNumber
        end

        -- 周りのドロップアイテム ( やチェスト ) を探す
        local tx, ty, tz = findItemInNearDrop(combustible)

        -- TODO: アイテムが落ちた方向を追跡する
        if tx then
            local complete, path, gd = findNearMovablePath(tx, ty, tz)
            local p = 1
            if not complete then p = 0.9 end
            if gd then return p, "drop", gd, path end
        end
    end,
    action = function(self, type, v1, v2)
        if type == "inventory" then
            local slotNumber = v1
            if turtle.getSelectedSlot() ~= slotNumber then
                turtle.select(slotNumber)
            end
            turtle.refuel()
        end
        if type == "drop" then
            local gd, path = v1, v2

            -- その場所まで移動
            local ok, reason = goToGoal(20, path, DisableDig, DisableAttack)
            if not ok then Logger.logDebug(self.name, reason) return end

            -- アイテムをチェストや地面から回収
            local ok, reason = suckIf(combustible, gd, 20)
            if not ok then Logger.logDebug(self.name, reason) end
            return
        end
        return false
    end,
}
local goHomeRule = {
    name = "go home",
    when = function()
        if Memoried.anyRequest() then return end
        if distanceToHome() < 10 then return end

        local _, path = findNearMovablePath(0, 0, 0)
        if not path then return false end
        return 1, path
    end,
    action = function(self, path)
        local ok, reason = goToGoal(100, path, DisableDig, EnableAttack)
        if not ok then Logger.logDebug(self.name, reason) end
    end
}

return {
    collectAroundMapRule = collectAroundMapRule,
    craftTorchRule = craftTorchRule,
    setTorchRule = setTorchRule,
    refuelRule = refuelRule,
    goHomeRule = goHomeRule,
}