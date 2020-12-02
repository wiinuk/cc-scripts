package.path = package.path..";../?.lua"

local TT = require "tt-core"
local mainLogger = TT.mainLogger
local goTo = TT.goTo
local isHomeChecked = TT.isHomeChecked
local persistentMemory = TT.persistentMemory
local savePersistentMemory = TT.savePersistentMemory
local isMovable = TT.isMovable
local disableDig = TT.disableDig
local Memoried = require "memoried"
local Down = Memoried.Down
local Logger = require "logger"
-- local Json = require "json"
local Mex = require "memoried_extensions"
local Vec3 = require "vec3"


local DisableDig = true
local DisableAttack = true

local Leaves = "minecraft:leaves"
local StainedGlass = "minecraft:stained_glass"
local branchBlockColor = "black"
local normalEdgeColor = "white"
local homeBlockName = "minecraft:obsidian"

local collectMapPriority = 1

local function isHomeBlock(info)
    return info and info.name == homeBlockName
end

local function isBranchFloor(info)
    return isHomeBlock(info) or (info and info.name == StainedGlass and info.state and info.state.color == branchBlockColor)
end

local function isAnyEdge(info)
    return info and info.name == StainedGlass and info.state and info.state.color ~= branchBlockColor
end

local checkHomeRule = {
    name = "tt: check home",
    when = function()
        if not isHomeChecked() then return 10 end
    end,
    action = function()
        local cx, cy, cz = Memoried.currentPosition()
        if cx ~= 0 or cy ~= 0 or cz ~= 0 then return error("The floor should be the 0 0 0") end

        -- 床がホームブロックか確認する
        local _, info = Memoried.getOperationAt(Down).inspect()
        if not isHomeBlock(info) then
            return error("The floor should be the home block", homeBlockName)
        end

        Memoried.ttHome = {}
    end
}

local function popNearestNode(openSet)
    if #openSet <= 0 then return end

    local cx, cy, cz = Memoried.currentPosition()

    local nearestIndex = 1
    local nearestNode = openSet[nearestIndex]
    local nearestDistance = Vec3.manhattanDistance(cx, cy, cz, nearestNode.x, nearestNode.y, nearestNode.z)
    for i = 2, #openSet do
        local node = openSet[i]
        local distance = Vec3.manhattanDistance(cx, cy, cz, node.x, node.y, node.z)
        if distance <= nearestDistance then
            nearestIndex = i
            nearestNode = node
            nearestDistance = distance
        end
    end
    table.remove(openSet, nearestIndex)
    return nearestNode
end

local function addAsOpen(openSet, closeSet, x, y, z, direction)
    for i = 1, #closeSet do
        local node = closeSet[i]
        if node.x == x and node.y == y and node.z == z and node.direction == direction then
            return false
        end
    end
    for i = 1, #openSet do
        local node = openSet[i]
        if node.x == x and node.y == y and node.z == z and node.direction == direction then
            return false
        end
    end

    openSet[#openSet+1] = { x = x, y = y, z = z, direction = direction }
    return true
end

local function registerEdgeInfo(info, direction)
    local color = info.state.color
    if color == normalEdgeColor then return end

    local locations = persistentMemory.colorToLocations[color]
    if not locations then
        locations = {}
        persistentMemory.colorToLocations[color] = locations
    end
    local cx, cy, cz = Memoried.currentPosition()
    locations[#locations+1] = { x = cx, y = cy, z = cz, direction = direction }

    mainLogger.logInfo("register", cx, cy, cz, color)
end

local function mineToDirection(direction, disableDig, disableAttack)
    local tx, ty, tz = Mex.globalDirectionToPosition(direction)
    return Mex.mineTo(7, tx, ty, tz, disableDig, disableAttack)
end

local collectMapRule = {
    name = "tt: collect map",
    when = function()
        if not isHomeChecked() then return end
        if
            not persistentMemory.startNodeAdded or
            0 < #persistentMemory.openNodes
        then
            return collectMapPriority
        end
    end,
    action = function(self)
        local opens = persistentMemory.openNodes
        if not persistentMemory.startNodeAdded then

            -- 未探索道の初期化
            for d = 1, 4 do
                opens[#opens+1] = { x = 0, y = 0, z = 0, direction = d }
            end
            persistentMemory.startNodeAdded = true
        end

        -- 最も近い未探索道に向かう
        local node = popNearestNode(persistentMemory.openNodes)
        local ok, reason = goTo(5, node.x, node.y, node.z, isMovable, DisableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, reason) end

        -- 分岐か確認する
        local _, info = Memoried.getOperationAt(Down).inspect()
        if not isBranchFloor(info) then return Logger.logError(self.name, "floor should be the branch block") end

        -- 未探索道を探索済みとマーク
        local closes = persistentMemory.closeNodes
        closes[#closes+1] = node
        Logger.logDebug(self.name, "closed", node.x, node.y, node.z, node.direction)

        while true do

            -- 移動できなければ道ではないので終了
            if Memoried.getOperationAt(node.direction).detect() then break end

            -- 1m 移動
            -- 葉ブロックの掘り有効
            local ok, reason = mineToDirection(node.direction, disableDig, DisableAttack)
            if not ok then return Logger.logError(self.name, "move", reason) end

            local _, info = Memoried.getOperationAt(Down).inspect()
            if isBranchFloor(info) then

                -- 移動先が分岐なら未探索道に追加して終了
                local cx, cy, cz = Memoried.currentPosition()
                for d = 1, 4 do
                    if addAsOpen(opens, closes, cx, cy, cz, d) then
                        Logger.logDebug(self.name, "open", cx, cy, cz, d)
                    end
                end
                break

            elseif isAnyEdge(info) then

                -- 移動先が直線なら登録して続ける
                registerEdgeInfo(info, node.direction)

            else
                -- 分岐でも直線でもない = 道でないので終了
                break
            end
        end
        savePersistentMemory()
        Logger.logInfo(self.name, "finished")
    end,
}

return {
    checkHomeRule = checkHomeRule,
    collectMapRule = collectMapRule,
}
