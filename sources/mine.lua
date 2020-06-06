
---@version: 0.4.7
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Logger = require "logger"
local Rules = require "rules"
local M = require "memoried_extensions"
local findItemInNearDrop = M.findItemInNearDrop
local findNearMovablePath = M.findNearMovablePath
local goToGoal = M.goToGoal
local suckIf = M.suckIf
local directionToNormal = M.directionToNormal
local getNeedFuelLevel = M.getNeedFuelLevel
local isImportantItem = M.isImportantItem
local globalDirectionToPosition = M.globalDirectionToPosition
local limitedDig = M.limitedDig
local maybeAir = M.maybeAir

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
local Unlimited = true

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

---@return number|nil direction
---@return any reason
local function mineTo(maxRetryCount, x, y, z, disableDig, disableAttack)
    local retryCount = 0
    local lastReason = nil
    while retryCount <= maxRetryCount do
        local complete, path, direction = findNearMovablePath(x, y, z, true)
        if path then
            local ok, reason = goToGoal(maxRetryCount, path, disableDig, disableAttack)
            if complete then
                if ok then return direction end
                lastReason = reason
            else
                if not ok then lastReason = reason end
            end
            retryCount = retryCount + 1
        else
            local ok, reason = M.mineTo(maxRetryCount, x, y, z, disableDig, disableAttack)
            if ok then return direction end

            lastReason = reason
            retryCount = retryCount + 1
        end
    end
    return nil, "number of retries exceeded: "..tostring(lastReason)
end

-- - ユーザーにブロックで範囲を指定してもらう ( (x, z) 平面 )
-- - もし周りにチェストが無ければエラー表示して終わり
-- - もし最終位置でなければ繰り返す
--   - y- 方向に回転直下掘り、下にマグマがあったらストップ つぎの (x, z) 位置に移動
--   - y+ 方向に回転直上掘り、周りにブロックがなくなったらストップ つぎの (x, z) 位置に移動
-- - チェストに帰る
--
-- 一連の作業で
--   - もしインベントリがあふれそうならチェストに入れる そのあと元の作業に復帰
--   - もし帰るには燃料が足りなさそうならチェストに行って燃料補給 そのあと元の作業に復帰
--   - 他のエラーなら表示して終了

local normals = {
    1,1,
    -1,1,
    1,-1,
    -1,-1,
}
local function measureBlockNormal(baseBlocks)
    local lastReason = nil
    for bi = 1, #baseBlocks do
        local d = baseBlocks[bi].direction
        local block = baseBlocks[bi].block

        -- 始点となるブロックの座標
        --    [b]
        -- [b][T][b]
        --    [b]
        local bx, by, bz = globalDirectionToPosition(d)

        for ni = 1, #normals, 2 do
            -- 始点ブロックの次のブロックの座標から、ブロック線の方向を求める
            -- [n]   [n]
            --    [b]
            -- [n]   [n]

            local normalX, normalZ = normals[ni], normals[ni + 1]
            local nx, ny, nz = bx + normalX, by, bz + normalZ
            local direction, reason = mineTo(20, nx, ny, nz, DisableDig, EnableAttack)
            if direction then
                -- 次のブロックに移動できた

                local ok, nextBlock = Memoried.getOperationAt(direction).inspect()
                if ok and block.name == nextBlock.name then
                    -- 前のブロックと次のブロックが同じ
                    return block, bx, by, bz, normalX, normalZ
                end
            else
                lastReason = reason
            end
        end
    end
    return nil, lastReason
end
local function measureEndBlock(block, bx, by, bz, normalX, normalZ)
    -- 現在の終点座標
    local ex, ey, ez = bx + normalX, by, bz + normalZ
    while true do
        local tx, ty, tz = ex + normalX, ey, ez + normalX
        Logger.logDebug("measureEndBlock", bx, by, bz, "e", ex, ey, ez)
        local direction = mineTo(20, tx, ty, tz, DisableDig, EnableAttack)
        if direction then
            -- 次のブロックに移動できた

            local ok, targetBlock = Memoried.getOperationAt(direction).inspect()
            if not ok or block.name ~= targetBlock.name then
                -- 前のブロックと次のブロックが違うなら終点
                return ex, ey, ez
            end
            ex, ey, ez = tx, ty, tz
        else
            -- 移動できなかった
            return ex, ey, ez
        end
    end
end
local function measureBlockLine()
    local blocks = {}
    for d = 1, 4 do
        local ok, info = Memoried.getOperationAt(d).inspect()
        if ok then blocks[#blocks+1] = { direction = d, block = info } end
    end
    if #blocks == 0 then return nil, "start block not found" end

    local block, bx, by, bz, normalX, normalZ = measureBlockNormal(blocks)
    if not block then return nil, "next block not found: "..tostring(bx) end

    local ex, ey, ez = measureEndBlock(block, bx, by, bz, normalX, normalZ)
    if not ex then return nil, "end block not found: "..tostring(ey) end

    return bx, by, bz, ex, ey, ez
end
local function removeMiningRequest(...)
    Memoried.removeRequest "mining"
    mainLogger.logError(...)
    mainLogger.logError("mining request removed")
end
Rules.add {
    name = "mine: read range",
    when = function()
        local request = Memoried.getRequest "mining"
        if not request then return end

        local step = request.step or ""
        if step ~= "" then return end

        return defaultRequestPriority
    end,
    action = function()
        local sx, sy, sz, ex, ey, ez = measureBlockLine()
        if not sx then return removeMiningRequest("block line not found,", sy) end

        local request = Memoried.getRequest "mining"
        local range = Box3.newFromPoint(sz, sy, sz)
        Box3.expandByPoint(range, ex, ey, ez)
        Box3.expandByPoint(range, sx, sy + (request.options.up or 1000), sz)
        Box3.expandByPoint(range, sx, sy - (request.options.down or 1000), sz)
        request.range = range
        request.step = "find-chest"
    end
}
local function findChestNoMove()
    local cx, cy, cz = findChestInMemory()
    if cx then return cx, cy, cz end

    for d = 1, 6 do
        local ok, block = Memoried.getOperationAt(d).inspect()
        if ok and block.name == Chest then return globalDirectionToPosition(d) end
    end
end
Rules.add {
    name = "mine: find chest",
    when = function()
        local request = Memoried.getRequest "mining"
        if not request or request.step ~= "find-chest" then return false end
        return defaultRequestPriority
    end,
    action = function()
        local cx, cy, cz = findChestNoMove()
        if not cx then return removeMiningRequest("chest not found") end

        local request = Memoried.getRequest "mining"
        local range = request.range

        request.chestX = cx
        request.chestY = cy
        request.chestZ = cz

        -- 採掘戦闘位置
        -- 採掘先頭位置は必ず採掘範囲内を指すとする
        -- 初期高さはチェストの高さとする
        request.mineX = range.minX
        request.mineY = request.chestY
        request.mineZ = range.minZ

        request.normalX = 1
        request.normalY = -1

        request.step = "mine-core"
    end
}
local function detectAnyAround()
    for d = 1, 4 do
        -- 周りを確認
        if Memoried.getOperationAt(d).detect() then
            return true
        end
    end
    return false
end
Rules.add {
    name = "mine: core",
    when = function()
        -- - もし最終位置でなければ
        --   - y- 方向に回転直下掘り、下にマグマがあったらストップ つぎの (x, z) 位置に移動
        --   - y+ 方向に回転直上掘り、周りにブロックがなくなったらストップ つぎの (x, z) 位置に移動
        -- - チェストに帰る
        local request = Memoried.getRequest "mining"
        if not request or request.step ~= "mine-core" then return false end
        return defaultRequestPriority
    end,
    action = function(self)
        local request = Memoried.getRequest "mining"

        local cx, cy, cz = Memoried.currentPosition()
        if request.mineX ~= cx or request.mineY ~= cy or request.mineZ ~= cz then return false end

        --[[
        [ ][1][ ]
        [1][T][1]
        [ ][1][ ]

        [ ][ ][ ][ ][ ][ ]
        [ ][ ][ ][ ][ ][ ]
        [ ][6][ ][5][ ][4]
        [6][T][5][T][4][T]
        [1][6][2][5][3][4]
        [T][1][T][2][T][3]
        ]]

        -- 周りを掘る
        for d = 1, 4 do
            local mx, my, mz = globalDirectionToPosition(d)
            if Box3.vsPoint(request.range, mx, my, mz) then
                local location = Memoried.getLocation(mx, my, mz)
                if not maybeAir(location) then
                    local ok, reason = limitedDig(d)
                    if not ok then Logger.logDebug(self.name, reason) end
                end
            end
        end

        -- 上下移動
        if request.normalY == -1 then
            -- 下に掘っているとき
            local ok, info = Memoried.getOperationAt(Down).inspect()
            if ok and
                (
                    info.name == "minecraft:bedrock" or
                    info.name == "minecraft:lava" or
                    info.name == "minecraft:flowing_lava"
                )
            then
                -- 掘らないブロックなら反転
                request.normalY = -1 * request.normalY
            else
                -- 掘る
                local ok, reason = M.mineTo(1, cx, cy + request.normalY, cz, EnableDig, EnableAttack, Unlimited)
                if not ok then return removeMiningRequest(self.name, reason) end

                request.mineY = request.mineY + request.normalY
            end
        else
            -- request.normalY == 1
            -- 上に掘っているとき

            -- 上がぶつかったなら掘れる
            -- 上がぶつからなかったときも、チェストの高さまでは周りを確認しないで上に移動
            if Memoried.getOperationAt(Up).detect() or request.mineY <= request.chestY or detectAnyAround() then
                local ok, reason = M.mineTo(1, cx, cy + request.normalY, cz, EnableDig, EnableAttack, Unlimited)
                if not ok then return removeMiningRequest(self.name, reason) end
                request.mineY = request.mineY + request.normalY
            else
                -- チェストの高さを超えたのになにもぶつからなかった
                -- 次の直下掘りに移動
                request.normalY = -1 * request.normalY

                -- x方向に2移動
                request.mineX = request.mineX + request.normalX * 2

                if request.mineX < request.range.minX or request.range.maxX < request.mineX then

                    -- x座標が範囲外に行ったので次のz座標に移動
                    request.mineZ = request.mineZ + 2

                    if request.range.maxZ < request.mineZ then
                        -- z座標が範囲外に行ったら終わり
                        request.step = "goto-chest"
                        return
                    end

                    -- x方向の移動方向は反転
                    request.normalX = -1 * request.normalX

                    -- x座標を範囲内へ移動
                    request.mineX = request.mineX + request.normalX
                    if request.mineX < request.range.minX or request.range.maxX < request.mineX then
                        request.mineX = request.mineX + request.normalX * 2
                    end
                end

                -- 目標へ移動
                local ok, reason = M.mineTo(20, request.mineX, request.mineY, request.mineZ, EnableDig, EnableAttack)
                if not ok then return removeMiningRequest(self.name, reason) end
            end
        end

    end,
}
Rules.add {
    name = "mine: move to mine top",
    when = function()
        local request = Memoried.getRequest "mining"
        if not request or request.step ~= "mine-core" then return false end

        local cx, cy, cz = Memoried.currentPosition()
        if request.mineX == cx and request.mineY == cy and request.mineZ == cz then return false end

        return defaultRequestPriority
    end,
    action = function()
        local request = Memoried.getRequest "mining"
        local range = request.range
        local mx, my, mz =
            request.mineX or range.minX,
            request.mineY or request.chestY,
            request.mineZ or range.minZ

        -- 採掘先頭位置にいないなら移動
        local direction, reason = mineTo(20, mx, my, mz, EnableDig, EnableAttack)
        if not direction then return removeMiningRequest("mineTo failed:", reason) end

        local ok, reason = Memoried.getOperation(direction).move()
        if not ok then return removeMiningRequest("move[1] failed:", reason) end

    end
}
Rules.add {
    name = "mine: get and equip pickaxe",
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
    name = "mine: drop to chest",
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
        local ratio = dropClockRatio * 0.5 + getUsingRatio()
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
    return {}
end

---@param arguments string[]
---@param options MiningOptions
local function parseMiningOptions(options, arguments)
    while 0 < #arguments do
        if
            ArgParser.parseNamedOption(arguments, "up", "u", options, tonumber) or
            ArgParser.parseNamedOption(arguments, "down", "d", options, tonumber)
        then
        else
            return error("unrecognized argument: "..tostring(arguments[1]))
        end
    end
    return true
end

local function miningCommand(arguments)
    mainLogger.log("# mining")
    local options = getDefaultMiningOptions()
    parseMiningOptions(options, arguments)
    mainLogger.log("options: ")
    if options.up then mainLogger.log("- up:", options.up) end
    if options.down then mainLogger.log("- down:", options.down) end

    Memoried.addRequest({
        name = "mining",
        options = options,
    })
end

return {
    mainLogger = mainLogger,
    miningCommand = miningCommand,
}

