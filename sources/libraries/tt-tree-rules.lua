package.path = package.path..";../?.lua"

local TT = require "tt-core"
local mainLogger = TT.mainLogger
local goTo = TT.goTo
local isHomeChecked = TT.isHomeChecked
local persistentMemory = TT.persistentMemory
local isMovable = TT.isMovable
local disableDig = TT.disableDig
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
local Box3 = require "box3"
local Ex = require "extensions"
local maxByArray = Ex.maxByArray
local Names = require "minecraft-names"


local DisableAttack = true
local EnableAttack = false

local Grass = Names.Grass
local Log = Names.Log
local Sapling = Names.Sapling
local Dirt = Names.Dirt
local treeFarmColor = "green"

local treeFarmingPriority = 0.5
local suckSaplingPriority = 0.5

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

local function getHighestPriorityTreeFarmLocationBy(getPriority)
    local locations = persistentMemory.colorToLocations[treeFarmColor]
    local clock = os.clock()
    local cx, cy, cz = Memoried.currentPosition()
    return maxByArray(locations, function (location)
        return getPriority(location, clock, cx, cy, cz)
    end)
end

local function isTreeFarm(info)
    return info.name == Dirt or info.name == Grass
end

local function moveToTreeFarmRightBack(direction)
    local ok, info = Memoried.getOperationAt(direction).inspect()
    if not ok or not isTreeFarm(info) then return false, "location is not tree farm" end

    Memoried.getOperation(Right).dig()
    Memoried.getOperation(Forward).move()

    local ok, info = Memoried.getOperationAt(direction).inspect()
    if not ok or not isTreeFarm(info) then
        Memoried.getOperation(Left).move()
        Memoried.turnRight()
    end
end

local function placeSapling()

    -- 右下に移動
    -- [?][?][?]
    -- [?][ ][?]
    --    [^]
    Memoried.getOperation(Down).move()
    Memoried.getOperation(Right).move()
    local ok, info = Memoried.getOperation(Left).inspect()
    if not ok or not isTreeFarm(info) then
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
        if not isHomeChecked() then return end

        -- 植林場を知らない
        local location = getHighestPriorityTreeFarmLocationBy(treeFarmLocationPriority)
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

        if ok and info.name == Log then
            local ok, reason = Tree.digTree()
            if not ok then error(reason) end

            local now = os.clock()
            location.lastModifyClock = now
            location.lastDigSuccessClock = now
            Memoried.getOperationAt(Down).move()
            mainLogger.logInfo(self.name, "finished")

        elseif ok and info.name == Sapling then
            -- TODO: 骨粉
            showNextCheckClock(location)
            Memoried.getOperationAt(Down).move()

        elseif not ok then
            -- 何も植えていなかったので苗木を植える
            local slot = Tree.findSimpleHugeSaplingSlot()
            if slot then
                turtle.select(slot)
                placeSapling()
                location.lastModifyClock = os.clock()
            else
                showNextCheckClock(location)
            end
        end
    end
}

local itemLifeSpan = 60 * 5
local function treeFarmLocationPriorityForSuckSapling(treeFarmLocation, clock, cx, cy, cz)

    -- 原木採取したことがなかった
    if not treeFarmLocation.lastDigSuccessClock then return end

    local suck = treeFarmLocation.lastSuckTryClock or 0
    local dig = treeFarmLocation.lastDigSuccessClock or 0
    suck = math.max(dig, suck)

    -- 燃料を節約するため、前回の苗木採取からある程度時間を空ける
    local nextCheckClock = dig + (suck - dig) * 2
    if clock < nextCheckClock then
        mainLogger.log("last suck try:", dig - clock, "s later")
        mainLogger.log("last dig success:", dig - clock, "s later")
        mainLogger.log("next check:", nextCheckClock - clock, "s later", cx, cy, cz)
        return
    end

    -- 原木採取してからある程度経過すると苗木は消えてしまう
    local span = clock - dig
    if 60 --[[ 葉ブロックの推定消滅期間 ]] + itemLifeSpan < span * 2 then return end

    -- 同じような時間条件の場合近いほうを優先する
    local d = Vec3.manhattanDistance(
        treeFarmLocation.x, treeFarmLocation.y, treeFarmLocation.z,
        cx, cy, cz
    )
    return span - d
end

local function findNearestNoSuckLocation(map, cx, cy, cz)
    return maxByArray(map, function(p)
        if p.sucked then return end

        local d = 0

        -- 自分の位置の測定は距離2
        if p.x == cx and p.y == cy and p.z == cz
        then d = 2
        else d = Vec3.manhattanDistance(cx, cy, cz, p.x, p.y, p.z)
        end

        return -d
    end)
end

local function initializeSaplingMap(map, height, width, offsetForward, offsetRight)
    local bx, by, bz = Memoried.currentPosition()
    local range = Box3.newFromPoint(bx, by, bz)

    local ex, ey, ez = Vec3.multiply(
        offsetForward,
        Memoried.getOperation(Back).currentNormal()
    )
    Box3.expandByPoint(range, bx + ex, by + ey, bz + ez)

    local ex, ey, ez = Vec3.multiply(
        height - 1 - offsetForward,
        Memoried.getOperation(Forward).currentNormal()
    )
    Box3.expandByPoint(range, bx + ex, by + ey, bz + ez)

    local ex, ey, ez = Vec3.multiply(
        offsetRight,
        Memoried.getOperation(Left).currentNormal()
    )
    Box3.expandByPoint(range, bx + ex, by + ey, bz + ez)

    local ex, ey, ez = Vec3.multiply(
        width - 1 - offsetRight,
        Memoried.getOperation(Right).currentNormal()
    )
    Box3.expandByPoint(range, bx + ex, by + ey, bz + ez)

    Logger.logDebug("map range",
        range.minX, range.minY, range.minZ, "..",
        range.maxX, range.maxY, range.maxZ
    )

    for x = range.minX, range.maxX do
        for y = range.minY, range.maxY do
            for z = range.minZ, range.maxZ do
                map[#map+1] = { x = x, y = y, z = z, sucked = false }
            end
        end
    end
end

local function findNeighborPositionAndDirection(p)
    local pathAndDirections = nil
    for d = 1, 4 do
        local nx, ny, nz = Mex.directionToNormal(d)
        local mx, my, mz = p.x - nx, p.y - ny, p.z - nz
        local complete, path = Mex.findPath(mx, my, mz, isMovable)
        if complete then
            pathAndDirections = pathAndDirections or {}
            pathAndDirections[#pathAndDirections+1] = { path, d }
        end
    end
    local pd = maxByArray(pathAndDirections, function(x) return -#x[1] end)
    if not pd then return end

    return pd[1], pd[2]
end

local suckSaplingRule = {
    name = "tt: suck sapling",
    when = function()
        if not isHomeChecked() then return end

        -- 原木採取とは違うタイマーを使って植林場の優先度を測定する
        local location = getHighestPriorityTreeFarmLocationBy(treeFarmLocationPriorityForSuckSapling)
        if not location then return end

        local suckItemPriority = 0
        local lifeSpan = os.clock() - (location.lastDigSuccessClock or 0)
        if lifeSpan < itemLifeSpan then
            suckItemPriority = (lifeSpan / itemLifeSpan) * 3
        end

        return suckSaplingPriority + suckItemPriority, location
    end,
    action = function(self, location)
        local fx, fy, fz, direction = location.x, location.y, location.z, location.direction

        local ok, reason = goTo(10, fx, fy, fz, isMovable, disableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, reason) end

        -- 基準位置に移動 ( 右後ろの土ブロックの後ろ )
        moveToTreeFarmRightBack(direction)

        -- マップを初期化
        --[[
            0 ..                  7
            [ ][ ][ ][ ][ ][ ][ ][ ] 7
            [ ][ ][ ][ ][ ][ ][ ][ ]
            [ ][ ][ ][ ][ ][ ][ ][ ]
            [ ][ ][ ][D][D][ ][ ][ ]
            [ ][ ][ ][D][D][ ][ ][ ]
            [ ][ ][ ][ ][^][ ][ ][ ]
            [ ][ ][ ][ ][ ][ ][ ][ ]
            [ ][ ][ ][ ][ ][ ][ ][ ] 0
        ]]
        local map = {}
        initializeSaplingMap(map, 10, 10, 3, 5)

        while true do

            -- 探索していない中で最も近い位置を取得
            local l = findNearestNoSuckLocation(map, Memoried.currentPosition())

            if not l then
                -- 全ての位置を探索し終えた
                location.lastSuckTryClock = os.clock()
                mainLogger.log(self.name, "finished")
                return
            end

            -- 探索位置に近接しているブロックへのパスを検索
            local path, direction = findNeighborPositionAndDirection(l)
            if not path then

                -- パスが見つからなかったらあきらめて取ったことにする
                mainLogger.logWarning(self.name, "path not found", l.x, l.y, l.z)
                l.sucked = true
            else
                local ok, reason = Mex.goToGoal(4, path, disableDig, EnableAttack)
                if not ok then

                    -- 移動できなかったのであきらめて取ったことにする
                    mainLogger.logWarning(self.name, reason, l.x, l.y, l.z)
                    l.sucked = true
                else
                    while
                        -- ぶつからない = チェストではない
                        not Memoried.getOperationAt(direction).detect()
                        -- 複数のアイテムを回収
                        and Memoried.getOperationAt(direction).suck()
                        do
                        end

                    -- 移動できるようにするため情報を取得
                    Memoried.getOperationAt(direction).inspect()
                    Memoried.getOperationAt(direction).detect()
                    l.sucked = true
                end
            end
        end
    end
}

return {
    mainLogger = mainLogger,
    treeFarmingRule = treeFarmingRule,
    suckSaplingRule = suckSaplingRule,
}
