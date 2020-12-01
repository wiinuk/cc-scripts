local Memoried = require "memoried"
local AStar = require "astar"
local Logger = require "logger"
local Vec3 = require "vec3"

local DiamondPickaxe = "minecraft:diamond_pickaxe"
local Torch = "minecraft:torch"
local CraftingTable = "minecraft:crafting_table"
local Chest = "minecraft:chest"

local Left = Memoried.Left
local Right = Memoried.Right
local Back = Memoried.Back
local Forward = Memoried.Forward
local Up = Memoried.Up
local Down = Memoried.Down


---@return integer|nil slotNumber
local function findLastEmptySlot()
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

local function isMovableInMemory(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    return location and (location.detect == false or location.move == true)
end

local finderMaxStep = 100
-- TODO: 探索器や経路をキャッシュする

---@param isMovable fun(x: integer, y: integer, z: integer): boolean
local function getPath(sx, sy, sz, gx, gy, gz, isMovable)

    local finder = AStar.newFinder(isMovable or isMovableInMemory)
    AStar.initialize(finder, sx, sy, sz, gx, gy, gz)

    local path, state = AStar.resume(finder, finderMaxStep)
    if path then return path end
    if state == "ready" then return nil end
    if state == "suspended" then return nil, AStar.getBestPath(finder) end
    error("unknown finder state: "..tostring(state))
end

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
---@param enableNoMovableGoal boolean|nil
---@param isMovable fun(x: integer, y: integer, z: integer): boolean
---@return boolean findCompletePath
---@return integer[] path
---@return integer globalDirection
local function findNearMovablePath(tx, ty, tz, enableNoMovableGoal, isMovable)
    local lastBestPath = nil
    local lastBestPathDirection = nil
    local lastBestScore = 1/0
    local isMovable = isMovable or isMovableInMemory
    for globalDirection = 1, 6 do
        -- ゴール候補の移動可能な場所をさがす

        local nx, ny, nz = directionToNormal(globalDirection)
        local mx, my, mz = tx - nx, ty - ny, tz - nz

        -- パスのゴールとなる移動先は、移動可能な場所を選ぶ必要がある
        if enableNoMovableGoal or isMovable(mx, my, mz) then
            local cx, cy, cz = Memoried.currentPosition()
            local path, bestPath, bestScore = getPath(cx, cy, cz, mx, my, mz, isMovable)
            if path then return true, path, globalDirection end
            if bestPath and bestScore <= lastBestScore then
                lastBestPath = bestPath
                lastBestPathDirection = globalDirection
                lastBestScore = bestScore
            end
        end
    end
    return false, lastBestPath, lastBestPathDirection
end

local function findPath(tx, ty, tz, isMovable)
    local cx, cy, cz = Memoried.currentPosition()
    local path, bestPath = getPath(cx, cy, cz, tx, ty, tz, isMovable or isMovableInMemory)
    if path then
        return true, path
    else
        return false, bestPath
    end
end

local importantItems = {
    [DiamondPickaxe] = true,
    [Torch] = true,
    [CraftingTable] = true,
    [Chest] = true
}
local function isImportantItem(name)
    return not not importantItems[name]
end

local function limitedDig(globalDirection)
    local ok, info = Memoried.getOperationAt(globalDirection).inspect()
    if not ok then return false, info end

    local name = info.name
    if isImportantItem(name) then
        return false, "important item"
    end
    return Memoried.getOperationAt(globalDirection).dig()
end

---@param globalDirection integer
---@param disableDig boolean|function|nil
---@param disableAttack boolean|function|nil
---@param isUnlimited boolean|nil
local function mineMove1(globalDirection, disableDig, disableAttack, isUnlimited)

    if Memoried.getOperationAt(globalDirection).move() then return true end
    -- 行けなかった

    -- ブロックがあるなら掘る
    local canDig = true
    if disableDig == true then canDig = false end
    if type(disableDig) == "function" then
        canDig = not disableDig(globalDirection)
    end

    if canDig and Memoried.getOperationAt(globalDirection).detect() then

        -- 掘る
        if isUnlimited then
            Memoried.getOperationAt(globalDirection).dig()
        else
            limitedDig(globalDirection)
        end

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

    local canAttack = true
    if disableAttack == true then canAttack = false end
    if type(disableAttack) == "function" then
        canAttack = not disableAttack(globalDirection)
    end

    if canAttack then
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

local function mineTo(maxRetryCount, targetX, targetY, targetZ, disableDig, disableAttack, isUnlimited)
    local maxRetryCount = math.max(0, maxRetryCount)
    local retryCount = 0
    local lastReason = nil

    while true do
        if maxRetryCount < retryCount then return false, lastReason end

        local cx, cy, cz = Memoried.currentPosition()

        if cx == targetX and cy == targetY and cz == targetZ then return true end

        if targetX < cx then
            local ok, reason = mineMove1(Left, disableDig, disableAttack, isUnlimited)
            if not ok then lastReason = reason end
        end
        if cx < targetX then
            local ok, reason = mineMove1(Right, disableDig, disableAttack, isUnlimited)
            if not ok then lastReason = reason end
        end
        if targetZ < cz then
            local ok, reason = mineMove1(Back, disableDig, disableAttack, isUnlimited)
            if not ok then lastReason = reason end
        end
        if cz < targetZ then
            local ok, reason = mineMove1(Forward, disableDig, disableAttack, isUnlimited)
            if not ok then lastReason = reason end
        end
        if cy < targetY then
            local ok, reason = mineMove1(Up, disableDig, disableAttack, isUnlimited)
            if not ok then lastReason = reason end
        end
        if targetY < cy then
            local ok, reason = mineMove1(Down, disableDig, disableAttack, isUnlimited)
            if not ok then lastReason = reason end
        end

        local d1 = Vec3.manhattanDistance(cx, cy, cz, targetX, targetY, targetZ)
        local c2x, c2y, c2z = Memoried.currentPosition()
        local d2 = Vec3.manhattanDistance(c2x, c2y, c2z, targetX, targetY, targetZ)
        if d1 <= d2 then
            retryCount = retryCount + 1
        end
    end
end

local function goToGoal(maxRetryCount, path, disableDig, disableAttack, unlimited)
    for i = 1, #path, 3 do
        local px, py, pz = path[i], path[i+1], path[i+2]
        local ok, reason = mineTo(maxRetryCount, px, py, pz, disableDig, disableAttack, unlimited)
        if not ok then return ok, reason end
    end
    return true
end

local function maybeAir(location)
    return location and (location.move == true or location.inspect == false)
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
        local slot = findLastEmptySlot()
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

local function distanceToHome()
    local cx, cy, cz = Memoried.currentPosition()
    return Vec3.manhattanDistance(cx, cy, cz, 0, 0, 0)
end

local function getNeedFuelLevel()
    local level = turtle.getFuelLevel()
    if level ~= "unlimited" then return 0 end

    -- ホームまでの距離の1.5倍
    return distanceToHome() * 1.5
end

---@param globalDirection integer
---@return table|nil itemDetail
---@return string reason
local function inspectItemAt(globalDirection)
    compactItems()
    local emptySlot = findLastEmptySlot()
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

---@class GoToOptions
---@field public maxRetryCount number|nil
---@field public isMovable fun(x: integer, y: integer, z: integer): boolean @ allow nil
---@field public disableDig fun(globalDirection: number): boolean @ allow nil|boolean
---@field public disableAttack fun(globalDirection: number): boolean @ allow nil|boolean
local emptyOptions = {}

---@param x number
---@param y number
---@param z number
---@param options GoToOptions|nil
local function goTo(x, y, z, options)
    options = options or emptyOptions

    local complete, path = findPath(x, y, z, options.isMovable)
    if not complete then return false, "path not found" end
    local ok, reason = goToGoal(options.maxRetryCount or 10, path, options.disableDig, options.disableAttack)
    if not ok then return false, reason end
    return true
end

return {
    directionToNormal = directionToNormal,
    globalDirectionToPosition = globalDirectionToPosition,
    findLastEmptySlot = findLastEmptySlot,
    findItemInNearDrop = findItemInNearDrop,
    findPath = findPath,
    findNearMovablePath = findNearMovablePath,
    suckIf = suckIf,
    compactItems = compactItems,
    goToGoal = goToGoal,
    goTo = goTo,
    isMovableInMemory = isMovableInMemory,
    distanceToHome = distanceToHome,
    getNeedFuelLevel = getNeedFuelLevel,
    isImportantItem = isImportantItem,
    maybeAir = maybeAir,
    mineTo = mineTo,
    limitedDig = limitedDig,
    isMapMissing = isMapMissing,
    collectMissingMapAt = collectMissingMapAt,
}
