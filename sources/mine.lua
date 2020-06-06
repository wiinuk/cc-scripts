
---@version: 0.4.7
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Logger = require "logger"
local Rules = require "rules"
local pretty = require "pretty"
local M = require "memoried_extensions"
local findItemInNearDrop = M.findItemInNearDrop
local findNearMovablePath = M.findNearMovablePath
local goToGoal = M.goToGoal
local suckIf = M.suckIf
local directionToNormal = M.directionToNormal
local getNeedFuelLevel = M.getNeedFuelLevel
local isImportantItem = M.isImportantItem

local Forward = Memoried.Forward
local Left = Memoried.Left
local Back = Memoried.Back
local Right = Memoried.Right
local Down = Memoried.Down
local Up = Memoried.Up

local DiamondPickaxe = "minecraft:diamond_pickaxe"
local Chest = "minecraft:chest"

local mainLogger = Logger.create("main")

local DisableDig = true
local EnableDig = false
local DisableAttack = true
local EnableAttack = false

---@class MiningOptions
---@field public down integer
---@field public forward integer
---@field public right integer

--- 既定の要求の優先度
local defaultRequestPriority = 0.5
local equipToolPriorityRatio = 1.5
local defaultDropChestPriority = 1

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
                if not isImportantItem(name) then
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
    if isImportantItem(name) then return true end
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

