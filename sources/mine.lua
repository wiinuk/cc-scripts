
---@version: 0.4.3
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Ex = require "extensions"
local Logger = require "logger"
local Rules = require "rules"
local pretty = require "pretty"

local Forward = Memoried.Forward
local Left = Memoried.Left
local Back = Memoried.Back
local Right = Memoried.Right
local Down = Memoried.Down
local Up = Memoried.Up

local mainLogger = Logger.create("main")


---@return integer|nil slotNumber
local function findEmptySlot()
    for i = 16, 1, -1 do
        if turtle.getItemCount(i) == 0 then return i end
    end
    return nil
end

local normals = {
    0,0,1,
    -1,0,0,
    0,0,-1,
    1,0,0,
    0,-1,0,
    0,1,0,
}
---@param direction integer Direction
local function directionToNormal(direction)
    local i = direction * 3
    return normals[i - 2], normals[i - 1], normals[i]
end

local function globalDirectionToPosition(globalDirection)
    local x, y, z = Memoried.currentPosition()
    local nx, ny, nz = directionToNormal(globalDirection)
    return x + nx, y + ny, z + nz
end
local function limitedDig(globalDirection)
    local ok, info = Memoried.getOperationAt(globalDirection).inspect()
    if not ok then return false, info end

    local name = info.name
    if
        name == "minecraft:chest" or
        name == "minecraft:torch"
    then
        return false, "important item"
    end
    return Memoried.getOperationAt(globalDirection).dig()
end

---@param globalDirection integer
---@param disableDig boolean|nil
---@param disableAttack boolean|nil
local function mineMove1(globalDirection, disableDig, disableAttack)

    if Memoried.getOperationAt(globalDirection).move() then return true end
    -- 行けなかった

    -- ブロックがあるなら掘る
    if not disableDig and Memoried.getOperationAt(globalDirection).detect() then

        -- 掘る
        limitedDig(globalDirection)

        -- 拾う
        Memoried.getOperationAt(globalDirection).suck()
    end

    -- 掘ったら行けた?
    if Memoried.getOperationAt(globalDirection).move() then return true end

    -- エンティティがいる?
    if not Memoried.getOperationAt(globalDirection).detect() then
        -- 待機
        os.sleep(1)
        if Memoried.getOperationAt(globalDirection).move() then
            return true
        end
    end

    if not disableAttack then
        -- エンティティがいる?
        while not Memoried.getOperationAt(globalDirection).detect() do
            if Memoried.getOperationAt(globalDirection).move() then return true end
            -- 攻撃
            Memoried.getOperationAt(globalDirection).attack()
        end
    end

    -- 移動
    local ok, reason = Memoried.getOperationAt(globalDirection).move()
    if ok then return true end

    -- 失敗
    return false, reason
end

local function mineTo(maxRetryCount, targetX, targetY, targetZ, disableDig, disableAttack)
    local maxRetryCount = math.max(0, maxRetryCount)
    local retryCount = 0
    local lastReason = nil

    while true do
        if maxRetryCount < retryCount then return false, lastReason end

        local currentX, currentY, currentZ = Memoried.currentPosition()

        if currentX == targetX and currentY == targetY and currentZ == targetZ then return true end

        local ok, reason = false, nil
        if targetX < currentX then ok, reason = mineMove1(Left, disableDig, disableAttack)
        elseif currentX < targetX then ok, reason = mineMove1(Right, disableDig, disableAttack)
        elseif targetZ < currentZ then ok, reason = mineMove1(Back, disableDig, disableAttack)
        elseif currentZ < targetZ then ok, reason = mineMove1(Forward, disableDig, disableAttack)

        elseif currentY < targetY then ok, reason = mineMove1(Up, disableDig, disableAttack)
        elseif targetY < currentY then ok, reason = mineMove1(Down, disableDig, disableAttack)
        end
        if not ok then
            lastReason = reason
            retryCount = retryCount + 1
        end
    end
end

--- 同種のアイテムを重ねてインベントリに空きを作る。
--- できるだけ元のスロットの位置を維持する
local function compactItems()
    for i = 1, 16 do
        local iSpace = turtle.getItemSpace(i)
        if 0 ~= iSpace then
            local ii = turtle.getItemDetail(i)
            if ii then
                for j = i + 1, 16 do
                    local ji = turtle.getItemDetail(j)
                    local jCount = turtle.getItemCount()
                    if ji and ii.name == ji.name and ii.damage == ji.damage and jCount <= iSpace then
                        turtle.select(j)
                        turtle.transferTo(i)
                    end
                end
            end
        end
    end
end

---@param globalDirection integer
---@param slotNumbers integer[]
local function dropMany(globalDirection, slotNumbers)
    local allOk, lastReason = true, nil
    for i = 1, #slotNumbers do
        turtle.select(slotNumbers[i])
        local ok, reason = Memoried.getOperationAt(globalDirection).drop()
        allOk = allOk and ok
        if not ok and reason then lastReason = reason end
    end
    return allOk, lastReason
end

local function dropManyAndLog(globalDirection, slotNumbers)
    local ok, reason = dropMany(globalDirection, slotNumbers)
    if not ok then Logger.logInfo("drop many failure: ", reason) end
end

local function suckIf(isNeedItem, globalDirection, maxRetryCount)
    maxRetryCount = math.max(0, maxRetryCount or 20)

    -- スロットの空きを作る
    -- TODO: 希少度の低いアイテムを捨てる
    compactItems()

    local retryCount = 0
    local temporarySlots = {}
    while retryCount <= maxRetryCount do

        -- 空スロットを選択
        local slot = findEmptySlot()
        if not slot then
            -- 空スロットがないなら、不要なアイテムを落として終わり
            dropManyAndLog(globalDirection, temporarySlots)
            return false, "empty slot not found"
        end
        if turtle.getSelectedSlot() ~= slot then
            turtle.select(slot)
        end

        -- アイテムを拾う
        local ok, reason = Memoried.getOperationAt(globalDirection).suck()
        if not ok then
            -- 拾えなかったので、不要なアイテムを落として終わり
            dropManyAndLog(globalDirection, temporarySlots)
            return false, reason
        end

        local item = turtle.getItemDetail()
        if item then
            -- アイテムが必要なアイテムなら終わり
            if isNeedItem(item) then return true end

            -- 拾った不要アイテムのあるスロットを記録
            temporarySlots[#temporarySlots+1] = slot
        end

        retryCount = retryCount + 1
    end

    -- リトライ回数を超えたので、不要なアイテムを落として終わり
    dropManyAndLog(globalDirection, temporarySlots)
    return false, "number of retries exceeded"
end

---@class MiningOptions
---@field public down integer
---@field public forward integer
---@field public right integer

---@param request Request mining request
---@param x number
---@param y number
---@param z number
local function inMiningRequestRange(request, x, y, z)
    ---@type Box3|nil
    local range = request.range
    if range then return Box3.vsPoint(range, x, y, z) end
end

--- 既定の要求の優先度
local defaultRequestPriority = 0.5

--- 太陽光が当たる場所を掘るときの優先度係数
--- - 太陽光が当たるので MOB が湧かない
-- local sunLightMiningPriorityRatio = 1.5

--- 下を掘るときの優先度係数
--- - 下のほうが良い鉱石が出る
local minePriorityRatio = 1.5
local miningPriorityRatios = {
    [Forward] = 1,
    [Left] = 1,
    [Back] = 1,
    [Right] = 1,

    [Down] = 1.1,
    [Up] = 0.9,
}
local collectMapInfoPriority = 0.1
local miningCollectMapInfoPriorityRatio = 1.2
local equipToolPriorityRatio = 1.5
local moveToRangePriorityRatio = 1
local defaultDropChestPriority = 1
local setTorchPriority = 1.2

---@param priority number
---@param request Request
---@param globalDirection integer
local function whenMine(priority, request, globalDirection)
    local tx, ty, tz = globalDirectionToPosition(globalDirection)
    if not inMiningRequestRange(request, tx, ty, tz) then return priority end
    local location = Memoried.getLocation(tx, ty, tz)
    if not location or not location.detect then return priority end

    local ok, info = Memoried.getOperationAt(globalDirection).inspect()
    if ok then
        local name = info.name

        -- TODO: アイテム名をハードコードせずに判断したい
        if
            name == "minecraft:chest" or
            name == "minecraft:torch"
        then return priority end
    end

    local p = Memoried.memory.requestPriority or defaultRequestPriority
    p = p * minePriorityRatio * miningPriorityRatios[globalDirection]

    -- TODO:
    -- if isSunLight(x, y, z) then
    --     p = p * sunLightMiningPriorityRatio
    -- end

    return (priority or 0) + p, p
end

---@param globalDirection integer
---@return table|nil itemDetail
---@return string reason
local function inspectItemAt(globalDirection)
    compactItems()
    local emptySlot = findEmptySlot()
    if not emptySlot then return nil, "empty slot not found" end

    if turtle.getSelectedSlot() ~= emptySlot then
        turtle.select(emptySlot)
    end
    local item = nil
    if Memoried.getOperationAt(globalDirection).suck() then
        item = turtle.getItemDetail()
        Memoried.getOperationAt(globalDirection).drop()
    end
    return item
end

local function whenSuckAt(priority, globalDirection)
    local item, reason = inspectItemAt(globalDirection)
    if item then return (priority or 0) + 1
    elseif reason == "empty slot not found" then
        -- TODO:
        return false
    else
        return false
    end
end

local function isMapMissing(location)
    if not location then return true end
    if location.detect == nil then return true end
    if location.inspect == nil then return true end
    if location.drops == nil then return true end
    return false
end

--- 指定された世界方向のマップ情報を取得する
local function collectMissingMapAt(gd)
    Memoried.getOperationAt(gd).detect()
    Memoried.getOperationAt(gd).inspect()
    if not inspectItemAt(gd) then
        Memoried.getOperationAt(gd).drop()
        Memoried.getOperationAt(gd).suck()
    end
end

---@return integer|nil globalDirection
---@return integer mx
---@return integer my
---@return integer mz
local function findNearMovablePosition(tx, ty, tz)
    for globalDirection = 1, 6 do
        local nx, ny, nz = directionToNormal(globalDirection)
        local mx, my, mz = tx - nx, ty - ny, tz - nz
        local location = Memoried.getLocation(mx, my, mz)
        if location and (location.detect == false or location.move == true) then
            return globalDirection, mx, my, mz
        end
    end
    return
end
---@param tx integer 対象の世界座標x
---@param ty integer 対象の世界座標y
---@param tz integer 対象の世界座標z
---@return integer|nil globalDirection `mx, my, mz` から見た、`tx, ty, tz` の世界方向
---@return integer mx 対象のそばの、移動できるブロックの世界座標x
---@return integer my 対象のそばの、移動できるブロックの世界座標y
---@return integer mz 対象のそばの、移動できるブロックの世界座標z
local function findNearMovablePositionIfMissingMap(tx, ty, tz)
    local location = Memoried.getLocation(tx, ty, tz)
    if isMapMissing(location) then
        -- 探査していない情報がある
        local d, mx, my, mz = findNearMovablePosition(tx, ty, tz)
        if d then return d, mx, my, mz end
    end
    return
end

Rules.add {
    name = "mining: dig around",
    when = function ()
        local request = Memoried.getRequest "mining"
        if not request then return false end

        for gd = 1, 6 do
            local _, p = whenMine(false, request, gd)
            if p then return p, gd end
        end
        return false
    end,
    action = function (self, globalDirection)
        local ok, reason = limitedDig(globalDirection)
        if not ok then Logger.logError(self.name, "error", reason, "gd", tostring(globalDirection)) end
    end,
}
Rules.add {
    name = "mining: move to block",
    when = function ()
        local request = Memoried.getRequest "mining"
        if not request then return false end

        local range = request.range
        if not range then return false end

        -- 周りを探索
        local x, y, z = Memoried.currentPosition()
        x = Memoried.memory.lastFindX or x
        y = Memoried.memory.lastFindY or y
        z = Memoried.memory.lastFindZ or z
        for dx = -1, 1 do
            for dy = -1, 1 do
                for dz = -1, 1 do
                    local x, y, z = x + dx, y + dy, z + dz
                    if Box3.vsPoint(range, x, y, z) and Memoried.canDigInMemory(x, y, z) then
                        Memoried.memory.lastFindX = x
                        Memoried.memory.lastFindY = y
                        Memoried.memory.lastFindZ = z
                        return 0.5
                    end
                end
            end
        end

        -- ランダムに探索
        local maxSearchCount = 20
        for _ = 1, maxSearchCount do
            local x = math.random(range.minX, range.maxX)
            local y = math.random(range.minY, range.maxY)
            local z = math.random(range.minZ, range.maxZ)
            if Memoried.canDigInMemory(x, y, z) then
                Memoried.memory.lastFindX = x
                Memoried.memory.lastFindY = y
                Memoried.memory.lastFindZ = z
                return 0.5
            end
        end
        return false
    end,
    action = function ()
        local ok, reason = mineTo(
            20,
            Memoried.memory.lastFindX,
            Memoried.memory.lastFindY,
            Memoried.memory.lastFindZ
        )
        if not ok then Logger.logError(reason) end
    end
}
Rules.add {
    name = "mining: suck",
    when = function ()
        if not Memoried.hasRequest("mining") then return false end

        local priority = false
        priority = whenSuckAt(priority, Memoried.toGlobalDirection(Forward))
        priority = whenSuckAt(priority, Memoried.toGlobalDirection(Up))
        priority = whenSuckAt(priority, Memoried.toGlobalDirection(Down))
        return priority
    end,
    action = function()
        for gd = 1, 6 do
            Memoried.getOperationAt(gd).suck()
        end
    end
}
Rules.add {
    name = "mining: collect map",
    when = function ()
        local request = Memoried.getRequest("mining")
        if not request then return false end

        local range = request.range
        if not range then return false end

        -- 周りを探索
        local cx, cy, cz = Memoried.currentPosition()
        for dx = -2, 2 do
            for dy = -2, 2 do
                for dz = -2, 2 do
                    local tx, ty, tz = cx + dx, cy + dy, cz + dz
                    if Box3.vsPoint(range, tx, ty, tz) then
                        -- 採掘範囲内で
                        local direction, mx, my, mz = findNearMovablePositionIfMissingMap(tx, ty, tz)
                        if direction then
                            -- マップ情報が無くて、そのブロックの周りに行けるブロックがある
                            return
                                collectMapInfoPriority * miningCollectMapInfoPriorityRatio,
                                direction,
                                mx, my, mz
                        end
                    end
                end
            end
        end

        -- ランダムに探索
        local maxSearchCount = 20
        for _ = 1, maxSearchCount do
            local tx = math.random(range.minX, range.maxX)
            local ty = math.random(range.minY, range.maxY)
            local tz = math.random(range.minZ, range.maxZ)
            -- 採掘範囲内で

            local direction, mx, my, mz = findNearMovablePositionIfMissingMap(tx, ty, tz)
            if direction then
                -- マップ情報が無くて、そのブロックの周りに行けるブロックがある
                return
                    collectMapInfoPriority * miningCollectMapInfoPriorityRatio,
                    direction,
                    mx, my, mz
            end
        end
        return false
    end,
    action = function(_, gd, mx, my, mz)

        -- 攻撃しないで移動
        local ok, reason = mineTo(20, mx, my, mz, false, true)
        if not ok then Logger.logError(reason) end

        Memoried.memory.lastCollectMapClock = os.clock()
        collectMissingMapAt(gd)
    end
}
Rules.add {
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

local miningToolName = "minecraft:diamond_pickaxe"
---@param item ItemDetail
local function isMiningTool(item)
    return item.name == miningToolName and item.damage == 0
end
local function findItemInInventory(predicate)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and predicate(item) then
            return i
        end
    end
    return
end
local function findMiningToolInInventory()
    return findItemInInventory(isMiningTool)
end

---@class ItemDetail
---@field public count integer
---@field public damage integer
---@field public name string

---@param predicate fun(itemDetail: ItemDetail): boolean
---@return integer x
---@return integer y
---@return integer z
local function findItemInNearDrop(predicate)
    local cx, cy, cz = Memoried.currentPosition()

    -- 近くを探索
    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                local tx, ty, tz = cx + dx, cy + dy, cz + dz
                local location = Memoried.getLocation(tx, ty, tz)
                if location then
                    local drops = location.drops
                    if drops then
                        for i = #drops, 1, -1 do
                            local drop = drops[i]
                            if drop and predicate(drop) then
                                return tx, ty, tz
                            end
                        end
                    end
                end
            end
        end
    end

    -- 最後に捨てた場所を探索
    local dropHistory = Memoried.memory.dropHistory
    for i = #dropHistory, 1, -1 do
        local h = dropHistory[i]
        if predicate(h.item) then
            local p = h.position
            return p[1], p[2], p[3]
        end
    end

    return
end

Rules.add {
    name = "mining: get and equip pickaxe",
    when = function()
        if not Memoried.hasRequest("mining") then return false end
        if
            Memoried.equippedItemName(Left) == miningToolName or
            Memoried.equippedItemName(Right) == miningToolName
        then
            return false
        end

        -- インベントリを探す
        local slotNumber = findMiningToolInInventory()
        if slotNumber then
            return defaultRequestPriority * equipToolPriorityRatio, "inventory", slotNumber
        end

        -- 周りのドロップアイテム ( やチェスト ) を探す
        local tx, ty, tz = findItemInNearDrop(isMiningTool)
        -- TODO: アイテムが落ちた方向を追跡する
        if tx then
            local gd, mx, my, mz = findNearMovablePosition(tx, ty, tz)
            if gd then return defaultRequestPriority * equipToolPriorityRatio, "drop", gd, mx, my, mz end
        end

        return false
    end,
    action = function (self, type, v1, v2, v3, v4)
        if type == "inventory" then
            local slotNumber = v1

            -- 持つ方向を決定
            local direction = Right
            if
                Memoried.equippedItemName(Right) ~= nil and
                Memoried.equippedItemName(Left) == nil
            then
                direction = Left
            end

            turtle.select(slotNumber)
            return Memoried.getOperation(direction).equip()
        end
        if type == "drop" then
            local gd, x, y, z = v1, v2, v3, v4

            -- その場所まで移動
            local ok, reason = mineTo(20, x, y, z, true, true)
            if not ok then Logger.logDebug(self.name, reason) return end

            -- アイテムをチェストや地面から回収
            local ok, reason = suckIf(isMiningTool, gd, 20)
            if not ok then Logger.logDebug(self.name, reason) end
            return
        end
        Logger.logDebug(self.name, "unknown item location kind", type)

        return false
    end
}
Rules.add {
    name = "mining: move to range",
    when = function ()
        local request = Memoried.getRequest("mining")
        if not request then return false end

        local x, y, z = Memoried.currentPosition()
        if inMiningRequestRange(request, x, y, z) then return false end

        return defaultRequestPriority * moveToRangePriorityRatio
    end,
    action = function (self)
        local request = Memoried.getRequest("mining")
        local range = request.range
        local cx, cy, cz = Memoried.currentPosition()
        local x = Ex.clamp(cx, range.minX, range.maxX)
        local y = Ex.clamp(cy, range.minY, range.maxY)
        local z = Ex.clamp(cz, range.minZ, range.minZ)

        -- 掘らない
        local ok, reason = mineTo(10, x, y, z, true, false)

        if not ok then Logger.logDebug("["..self.name.."]", reason) end
    end
}
local function locationIsChest(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    if not location then return false end

    -- チェスト
    local inspect = location.inspect
    if inspect and inspect.name == "minecraft:chest" then return true end

    -- 触ったことがあって、捨てたことがあるならチェスト?
    if location.detect then
        local drops = location.drops
        if drops and 1 < #drops then return true end
    end

    return false
end
local function findChestInMemory()

    -- チェスト履歴から検索
    local maxSearchCount = 20
    local chestHistory = Memoried.memory.chestHistory
    for i = #chestHistory, math.max(1, #chestHistory - maxSearchCount), -1 do
        local position = chestHistory[i]
        local x, y, z = position[1], position[2], position[3]

        -- ( 記憶上の ) 最新の情報を取得
        if locationIsChest(x, y, z) then return x, y, z end

        -- チェストでなかったので履歴から削除
        table.remove(chestHistory, i)
        Logger.logInfo("remove chest history", x, y, z)
    end

    -- 捨て履歴から検索
    local maxSearchCount = 20
    local history = Memoried.memory.dropHistory

    for i = #history, math.max(1, #history - maxSearchCount), -1 do
        local position = history[i].position
        local x, y, z = position[1], position[2], position[3]
        if locationIsChest(x, y, z) then return x, y, z end
    end
    return
end
local function getUsingRatio()
    local usingRatio = 0
    for i = 1, 16 do
        local count = turtle.getItemCount(i)
        if count ~= 0 then
            local space = turtle.getItemSpace(i)
            usingRatio = usingRatio + (count / (count + space)) * (1 / 16)
        end
    end
    return usingRatio
end
Rules.add {
    name = "mining: drop to chest",
    when = function ()
        if not Memoried.hasRequest "mining" then return false end

        -- 前回の格納から一定時間が経過するか
        local previousDropClock = Memoried.memory.previousDropClock or 0
        local dropSpan = os.clock() - previousDropClock

        -- 最初の 30秒 までは優先度 0
        -- 次の 120秒 で優先度 1 まで上昇
        -- 次の 120秒 で優先度 2 まで上昇
        -- 0s => 0
        -- 30s => 0
        -- 90s => 0.5
        -- 150s => 1
        -- 270s => 2
        local dropClockRatio = math.max(0, dropSpan - 30) / 120

        -- 占有率が一定以上になるか
        local ratio = dropClockRatio + getUsingRatio()
        if ratio < 0.1 then return false end

        -- そもそもチェストの場所を知らない
        local x, y, z = findChestInMemory()
        if not x then return false end

        -- チェストに到達できない
        local d, mx, my, mz = findNearMovablePosition(x, y, z)
        if not d then return false end

        local priority = defaultDropChestPriority * ratio
        return priority, d, mx, my, mz
    end,
    action = function(self, d, mx, my, mz)

        -- 移動
        local ok, reason = mineTo(20, mx, my, mz, true, false)
        if not ok then return Logger.logInfo("["..self.name.."]", reason) end

        -- 改めてチェストか確認
        Memoried.getOperationAt(d).inspect()
        local nx, ny, nz = directionToNormal(d)
        if not locationIsChest(mx + nx, my + ny, mz + nz) then return end

        -- ドロップ
        for i = 1, 16 do
            if 0 < turtle.getItemCount(i) then
                turtle.select(i)
                Memoried.getOperationAt(d).drop()
            end
        end
        Memoried.memory.previousDropClock = os.clock()
    end
}
local function isMined(location)
    local inspect = location.inspect
    if location.move == true or inspect == false then return true end
    if inspect == nil then return false end
    local name = inspect.name
    if name == "minecraft:chest" or name == "minecraft:torch" then return true end
    return false
end

Rules.add {
    name = "mining: check complete",
    when = function()
        local request = Memoried.getRequest "mining"
        if not request then return false end

        return defaultRequestPriority * 0.1, request
    end,
    action = function(self, request)
        local range = request.range
        local checkX = request.checkX or range.minX
        local checkY = request.checkY or range.minY
        local checkZ = request.checkZ or range.minZ

        local maxCheckCount = 100
        local checkCount = 0
        while checkCount <= maxCheckCount do
            local location = Memoried.getLocation(checkX, checkY, checkZ)
            if not location or not isMined(location) then
                request.checkX = checkX
                request.checkY = checkY
                request.checkZ = checkZ
                Logger.logDebug("find mining point: ", checkX, checkY, checkZ, " in ", pretty(range))
                local ok, reason = mineTo(20, checkX, checkY, checkZ, true, false)
                if not ok then Logger.logError("["..self.name.."]", "mineTo failed", reason) end
                return
            end
            checkCount = checkCount + 1

            if
                checkX == range.maxX and
                checkY == range.maxY and
                checkZ == range.maxZ
            then
                mainLogger.log("mining complete")
                Memoried.removeRequest "mining"
                return
            end

            if range.maxX <= checkX then
                checkX = range.minX
                if range.maxY <= checkY then
                    checkY = range.minY
                    checkZ = checkZ + 1
                else
                    checkY = checkY + 1
                end
            else
                checkX = checkX + 1
            end
        end
        Logger.logDebug("tired at ", checkX, checkY, checkZ, "("..tostring(maxCheckCount).." checks)")
        return
    end
}
local function findCombustibleInInventory()
    if turtle.getFuelLimit() == "unlimited" then return false end

    local itemToFuelLevel = Memoried.memory.itemToFuelLevel
    for i = 1, 16 do
        local item = turtle.getItemDetail()
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

local function manhattanDistance(ax, ay, az, bx, by, bz)
    return math.abs(ax - bx) + math.abs(ay - by) + math.abs(az - bz)
end
Rules.add {
    name = "set torch",
    when = function()
        -- TODO トーチをクラフト

        -- トーチを持っていて
        local slot = nil
        for i = 1, 16 do
            local item = turtle.getItemDetail(i)
            if item and item.name == "minecraft:torch" then slot = i break end
        end
        if not slot then return false end

        -- 近くにトーチを置いたことがなく
        local x, y, z = Memoried.currentPosition()
        local history = Memoried.memory.setTorchHistory
        for i = #history, math.max(1, #history - 10), -1 do
            local p = history[i]
            local tx, ty, tz = p[1], p[2], p[3]
            local location = Memoried.getLocation(tx, ty, tz)
            if location and (location.move == true or (location.inspect and location.inspect.name ~= "minecraft:torch")) then
                -- トーチでないので削除
                table.remove(history, i)
                Logger.logInfo("remove torch history", tx, ty, tz)
            end
            if manhattanDistance(x, y, z, tx, ty, tz) < 8 then return false end
        end

        for gd = 1, 6 do
            local tx, ty, tz = globalDirectionToPosition(gd)
            local location = Memoried.getLocation(tx, ty, tz)

            -- トーチを設置できる空間があり
            if location and (location.move == true or location.inspect == false) then
                local hasBaseBlock = false

                -- トーチが刺さるブロックがあるか探す ( 天井を除く )
                for baseDirection = 1, 5 do
                    local nx, ny, nz = directionToNormal(baseDirection)
                    local baseLocation = Memoried.getLocation(tx + nx, ty + ny, tz + nz)
                    if baseLocation and (baseLocation.move == false or baseLocation.detect == true) then
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
Rules.add {
    name = "refuel",
    when = function()
        local fuel = turtle.getFuelLevel()
        if fuel == "unlimited" then return false end
        if 0.5 < fuel / turtle.getFuelLimit() then return false end

        -- インベントリを探す
        local slotNumber = findCombustibleInInventory()
        if slotNumber then
            return 1, "inventory", slotNumber
        end

        -- 周りのドロップアイテム ( やチェスト ) を探す
        local tx, ty, tz = findItemInNearDrop(combustible)

        -- TODO: アイテムが落ちた方向を追跡する
        if tx then
            local gd, mx, my, mz = findNearMovablePosition(tx, ty, tz)
            if gd then return 1, "drop", gd, mx, my, mz end
        end

    end,
    action = function(self, type, v1, v2, v3, v4)
        if type == "inventory" then
            local slotNumber = v1
            if turtle.getSelectedSlot() ~= slotNumber then
                turtle.select(slotNumber)
            end
            turtle.refuel()
        end
        if type == "drop" then
            local gd, x, y, z = v1, v2, v3, v4

            -- その場所まで移動
            local ok, reason = mineTo(20, x, y, z, true, true)
            if not ok then Logger.logDebug(self.name, reason) return end

            -- アイテムをチェストや地面から回収
            local ok, reason = suckIf(combustible, gd, 20)
            if not ok then Logger.logDebug(self.name, reason) end
            return
        end
        return false
    end,
}

-- # ルールの評価
-- - マップ情報が増えた
-- - 燃料が増えた
-- - 燃料チェストや燃料が落ちている場所を発見した
-- - リクエストを達成した
-- - リクエストの達成度を更新した
-- - リクエストがあるのに達成度が変化なしだったら減点 ( 行動当たりの時間効率 )
-- - 採掘リクエスト中
--   - 範囲内の空気ブロックが増えた
--   - 範囲内の松明ブロックが増えた
--   - チェストに入れた数が増えた

---@type MiningOptions
local function getDefaultMiningOptions()
    return {
        down = 2,
        forward = 3,
        right = 4,
        ["offset-y"] = -1,
    }
end

---@param arguments string[]
---@param options MiningOptions
local function parseMiningOptions(options, arguments)
    while 0 < #arguments do
        if
            ArgParser.parseNamedOption(arguments, "down", "d", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "forward", "f", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "right", "r", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "up", "u", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "back", "b", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "left", "l", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "offset-x", "x", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "offset-y", "y", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "offset-z", "z", options, tonumber)
        then
        else
            return error("unrecognized argument: "..arguments[1])
        end
    end
    return true
end

local function miningCommand(arguments)
    mainLogger.log("# mining")
    local options = getDefaultMiningOptions()
    parseMiningOptions(options, arguments)
    mainLogger.log("options: ")

    local offsetX, offsetY, offsetZ =
        options["offset-x"], options["offset-y"], options["offset-z"]
    local forward, left, back, right, down, up =
        options.forward, options.left, options.back, options.right, options.down, options.up

    if offsetX then mainLogger.log("- offset-x", offsetX) end
    if offsetY then mainLogger.log("- offset-y", offsetY) end
    if offsetZ then mainLogger.log("- offset-z", offsetZ) end
    if down then mainLogger.log("- down", down) end
    if up then mainLogger.log("- up", up) end
    if forward then mainLogger.log("- forward", forward) end
    if back then mainLogger.log("- back", back) end
    if right then mainLogger.log("- right", right) end
    if left then mainLogger.log("- left", left) end
    mainLogger.log("")

    local x, y, z = Memoried.currentPosition()
    if offsetX then x = x + offsetX end
    if offsetY then y = y + offsetY end
    if offsetZ then z = z + offsetZ end

    local box = Box3.newFromPoint(x, y, z)
    if right then Box3.expandByPoint(box, x + right, y, z) end
    if left then Box3.expandByPoint(box, x - left, y, z) end
    if up then Box3.expandByPoint(box, x, y + up, z) end
    if down then Box3.expandByPoint(box, x, y - down, z) end
    if forward then Box3.expandByPoint(box, x, y, z + forward) end
    if back then Box3.expandByPoint(box, x, y, z - back) end

    Memoried.addRequest({
        name = "mining",
        options = options,
        range = box
    })
end

return {
    mainLogger = mainLogger,
    miningCommand = miningCommand,
}

