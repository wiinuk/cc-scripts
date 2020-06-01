
---@version: 0.3.0
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Ex = require "extensions"
local Logger = require "logger"


local Forward = Memoried.Forward
local Left = Memoried.Left
local Back = Memoried.Back
local Right = Memoried.Right
local Down = Memoried.Down
local Up = Memoried.Up

Logger.addListener(Logger.fileWriterListener("/logs/mine.log"))

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

---@param globalDirection integer
---@param disableDig boolean|nil
---@param disableAttack boolean|nil
local function mineMove1(globalDirection, disableDig, disableAttack)

    if Memoried.getOperationAt(globalDirection).move() then return true end
    -- 行けなかった

    -- ブロックがあるなら掘る
    if not disableDig and Memoried.getOperationAt(globalDirection).detect() then

        -- 掘る
        Memoried.getOperationAt(globalDirection).dig()

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
        if targetX < currentX then ok, reason = mineMove1(Right, disableDig, disableAttack)
        elseif currentX < targetX then ok, reason = mineMove1(Left, disableDig, disableAttack)
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
        local ii = turtle.getItemDetail(i)
        if ii then
            for j = i + 1, 16 do
                local ji = turtle.getItemDetail(j)
                if ji and ii.name == ji.name then
                    turtle.select(j)
                    turtle.transferTo(i)
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
    if not ok then Logger.logDebug("drop many failure: ", reason) end
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
        turtle.select(slot)

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

---@type MiningOptions
local function getDefaultMiningOptions()
    return {
        down = 2,
        forward = 3,
        right = 4,
    }
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
local equipToolPriorityRatio = 0.1

---@param priority number
---@param request Request
---@param direction integer
local function whenMine(priority, request, direction)
    ---@type DirectionOperations
    local d = Memoried.getOperation(direction)

    if not d.detect() then return priority end

    local x, y, z = Memoried.currentPosition()
    local nx, ny, nz = d.currentNormal()
    if not inMiningRequestRange(request, x + nx, y + ny, z + nz) then return priority end

    local p = Memoried.memory.requestPriority or defaultRequestPriority
    p = p * minePriorityRatio * miningPriorityRatios[direction]

    -- if isSunLight(x, y, z) then
    --     p = p * sunLightMiningPriorityRatio
    -- end

    return (priority or 0) + p, p
end

---@param globalDirection integer
---@return table|nil itemDetail
---@return string reason
local function inspectItemAt(globalDirection)
    local emptySlot = findEmptySlot()
    if not emptySlot then return nil, "empty slot not found" end
    local oldSlot = turtle.getSelectedSlot()
    turtle.select(emptySlot)
    local item = nil
    if Memoried.getOperationAt(globalDirection).suck() then
        item = turtle.getItemDetail()
        Memoried.getOperationAt(globalDirection).drop()
    end
    turtle.select(oldSlot)
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
end

--- 指定された世界方向のマップ情報を取得する
local function collectMissingMapAt(gd)
    Memoried.getOperationAt(gd).detect()
    Memoried.getOperationAt(gd).inspect()
    inspectItemAt(gd)
end

---@return integer|nil globalDirection
---@return integer mx
---@return integer my
---@return integer mz
local function findNearMovablePosition(tx, ty, tz)
    for globalDirection = 1, 6 do
        local nx, ny, nz = directionToNormal(globalDirection)
        local mx, my, mz = tx - nx, ty - ny, tz - nz
        local moveToLocation = Memoried.getLocation(mx, my, mz)
        if moveToLocation and moveToLocation.move == true then
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

---@class Rule
---@field public name string
---@field public when fun(self: Rule): boolean|number, any, any
---@field public action fun(self: Rule, result1: any, result2: any): any

---@type Rule[]
local rules = {}
rules[#rules+1] = {
    name = "mining: dig around",
    when = function (self)
        local request = Memoried.getRequest "mining"
        if not request then return false end

        local priority = false
        local direction = nil
        for d = 6, 1, -1 do
            local nextPriority, p = whenMine(priority, request, d)
            if p then direction = d end
            priority = nextPriority
        end
        Logger.logDebug("[", self.name, "]", "direction", direction)
        return priority, direction
    end,
    action = function (self, direction)
        local ok, reason = Memoried.getOperation(direction).dig()
        if not ok then Logger.logError(self.name, "error", reason, "direction", direction) end
    end,
}
rules[#rules+1] = {
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
rules[#rules+1] = {
    name = "mining: suck",
    when = function ()
        if not Memoried.hasRequest("mining") then return false end

        local priority = false
        for gd = 1, 6 do priority = whenSuckAt(priority, gd) end
        return priority
    end,
    action = function()
        for gd = 1, 6 do
            Memoried.getOperationAt(gd).suck()
        end
    end
}
rules[#rules+1] = {
    name = "mining: collect map",
    when = function ()
        local request = Memoried.getRequest("mining")
        if not request then return false end

        local range = request.range
        if not range then return false end

        -- 周りを探索
        local cx, cy, cz = Memoried.currentPosition()
        for dx = -1, 1 do
            for dy = -1, 1 do
                for dz = -1, 1 do
                    local tx, ty, tz = cx + dx, cy + dy, cz + dz
                    if Box3.vsPoint(range, tx, ty, tz) then
                        -- 採掘範囲内で

                        local direction, mx, my, mz = findNearMovablePositionIfMissingMap(tx, ty, tz)
                        if direction then
                            -- マップ情報が無くて、そのブロックの周りに行けるブロックがある

                            Logger.logDebug("missing: ", tx, ty, tz, ", move to:", mx, my, mz, "direction:", direction)
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

                Logger.logDebug("missing: ", tx, ty, tz, ", move to:", mx, my, mz, "direction:", direction)
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

        collectMissingMapAt(gd)
    end
}
rules[#rules+1] = {
    name = "collect around map",
    when = function()
        local cx, cy, cz = Memoried.currentPosition()
        for globalDirection = 1, 6 do
            local nx, ny, nz = directionToNormal(globalDirection)
            local x, y, z = cx + nx, cy + ny, cz + nz

            local location = Memoried.getLocation(x, y, z)
            if isMapMissing(location) then return collectMapInfoPriority, globalDirection end
        end
        return false
    end,
    action = function (_, gd)
        collectMissingMapAt(gd)
    end,
}

local miningToolName = "minecraft:diamond_pickaxe"
---@param item ItemDetail
local function isMiningTool(item)
    return item.name == miningToolName and item.damage == 0
end
local function findMiningToolInInventory()
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and isMiningTool(item) then
            return i
        end
    end
    return
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

rules[#rules+1] = {
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

-- 範囲まで移動する
-- 同種のアイテムをまとめる
-- インベントリが満タンならチェストまで移動して入れる
-- ホームに帰れなくなりそうなら帰るか燃料を探す ( 高優先度 )

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

local function evaluateRules()
    local maxPriorityRuleCount = 0
    ---@type number
    local maxPriorityRules = {}
    --- `{ result1,..,result5, { result6,..,resultN }, ... }`
    ---@type any[]
    local maxPriorityResults = {}

    local function processWhenResult(maxPriority, rule, priority, result1, result2, result3, result4, result5, ...)
        if priority then
            if maxPriority <= priority then
                if maxPriority < priority then
                    Ex.clearArray(maxPriorityRules)
                    Ex.clearArray(maxPriorityResults)
                    maxPriorityRuleCount = 0
                end
                maxPriorityRuleCount = maxPriorityRuleCount + 1

                maxPriorityRules[maxPriorityRuleCount] = rule

                -- 6 = 固定長の戻り値個数(5) + 残りの可変長戻り値を格納する配列(1)
                local i = maxPriorityRuleCount * 6
                maxPriorityResults[i - 5] = result1
                maxPriorityResults[i - 4] = result2
                maxPriorityResults[i - 3] = result3
                maxPriorityResults[i - 2] = result4
                maxPriorityResults[i - 1] = result5
                if select("#", ...) ~= 0 then maxPriorityResults[i] = {...} end

                return priority
            end
            Logger.logDebug("-", "'"..rule.name.."'", "@"..tostring(priority))
        end
        return maxPriority
    end
    while true do
        local maxPriority = -99999999
        for i = 1, #rules do
            ---@type Rule
            local rule = rules[i]
            maxPriority = processWhenResult(maxPriority, rule, rule:when())
        end
        if maxPriorityRuleCount == 0 then return true end

        local index = math.random(1, maxPriorityRuleCount)
        local rule = maxPriorityRules[index]
        local i = index * 6
        local result1 = maxPriorityResults[i - 5]
        local result2 = maxPriorityResults[i - 4]
        local result3 = maxPriorityResults[i - 3]
        local result4 = maxPriorityResults[i - 2]
        local result5 = maxPriorityResults[i - 1]
        local result6ToN = maxPriorityResults[i]
        Ex.clearArray(maxPriorityRules)
        Ex.clearArray(maxPriorityResults)
        maxPriorityRuleCount = 0

        Logger.log("#", "'"..rule.name.."'", "@"..tostring(maxPriority))

        if result6ToN
        then rule:action(result1, result2, result3, result4, result5, unpack(result6ToN))
        else rule:action(result1, result2, result3, result4, result5)
        end
    end
end

---@param arguments string[]
---@param options MiningOptions
local function parseMiningOptions(options, arguments)
    while 0 < #arguments do
        if
            ArgParser.parseNamedOption(arguments, "down", "d", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "forward", "f", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "right", "r", options, tonumber)
        then
        else
            return error("unrecognized argument: "..arguments[1])
        end
    end
    return true
end

local function miningCommand(...)
    Logger.log("# mining")
    local options = getDefaultMiningOptions()
    parseMiningOptions(options, {...})
    Logger.log("options: ")
    Logger.log("- down", options.down)
    Logger.log("- forward", options.forward)
    Logger.log("- right", options.right)
    Logger.log("")

    local x, y, z = Memoried.currentPosition()
    local box = Box3.newFromPoint(x, y, z)
    Box3.expandByPoint(box, x + options.right, y - options.down, z + options.right)

    Memoried.addRequest({
        name = "mining",
        options = options,
        range = box
    })
    evaluateRules()
end

local commands = {
    mining = miningCommand
}

local function processArguments(x, ...) commands[x](...) end
processArguments(...)
