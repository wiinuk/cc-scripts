package.path = package.path..";../?.lua"
local TT = require "tt-core"
local mainLogger = TT.mainLogger
local persistentMemory = TT.persistentMemory
local goTo = TT.goTo
local isMovable = TT.isMovable
local disableDig = TT.disableDig
local Ex = require "extensions"
local maxByArray = Ex.maxByArray
local Vec3 = require "vec3"
local manhattanDistance = Vec3.manhattanDistance
local Memoried = require "memoried"
local Down = Memoried.Down
local Up = Memoried.Up
local Logger = require "logger"
local Mex = require "memoried_extensions"
local compactItems = Mex.compactItems
local pretty = require "pretty"


local DisableAttack = false
local Chest = "minecraft:chest"
local TrappedChest = "minecraft:chest"
local unsortedChestColor = "gray"
local singleKindChestColor = "light_blue"
local multipleKindChestColor = "blue"

local moveToSortedChestPriority = 0.4
local checkSortedChestPriority = 0.5

local function minCheckClock(chestLocation)
    local check = chestLocation.lastCheckClock or 0
    local modify = chestLocation.lastModifyClock or 0
    return modify + (check - modify) * 2
end

local function findHighPriorityLocation(locations)
    local clock = os.clock()
    local cx, cy, cz = Memoried.currentPosition()
    return maxByArray(locations, function(l)
        if clock < minCheckClock(l) then return end

        local modify = l.lastModifyClock or 0
        local d = manhattanDistance(l.x, l.y, l.z, cx, cy, cz)
        local span = clock - modify
        return -d + span
    end)
end

local function findHighPriorityUnsortedChestLocation()
    return findHighPriorityLocation(persistentMemory.colorToLocations[unsortedChestColor])
end

local function findHighPrioritySortedChestLocation()
    local multipleLocation, multiplePriority = findHighPriorityLocation(persistentMemory.colorToLocations[singleKindChestColor])
    local singleLocation, singlePriority = findHighPriorityLocation(persistentMemory.colorToLocations[multipleKindChestColor])

    if not multipleLocation and not singleLocation then return end
    if multipleLocation and not singleLocation then return multipleLocation end
    if not multipleLocation and singleLocation then return singleLocation end

    if multiplePriority < singlePriority then
        return multipleKindChestColor, singleLocation
    else
        return singleKindChestColor, multipleLocation
    end
end

local function isChest(info)
    return info and (info.name == Chest or info.name == TrappedChest)
end

local function findUnsortedChest(direction)
    if not Memoried.getOperationAt(direction).detect() then

        -- 正面にチェストがないなら前の下
        Memoried.getOperationAt(direction).move()
        local ok, info = Memoried.getOperationAt(Down).inspect()
        if not ok or not isChest(info) then
            return false, "chest not found"
        end
        return Down, 1
    end

    -- 積み上げられたチェストの高さをチェック
    local height = 1
    while true do
        if not Memoried.getOperationAt(Up).move() then break end
        local ok, info = Memoried.getOperationAt(direction).inspect()
        if not ok or not isChest(info) then break end
        height = height + 1
    end
    return direction, height
end

local function suckMany(slots, direction)
    while true do
        local slot = Mex.findLastEmptySlot()

        -- 空きスロットがなかった
        if not slot then break end

        turtle.select(slot)

        -- アイテムが無かった
        if not Memoried.getOperationAt(direction).suck() then break end

        slots = slots or {}
        slots[#slots+1] = slot
    end
    return slots
end

local function inspectItems(items, direction)
    local slots = suckMany(nil, direction)
    if not slots then return items end

    for i = 1, #slots do
        local slot = slots[i]

        turtle.select(slot)
        items = items or {}
        items[#items+1] = turtle.getItemDetail(slot)
        Memoried.getOperationAt(direction).drop()
    end
    return items
end

---@class ChestInfo
---@field public items table<integer, ItemDetail>
---@field public baseX integer
---@field public baseY integer
---@field public baseZ integer
---@field public offset integer
---@field public height integer
---@field public direction integer

---@class SortedChestLocation : Location
---@field public chests table<integer, ChestInfo>

---@return table<integer, ChestInfo>
local function checkNeighborSingleKindChests()
    local chests = {}
    local bx, by, bz = Memoried.currentPosition()

    -- 周囲のチェストをチェック
    for d = 1, 4 do
        local ok, info = Memoried.getOperationAt(d).inspect()
        if ok and isChest(info) then

            -- 一番下がチェストなら入っているアイテムを記録
            local items = {}
            local height = 1
            items = inspectItems(items, d)

            -- 上をチェックしていく
            while true do
                if not Memoried.getOperationAt(Up).move() then break end

                -- 上がチェストなら入っているアイテムを追記
                local ok, info = Memoried.getOperationAt(d).inspect()
                if not ok or not isChest(info) then break end

                items = inspectItems(items, d)
                height = height + 1
            end

            -- チェスト一覧に追加
            chests[#chests+1] = {
                baseX = bx,
                baseY = by,
                baseZ = bz,
                offset = 0,
                height = height,
                direction = d,
                items = items,
            }

            -- 下まで移動
            goTo(2, bx, by, bz, isMovable, disableDig, DisableAttack)
        end
    end
    return chests
end

local function checkNeighborMultipleKindChests()
    local chests = {}
    local bx, by, bz = Memoried.currentPosition()
    for d = 1, 4 do
        local offset = 0
        while true do
            local ok, info = Memoried.getOperationAt(d).inspect()
            if not ok or not isChest(info) then break end

            local items = inspectItems({}, d)
            chests[#chests+1] = {
                baseX = bx,
                baseY = by,
                baseZ = bz,
                offset = offset,
                height = 1,
                direction = d,
                items = items,
            }

            if not Memoried.getOperationAt(Up).move() then break end
            offset = offset + 1
        end
        goTo(2, bx, by, bz, isMovable, disableDig, DisableAttack)
    end
    return chests
end

---@param oldChest ChestInfo
---@param newChest ChestInfo
local function isChestUpdated(oldChest, newChest)
    local oldIsNull, newIsNull = oldChest == nil, newChest == nil
    if oldIsNull ~= newIsNull then return true end
    if oldIsNull then return false end

    local oldItems, newItems = oldChest.items, newChest.items
    if #oldItems ~= #newItems then return true end

    for i = 1, #oldItems do
        local oldItem, newItem = oldItems[i], newItems[i]
        if not (oldItem.name == newItem.name and oldItem.damage == newItem.damage) then
            return true
        end
    end
    return false
end

---@param oldChests table<integer, ChestInfo>
---@param newChests table<integer, ChestInfo>
local function isChestsUpdated(oldChests, newChests)
    local oldIsNull, newIsNull = oldChests == nil, newChests == nil
    if oldIsNull ~= newIsNull then return true end
    if oldIsNull then return false end
    if #oldChests ~= #newChests then return true end

    for i = 1, #oldChests do
        if isChestUpdated(oldChests[i], newChests[i]) then return true end
    end
    return false
end

local checkSortedChestRule = {
    name = "tt: check sorted chest",
    when = function()
        if not TT.isHomeChecked() then return end

        local color, location = findHighPrioritySortedChestLocation()
        if not location then return end

        return checkSortedChestPriority, color, location
    end,
    action = function(self, color, location)
        local tx, ty, tz = location.x, location.y, location.z

        local ok, reason = goTo(10, tx, ty, tz, isMovable, disableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, reason) end

        location.lastCheckClock = os.clock()

        compactItems()
        if color == singleKindChestColor then
            local oldChests = location.chests
            local newChests = checkNeighborSingleKindChests()
            if isChestsUpdated(oldChests, newChests) then
                location.lastModifyClock = os.clock()
                mainLogger.logDebug(self.name, "updated ( single )", tx, ty, tz, newChests)
            end
            location.chests = newChests

        elseif color == multipleKindChestColor then
            local oldChests = location.chests
            local newChests = checkNeighborMultipleKindChests()
            if isChestsUpdated(oldChests, newChests) then
                location.lastModifyClock = os.clock()
                mainLogger.logInfo(self.name, "updated ( multi )", tx, ty, tz, newChests)
            end
            location.chests = newChests

        else
            Logger.logError(self.name, "unknown chest kind color", color)
        end
    end
}

local transferItemToUnsortedChest = {
}

---@param slotToChest table<integer, ChestInfo>
local function popNearestChest(slotToChest)
    local nearestDistance = 1/0
    local nearestChest = nil
    local nearestSlot = nil
    local cx, cy, cz = Memoried.currentPosition()
    for slot, chest in pairs(slotToChest) do
        if chest then
            local distance = manhattanDistance(cx, cy, cz, chest.baseX, chest.baseY + chest.offset, chest.baseZ)
            if distance <= nearestDistance then
                nearestDistance = distance
                nearestSlot = slot
                nearestChest = chest
            end
        end
    end
    if nearestSlot then slotToChest[nearestSlot] = nil end

    return nearestSlot, nearestChest
end

local function transferToChestOnBase(slot, chest)

    -- チェストに移し替える
    local isComplete = false
    turtle.select(slot)
    for _ = 1, chest.height do

        -- 完全に移し替えられたら終わり
        if Memoried.getOperationAt(chest.direction).drop() and turtle.getItemCount(slot) == 0 then
            isComplete = true
            break
        end

        -- アイテムがチェストに入らなかったので上のチェストに移動する
        Memoried.getOperationAt(Up).move()
    end
    return isComplete
end

local function findChestFromChestLocations(locations, item)
    if not locations then return end

    for _, location in ipairs(locations) do
        local chests = location.chests
        if chests then
            for _, chest in ipairs(chests) do
                for _, chestItem in ipairs(chest.items) do
                    if item.name == chestItem.name then
                        return chest
                    end
                end
            end
        end
    end
end
local function findChestFromSortedChestLocations(item)
    local colorToLocations = persistentMemory.colorToLocations
    local chest = findChestFromChestLocations(colorToLocations[singleKindChestColor], item)
    if chest then return chest end

    return findChestFromChestLocations(colorToLocations[multipleKindChestColor], item)
end

local transferItemToSortedChestRule = {
    name = "tt: transfer to sorted chest",
    when = function()
        if not TT.isHomeChecked() then return end

        -- 一番優先度の高い仕分け前チェストを検索
        local location = findHighPriorityUnsortedChestLocation()
        if not location then return end

        return moveToSortedChestPriority, location
    end,
    action = function(self, location)
        local tx, ty, tz, d = location.x, location.y, location.z, location.direction

        local ok, reason = goTo(10, tx, ty, tz, isMovable, disableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, reason) end

        -- チェストの位置を検索
        local direction, height = findUnsortedChest(d)
        if not direction then return Logger.logError(self.name, height) end

        -- 空きを作る
        compactItems()

        -- TODO: 複数のチェストが重なっている場合下にアイテムを移動

        -- チェストからインベントリの空きスロットに移動
        goTo(10, tx, ty, tz, isMovable, disableDig, DisableAttack)
        local slots = suckMany(nil, direction)

        -- 上のチェストをチェック
        for _ = 2, height do
            Memoried.getOperationAt(Up).move()
            slots = suckMany(slots, direction)
        end

        location.lastCheckClock = os.clock()

        -- 何もインベントリに移動できなかったら終わり
        if not slots then return mainLogger.logInfo(self.name, "all item can not moved") end

        -- 取得したアイテムの移動先を検索
        local unmovableSlots = nil
        ---@type table<integer, ChestInfo>
        local slotToChest = nil
        for i = #slots, 1, -1 do
            local slot = slots[i]
            local item = turtle.getItemDetail(slot)
            local chest = findChestFromSortedChestLocations(item)
            if not chest then

                -- 移動先が見つからなかった
                mainLogger.logInfo(self.name, "not found", slot, pretty(item))
                unmovableSlots = unmovableSlots or {}
                unmovableSlots[#unmovableSlots+1] = slot
            else
                mainLogger.logInfo(self.name, "find", item, pretty(chest))
                slotToChest = slotToChest or {}
                slotToChest[slot] = chest
            end
        end

        -- 移動先が見つからなかったアイテムを仕分け前チェストに戻す
        if unmovableSlots then

            -- 一番下に戻る
            goTo(1, tx, ty, tz, isMovable, disableDig, DisableAttack)

            local i = 1
            for _ = 1, height do
                local slot = unmovableSlots[i]

                -- 戻すのが成功したら次のスロット
                turtle.select(slot)
                if Memoried.getOperationAt(direction).drop() then i = i + 1 end

                -- 全てのスロットを移し終えたので終わり
                if #unmovableSlots < i then break end

                -- 上に移動
                Memoried.getOperationAt(Up).move()
            end

            -- 全てのアイテムは移せなかった
            if not (#unmovableSlots < i) then
                local itemName = turtle.getItemDetail(unmovableSlots[i]).name
                mainLogger.logWarning(self.name, "item drop failed", itemName)
            end
        end

        -- 何も移動先が見付からなかったので終わり
        if not slotToChest then return end

        while true do

            -- 最も近いチェストを検索
            local slot, chest = popNearestChest(slotToChest)
            if not slot then break end

            -- 最も近いチェストに移動
            local ok, reason = goTo(3, chest.baseX, chest.baseY + chest.offset, chest.baseZ, isMovable, disableDig, DisableAttack)
            if not ok then
                mainLogger.logError(self.name, "move to chest", reason)
            else

                -- アイテムをチェストに移動
                local name = turtle.getItemDetail(slot).name
                if not transferToChestOnBase(slot, chest) then
                    mainLogger.logError(self.name, "item drop failed ( full? )")
                else
                    mainLogger.logInfo(self.name, "transfer", name, "to", chest.baseX, chest.baseY + chest.offset, chest.baseZ, chest.direction)
                end
            end
        end

        local now = os.clock()
        location.lastModifyClock = now
    end,
}

return {
    checkSortedChestRule = checkSortedChestRule,
    transferItemToSortedChestRule = transferItemToSortedChestRule,
}
