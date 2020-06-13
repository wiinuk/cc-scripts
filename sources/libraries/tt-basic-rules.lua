package.path = package.path..";../?.lua"

local Memoried = require "memoried"
local Down = Memoried.Down
local Up = Memoried.Up
local Forward = Memoried.Forward
local Back = Memoried.Back
local Right = Memoried.Right
local Left = Memoried.Left
local Logger = require "logger"
-- local Json = require "json"
local Mex = require "memoried_extensions"
local Vec3 = require "vec3"
local Tree = require "tree-core"


local DisableDig = true
local EnableDig = false
local DisableAttack = true
local EnableAttack = false

local Grass = "minecraft:grass"
local Log = "minecraft:log"
local Leaves = "minecraft:leaves"
local Sapling = "minecraft:sapling"
local Dirt = "minecraft:dirt"
local StainedGlass = "minecraft:stained_glass"
local branchBlockColor = "black"
local normalEdgeColor = "white"
local treeFarmColor = "green"
local homeBlockName = "minecraft:obsidian"

local mainLogger = Logger.create("main-logger")

local collectMapPriority = 1
local treeFarmingPriority = 0.5

local function isHomeBlock(info)
    return info and info.name == homeBlockName
end

local function isBranchFloor(info)
    return isHomeBlock(info) or (info and info.name == StainedGlass and info.state and info.state.color == branchBlockColor)
end

local function isAnyEdge(info)
    return info and info.name == StainedGlass and info.state and info.state.color ~= branchBlockColor
end

local function ready()
    return Memoried.ttHome
end

local function goTo(maxRetryCount, x, y, z, isMovable, disableDig, disableAttack)
    local complete, path = Mex.findPath(x, y, z, isMovable)
    if not complete then return false, "path not found" end
    local ok, reason = Mex.goToGoal(maxRetryCount, path, disableDig, disableAttack)
    if not ok then return false, reason end
    return true
end

local checkHomeRule = {
    name = "tt: check home",
    when = function()
        if not ready() then return 10 end
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
        colorToLocations = {},
    }
end
-- local memoryPath = "/settings/tt.json"
local function loadOrCreatePersistentMemory()
    return newDefaultPersistentMemory()

    -- if not fs.exists(memoryPath) then
    --     Logger.logInfo("new creating memory")
    --     return newDefaultPersistentMemory()
    -- end

    -- local file = io.open(memoryPath, "r+")
    -- local contents = file:read("*a")
    -- file:close()

    -- local ok, result = Json.parse(contents)
    -- if not ok then return error(result) end

    -- Logger.logInfo("loading memory from", memoryPath)
    -- return result
end

local persistentMemory = loadOrCreatePersistentMemory()

local function savePersistentMemory()
    -- local json, reason = Json.stringify(persistentMemory, { space = " ", indent = "  ", maxWidth = 0 })
    -- if not json then return Logger.logError("memory stringify error", reason) end

    -- local file = io.open(memoryPath, "w+")
    -- file:write(json)
    -- file:close()

    -- Logger.logInfo("memory saved to", memoryPath)
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

local function disableDig(direction)
    local ok, info = Memoried.getOperationAt(direction).inspect()
    return not (ok and info.name == Leaves)
end

local collectMapRule = {
    name = "tt: collect map",
    when = function()
        if not ready() then return end
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
    end,
}

---@generic T
---@param array table<integer, T>
---@param toPriority fun(item: T): number|nil
---@return T|nil maxPriorityItem
---@return number|nil maxPriority
local function maxByArray(array, toPriority)
    if not array or #array == 0 then return end

    local maxPriority = -1 / 0
    local maxPriorityItem = nil
    for i = 1, #array do
        local item = array[i]
        local priority = toPriority(item)
        if priority and maxPriority <= priority then
            maxPriorityItem = item
            maxPriority = priority
        end
    end
    return maxPriorityItem, maxPriority
end

local function minCheckClock(treeFarmLocation)
    local check = treeFarmLocation.lastCheckClock or 0
    local modify = treeFarmLocation.lastModifyClock or 0
    return modify + (check - modify) * 2
end

local function treeFarmLocationPriority(treeFarmLocation, clock, cx, cy, cz)
    if clock < minCheckClock(treeFarmLocation) then return end

    local modify = treeFarmLocation.lastModifyClock or 0
    local d = Vec3.manhattanDistance(
        treeFarmLocation.x, treeFarmLocation.y, treeFarmLocation.z,
        cx, cy, cz
    )
    local span = clock - modify
    return -d + span
end

local function getHighestPriorityTreeFarmLocation()
    local locations = persistentMemory.colorToLocations[treeFarmColor]
    local clock = os.clock()
    local cx, cy, cz = Memoried.currentPosition()
    return maxByArray(locations, function (location)
        return treeFarmLocationPriority(location, clock, cx, cy, cz)
    end)
end

local function placeSapling(slot)
    turtle.select(slot)

    -- 右下に移動
    -- [?][?][?]
    -- [?][ ][?]
    --    [^]
    Memoried.getOperation(Down).move()
    Memoried.getOperation(Right).move()
    local _, info = Memoried.getOperation(Left).inspect()
    if info.name ~= Dirt or info.name ~= Grass then
        Memoried.getOperation(Left).move()
        Memoried.turnRight()
    end
    -- [D][D]
    -- [D][D]
    --    [^]

    Memoried.getOperation(Up).dig()
    Memoried.getOperation(Up).move()
    Memoried.getOperation(Up).dig()
    Memoried.getOperation(Up).move()
    Memoried.getOperation(Forward).dig()
    Memoried.getOperation(Forward).move()
    Memoried.getOperation(Down).place()
    -- [D??][D??]
    -- [D??][DS^]
    Memoried.getOperation(Forward).dig()
    Memoried.getOperation(Forward).move()
    Memoried.getOperation(Down).dig()
    Memoried.getOperation(Down).place()
    -- [D??][DS^]
    -- [D??][DS ]
    Memoried.getOperation(Left).dig()
    Memoried.getOperation(Forward).move()
    Memoried.getOperation(Down).dig()
    Memoried.getOperation(Down).place()
    -- [DS<][DS]
    -- [D??][DS]
    Memoried.getOperation(Left).dig()
    Memoried.getOperation(Forward).move()
    Memoried.getOperation(Down).dig()
    Memoried.getOperation(Down).place()
    -- [DS ][DS]
    -- [DSv][DS]

    Memoried.getOperation(Forward).move()
    Memoried.getOperation(Down).move()
    Memoried.getOperation(Down).move()
    -- [DS][DS]
    -- [DS][DS]
    -- [v]
end

local function showNextCheckClock(location)
    local nextSpan = minCheckClock(location) - os.clock()
    if 0 < nextSpan then
        mainLogger.logInfo("next check is", nextSpan, "s later", location.x, location.y, location.z)
    end

end

local treeFarmingRule = {
    name = "tt: tree farming",
    when = function()

        -- 準備ができていない
        if not ready() then return end

        -- 植林場を知らない
        local location = getHighestPriorityTreeFarmLocation()
        if not location then return end

        local cx, cy, cz = Memoried.currentPosition()
        local fuelLevelPriority = 0
        local needLevel = Vec3.manhattanDistance(location.x, location.y, location.z, cx, cy, cz) * 1.5
        local level = turtle.getFuelLevel()
        if level ~= "unlimited" and needLevel ~= 0 then
            -- level = 500, needLevel = 50 => 0.1
            -- level = 100, needLevel = 50 => 0.5
            -- level = 50, needLevel = 50 => 1
            -- level = 10, needLevel = 50 => 5
            fuelLevelPriority = 1 / (level / needLevel)
        end

        return treeFarmingPriority + fuelLevelPriority, location
    end,
    action = function(self, location)
        local fx, fy, fz, direction = location.x, location.y, location.z, location.direction

        local ok, reason = goTo(10, fx, fy, fz, isMovable, disableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, reason) end

        Memoried.getOperationAt(Up).dig()
        Memoried.getOperationAt(Up).move()

        location.lastCheckClock = os.clock()
        local ok, info = Memoried.getOperationAt(direction).inspect()

        if info.name == Log then
            Tree.digTree()
            location.lastModifyClock = os.clock()

        elseif info.name == Sapling then
            -- TODO: 骨粉
            showNextCheckClock(location)

        elseif not ok then
            -- 何も植えていなかったので苗木を植える
            local slot = Tree.findSimpleHugeSaplingSlot()
            if slot then
                placeSapling(slot)
                location.lastModifyClock = os.clock()
            else
                showNextCheckClock(location)
            end
        end
    end
}

return {
    mainLogger = mainLogger,
    checkHomeRule = checkHomeRule,
    collectMapRule = collectMapRule,
    treeFarmingRule = treeFarmingRule,
}
