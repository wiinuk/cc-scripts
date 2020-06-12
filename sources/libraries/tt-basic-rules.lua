package.path = package.path..";../?.lua"

local Memoried = require "memoried"
local Down = Memoried.Down
local Logger = require "logger"
local Json = require "json"
local Mex = require "memoried_extensions"
local Vec3 = require "vec3"


local DisableDig = true
local DisableAttack = true
local StainedGlass = "minecraft:stained_glass"
local branchBlockColor = "black"
local normalEdgeColor = "white"
local homeBlockName = "minecraft:obsidian"

local mainLogger = Logger.create("main-logger")

local function isHomeBlock(info)
    return info and info.name == homeBlockName
end

local function isBranchFloor(info)
    return info and info.name == StainedGlass and info.state and info.state.color == branchBlockColor
end

local function isAnyEdge(info)
    return info and info.name == StainedGlass and info.state and info.state.color ~= branchBlockColor
end

local checkHomeRule = {
    name = "tt: check home",
    when = function()
        if not Memoried.ttHome then return 10 end
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

local function newDefaultPersistentMemory()
    return {
        startNodeAdded = false,
        openNodes = {},
        closeNodes = {},
        colorToPositions = {},
    }
end
local memoryPath = "/settings/tt.json"
local function loadOrCreatePersistentMemory()
    local file = io.open(memoryPath, "r+")
    if not file then
        Logger.logInfo("new creating memory")
        return newDefaultPersistentMemory()
    end

    local contents = file:readAll()
    file:close()

    local ok, result = Json.parse(contents)
    if not ok then return error(result) end

    Logger.logInfo("loading memory from", memoryPath)
    return result
end

local persistentMemory = loadOrCreatePersistentMemory()

local function savePersistentMemory()
    local json, reason = Json.stringify(persistentMemory, { space = " ", indent = "  ", maxWidth = 0 })
    if not json then return Logger.logError("memory stringify error", reason) end

    local file = io.open(memoryPath, "w+")
    file:write(json)
    file:close()

    Logger.logInfo("memory saved to", memoryPath)
end

local function isMovable(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    return location and (location.move == true or location.detect == false)
end

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

local function registerEdgeInfo(info)
    local color = info.state.color
    if color == normalEdgeColor then return end

    local positions = persistentMemory.colorToPositions[color]
    if not positions then
        positions = {}
        persistentMemory.colorToPositions = positions
    end
    local cx, cy, cz = Memoried.currentPosition()
    positions[#positions+1] = { cx, cy, cz }

    mainLogger.logInfo("register", cx, cy, cz, color)
end

local collectMapRule = {
    name = "tt: collect map",
    when = function()
        if not Memoried.ttHome then return end
        if 0 < #persistentMemory.openNodes then return 1 end
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
        local complete, path = Mex.findPath(node.x, node.y, node.z, isMovable)
        if not complete then return Logger.logError(self.name, "path not found") end
        local ok, reason = Mex.goToGoal(5, path, DisableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, "goToGoal", reason) end

        -- 分岐か確認する
        local _, info = Memoried.getOperationAt(Down).inspect()
        if not isBranchFloor(info) then return Logger.logError(self.name, "floor should be the branch block") end

        -- 未探索道を探索済みとマーク
        local closes = persistentMemory.closeNodes
        closes[#closes+1] = node
        mainLogger.logInfo(self.name, "closed", node.x, node.y, node.z, node.direction)

        while true do

            -- 1m 移動
            local ok, reason = Memoried.getOperationAt(node.direction).move()
            if not ok then return Logger.logError(self.name, "move", reason) end

            local _, info = Memoried.getOperationAt(Down).inspect()

            if isBranchFloor(info) then

                -- 移動先が分岐なら未探索道に追加して終了
                local cx, cy, cz = Memoried.currentPosition()
                for d = 1, 4 do
                    if addAsOpen(opens, closes, cx, cy, cz, d) then
                        mainLogger.logInfo(self.name, "open", cx, cy, cz, d)
                    end
                end
                break

            elseif isAnyEdge(info) then

                -- 移動先が直線なら登録して続ける
                registerEdgeInfo(info)

            else
                -- 分岐でも直線でもない = 道でないので終了
                break
            end
        end
        savePersistentMemory()
    end,
}


return {
    mainLogger = mainLogger,
    checkHomeRule = checkHomeRule,
    collectMapRule = collectMapRule,
}