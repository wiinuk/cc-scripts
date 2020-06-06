
---@version: 0.4.5
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Ex = require "extensions"
local Logger = require "logger"
local Rules = require "rules"
local pretty = require "pretty"
local AStar = require "astar"

local Forward = Memoried.Forward
local Left = Memoried.Left
local Back = Memoried.Back
local Right = Memoried.Right
local Down = Memoried.Down
local Up = Memoried.Up

local DiamondPickaxe = "minecraft:diamond_pickaxe"
local Torch = "minecraft:torch"
local CraftingTable = "minecraft:crafting_table"
local Stick = "minecraft:stick"
local Coal = "minecraft:coal"
local Planks = "minecraft:planks"
local Log = "minecraft:log"
local Chest = "minecraft:chest"

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
    if name == Chest or name == Torch then
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

local DisableDig = true
local EnableDig = false
local DisableAttack = true
local EnableAttack = false

local function goToGoal(maxRetryCount, path, disableDig, disableAttack)
    for i = 1, #path, 3 do
        local px, py, pz = path[i], path[i+1], path[i+2]
        local ok, reason = mineTo(maxRetryCount, px, py, pz, disableDig, disableAttack)
        if not ok then return ok, reason end
    end
    return true
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

local function suckMany(globalDirection)
    while true do
        local ok, reason = Memoried.getOperationAt(globalDirection).suck()
        if not ok then return reason end
    end
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
        if name == Chest or name == Torch then
            return priority
        end
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

local function isMovableInMemory(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    return location and (location.detect == false or location.move == true)
end

local finderMaxStep = 100
-- TODO: 探索器や経路をキャッシュする
local function getPath(sx, sy, sz, gx, gy, gz)

    local finder = AStar.newFinder(isMovableInMemory)
    AStar.initialize(finder, sx, sy, sz, gx, gy, gz)

    local path, state = AStar.resume(finder, finderMaxStep)
    if path then return path end
    if state == "ready" then return nil end
    if state == "suspended" then return nil, AStar.getBestPath(finder) end
    error("unknown finder state: "..tostring(state))
end

--- まず対象位置のそばにある移動可能位置を特定する。
--- 次に、タートルの現在位置から移動可能位置へのパスと、移動可能位置から見た対象位置の大域方向を返す
---
--- ---
--- ### 例:
--- 前提
--- - 現在 (0,0,0), 対象 (0,0,3) とする
--- - 全ての位置は移動可能とする
---
--- 処理
--- - 対象のそばの (0,0,2) を移動可能位置と決定する
--- - 移動可能位置 (0,0,2) をゴールとする
--- - 現在の (0,0,0) から (0,0,2) へのパスを検索する
--- - パス `{ 0,0,0, 0,0,1, 0,0,2 }` と、ゴールから見た対象の方向 `Forward` が返る
---@param tx integer
---@param ty integer
---@param tz integer
---@return boolean findCompletePath
---@return integer[] path
---@return integer globalDirection
local function findNearMovablePath(tx, ty, tz)

    local lastBestPath = nil
    local lastBestPathDirection = nil
    for globalDirection = 1, 6 do
        -- ゴール候補の移動可能な場所をさがす

        local nx, ny, nz = directionToNormal(globalDirection)
        local mx, my, mz = tx - nx, ty - ny, tz - nz

        -- パスのゴールとなる移動先は、移動可能な場所を選ぶ必要がある
        if isMovableInMemory(mx, my, mz) then
            local cx, cy, cz = Memoried.currentPosition()
            local path, bestPath = getPath(cx, cy, cz, mx, my, mz)
            if path then return true, path, globalDirection end
            if bestPath then
                lastBestPath = bestPath
                lastBestPathDirection = globalDirection
            end
        end
    end
    return false, lastBestPath, lastBestPathDirection
end
Rules.add {
    name = "mining: dig around",
    when = function ()
        local request = Memoried.getRequest "mining"
        if not request then return false end

        local priority = false
        local direction = nil
        for gd = 1, 6 do
            local nextPriority, p = whenMine(priority, request, gd)
            if p then
                priority = nextPriority
                direction = gd
            end
        end
        return priority, direction
    end,
    action = function (self, globalDirection)
        local ok, reason = limitedDig(globalDirection)
        if not ok then

            -- 怪しい記憶を削除
            local tx, ty, tz = globalDirectionToPosition(globalDirection)
            local location = Memoried.getLocation(tx, ty, tz)
            Memoried.clearLocation(location)

            Logger.logError(self.name, "error", reason, "gd", tostring(globalDirection))
        end
    end,
}
Rules.add {
    name = "mining: move to block",
    when = function ()
        local request = Memoried.getRequest "mining"
        if not request then return false end

        local range = request.range
        if not range then return false end

        -- 周りをランダムに探索
        local x, y, z = Memoried.currentPosition()
        x = Memoried.memory.lastFindX or x
        y = Memoried.memory.lastFindY or y
        z = Memoried.memory.lastFindZ or z
        local dx, dy, dz = math.random(-2, 2), math.random(-2, 2), math.random(-2, 2)
        local x, y, z = x + dx, y + dy, z + dz
        if Box3.vsPoint(range, x, y, z) and Memoried.canDigInMemory(x, y, z) then
            local complete, path = findNearMovablePath(x, y, z)
            if path then
                if complete then
                    Memoried.memory.lastFindX = x
                    Memoried.memory.lastFindY = y
                    Memoried.memory.lastFindZ = z
                    return 0.5, path
                else
                    return 0.4, path
                end
            end
        end

        -- ランダムに探索
        local x = math.random(range.minX, range.maxX)
        local y = math.random(range.minY, range.maxY)
        local z = math.random(range.minZ, range.maxZ)
        if Memoried.canDigInMemory(x, y, z) then
            local complete, path = findNearMovablePath(x, y, z)
            if path then
                if complete then
                    Memoried.memory.lastFindX = x
                    Memoried.memory.lastFindY = y
                    Memoried.memory.lastFindZ = z
                    return 0.3, path
                else
                    return 0.2, path
                end
            end
        end
        return false
    end,
    action = function (_, path)
        local ok, reason = goToGoal(20, path, EnableDig, EnableAttack)
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

        -- ランダムに周りのブロックを選択
        local cx, cy, cz = Memoried.currentPosition()
        local dx, dy, dz = math.random(-2, 2), math.random(-2, 2), math.random(-2, 2)
        local tx, ty, tz = cx + dx, cy + dy, cz + dz

        if Box3.vsPoint(range, tx, ty, tz) then
            -- ブロックが採掘範囲内で

            local location = Memoried.getLocation(tx, ty, tz)
            if isMapMissing(location) then
                -- マップ情報が無くて

                local complete, path, direction = findNearMovablePath(tx, ty, tz)
                if path then
                    -- そのブロックに到達できる
                    if complete then
                        return
                            collectMapInfoPriority * miningCollectMapInfoPriorityRatio,
                            direction, path
                    else
                        return
                            collectMapInfoPriority * miningCollectMapInfoPriorityRatio * 0.9,
                            direction, path
                    end
                end
            end
        end

        -- 採掘範囲内をランダムに探索
        local tx = math.random(range.minX, range.maxX)
        local ty = math.random(range.minY, range.maxY)
        local tz = math.random(range.minZ, range.maxZ)
        local location = Memoried.getLocation(tx, ty, tz)
        if isMapMissing(location) then
            local complete, path, direction = findNearMovablePath(tx, ty, tz)
            if path then
                if complete then
                    return
                        collectMapInfoPriority * miningCollectMapInfoPriorityRatio,
                        direction,
                        path
                else
                    return
                        collectMapInfoPriority * miningCollectMapInfoPriorityRatio * 0.9,
                        direction,
                        path
                end
            end
        end
        return false
    end,
    action = function(_, gd, path)
        local ok, reason = goToGoal(20, path, EnableDig, DisableAttack)
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

---@param item ItemDetail
local function isMiningTool(item)
    return item.name == DiamondPickaxe and item.damage == 0
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
            Memoried.equippedItemName(Left) == DiamondPickaxe or
            Memoried.equippedItemName(Right) == DiamondPickaxe
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
            local complete, path, gd = findNearMovablePath(tx, ty, tz)
            local ratio = 1
            if not complete then ratio = 0.9 end
            if path then return defaultRequestPriority * equipToolPriorityRatio * ratio, "drop", gd, path end
        end

        return false
    end,
    action = function (self, type, v1, v2)
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
            local gd, path = v1, v2

            -- その場所まで移動
            local ok, reason = goToGoal(20, path, DisableDig, DisableAttack)
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
        local z = Ex.clamp(cz, range.minZ, range.maxZ)

        local path, bestPath = getPath(cx, cy, cz, x, y, z)
        local ok, reason

        -- 掘らない
        if path then
            ok, reason = goToGoal(20, path, DisableDig, EnableAttack)
        elseif bestPath then
            ok, reason = goToGoal(20, bestPath, DisableDig, EnableAttack)
        else
            ok, reason = mineTo(10, x, y, z, DisableDig, EnableAttack)
        end

        if not ok then Logger.logDebug("["..self.name.."]", reason) end
    end
}
local function locationIsChest(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    if not location then return false end

    -- チェスト
    local inspect = location.inspect
    if inspect and inspect.name == Chest then return true end

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

local function manhattanDistance(ax, ay, az, bx, by, bz)
    return math.abs(ax - bx) + math.abs(ay - by) + math.abs(az - bz)
end
local function distanceToHome()
    local cx, cy, cz = Memoried.currentPosition()
    return manhattanDistance(cx, cy, cz, 0, 0, 0)
end
local function getNeedFuelLevel()
    local level = turtle.getFuelLevel()
    if level ~= "unlimited" then return 0 end

    -- ホームまでの距離の1.5倍
    return distanceToHome() * 1.5
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
        if ratio < 0.5 then return false end

        -- そもそもチェストの場所を知らない
        local x, y, z = findChestInMemory()
        if not x then return false end

        -- チェストに到達できない
        local complete, path, direction = findNearMovablePath(x, y, z)
        if not path then return false end

        if not complete then ratio = ratio * 0.9 end
        local priority = defaultDropChestPriority * ratio
        return priority, direction, path
    end,
    action = function(self, d, path)

        -- 移動
        local ok, reason = goToGoal(20, path, DisableDig, EnableAttack)
        if not ok then return Logger.logInfo("["..self.name.."]", reason) end

        -- 改めてチェストか確認
        Memoried.getOperationAt(d).inspect()
        local cx, cy, cz = Memoried.currentPosition()
        local nx, ny, nz = directionToNormal(d)
        local tx, ty, tz = cx + nx, cy + ny, cz + nz
        if not locationIsChest(tx, ty, tz) then
            return Logger.logInfo("["..self.name.."]", tx, ty, tz, "is not chest")
        end

        local needFuelLevel = getNeedFuelLevel()

        -- ドロップ
        local count = 64
        if 95 < math.random(1, 100) then
            d = Up
            count = 1
        end
        for i = 1, 16 do
            if 0 < turtle.getItemCount(i) then
                local item = turtle.getItemDetail(i)
                local name = item.name
                if name ~= Torch then
                    local level = Memoried.memory.itemToFuelLevel[name]
                    if level and 0 < needFuelLevel then
                        needFuelLevel = needFuelLevel - (item.count * level)
                    else
                        turtle.select(i)
                        Memoried.getOperationAt(d).drop(count)
                    end
                end
            end
        end
        Memoried.memory.previousDropClock = os.clock()
    end
}
local function isMined(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    if not location then return false end
    local inspect = location.inspect
    if location.move == true or inspect == false then return true end
    if inspect == nil then return false end
    local name = inspect.name
    if name == Chest or name == Torch then return true end
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
            if not isMined(checkX, checkY, checkZ) then
                request.checkX = checkX
                request.checkY = checkY
                request.checkZ = checkZ
                Logger.logDebug("find mining point: ", checkX, checkY, checkZ, " in ", pretty(range))
                local _, path = findNearMovablePath(checkX, checkY, checkZ)
                if path then
                    local ok, reason = goToGoal(20, path, EnableDig, DisableAttack)
                    if not ok then
                        Logger.logError("["..self.name.."]", "goToGoal failed", reason)
                    end
                end
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
        request.checkX, request.checkY, request.checkZ = checkX, checkY, checkZ
        Logger.logDebug("tired at ", checkX, checkY, checkZ, "("..tostring(maxCheckCount).." checks)", pretty(range))
        return
    end
}
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

local function findLastSlotByName(name)
    for i = 16, 1, -1 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then return i end
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
local function findItemSlotBy(predicate)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and predicate(item) then return i end
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
local function maybeAir(location)
    return location and
        (location.detect == false or location.move == true or location.inspect == false)
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
                local emptySlot = findEmptySlot()
                if not emptySlot then return false, "empty slot not found" end

                turtle.select(slot)
                turtle.transferTo(emptySlot)

                if name ~= "" and name ~= nil then

                    -- 配置
                    local fromSlot = findLastSlotByName(name)
                    if not fromSlot then return false, "item not found '"..name.."'" end

                    turtle.select(fromSlot)
                    turtle.transferTo(slot)
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
Rules.add {
    name = "craft torch",
    when = function()
        if findSlotByName(Stick) then return false end    

        local tree, direction = createCraftInfo(Stick)    
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
Rules.add {
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
            if manhattanDistance(x, y, z, tx, ty, tz) < 6 then return false end
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

