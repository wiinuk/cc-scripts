
---@version: 0.2.6
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Ex = require "extensions"
local Json = require "json"


local Forward = Memoried.Forward
local Left = Memoried.Left
local Back = Memoried.Back
local Right = Memoried.Right
local Down = Memoried.Down
local Up = Memoried.Up

---@return integer|nil slotNumber
local function findEmptySlot()
    for i = 16, 1, -1 do
        if turtle.getItemCount(i) == 0 then return i end
    end
    return nil
end

---@param globalAngleY number radian
---@return DirectionOperations
local function globalAngleYToDirectionOperation(globalAngleY)
    local localAngleY = Memoried.toLocalAngleY(globalAngleY)
    local direction = math.modf((localAngleY / (math.pi * 0.5)) + 1)
    return Memoried.getOperation(direction)
end

---@param getOperation fun(x: any): DirectionOperations
---@param getOperationArgument any
---@param disableDig boolean|nil
---@param disableAttack boolean|nil
local function mineMove1(getOperation, getOperationArgument, disableDig, disableAttack)

    if getOperation(getOperationArgument).move() then return true end
    -- 行けなかった

    -- ブロックがあるなら掘る
    if not disableDig and getOperation(getOperationArgument).detect() then

        -- 掘る
        getOperation(getOperationArgument).dig()

        -- 拾う
        getOperation(getOperationArgument).suck()
    end

    -- 掘ったら行けた?
    if getOperation(getOperationArgument).move() then return true end

    -- エンティティがいる?
    if not getOperation(getOperationArgument).detect() then
        -- 待機
        os.sleep(1)
        if getOperation(getOperationArgument).move() then return true end
    end

    if not disableAttack then
        -- エンティティがいる?
        while not getOperation(getOperationArgument).detect() do
            if getOperation(getOperationArgument).move() then return true end
            -- 攻撃
            getOperation(getOperationArgument).attack()
        end
    end

    -- 移動
    local ok, reason = getOperation(getOperationArgument).move()
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
        if targetX < currentX then ok, reason = mineMove1(globalAngleYToDirectionOperation, math.pi * 0.5, disableDig, disableAttack)
        elseif currentX < targetX then ok, reason = mineMove1(globalAngleYToDirectionOperation, math.pi * 1.5, disableDig, disableAttack)
        elseif targetZ < currentZ then ok, reason = mineMove1(globalAngleYToDirectionOperation, math.pi, disableDig, disableAttack)
        elseif currentZ < targetZ then ok, reason = mineMove1(globalAngleYToDirectionOperation, 0, disableDig, disableAttack)

        elseif currentY < targetY then ok, reason = mineMove1(Memoried.getOperation, Up, disableDig, disableAttack)
        elseif targetY < currentY then ok, reason = mineMove1(Memoried.getOperation, Down, disableDig, disableAttack)
        end
        if not ok then
            lastReason = reason
            retryCount = retryCount + 1
        end
    end
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
        down = 10,
        forward = 5,
        right = 5,
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

---@return table|nil itemDetail
---@return string reason
local function inspectItem(suck, drop)
    local emptySlot = findEmptySlot()
    if not emptySlot then return nil, "empty slot not found" end
    local oldSlot = turtle.getSelectedSlot()
    turtle.select(emptySlot)
    local item = nil
    if suck(1) then
        item = turtle.getItemDetail(turtle.getSelectedSlot())
        drop(turtle.getItemCount())
    end
    turtle.select(oldSlot)
    return item
end

local function whenSuckSimple(priority, suck, drop)
    local item, reason = inspectItem(suck, drop)
    if item then return (priority or 0) + 1
    elseif reason == "empty slot not found" then
        -- TODO:
        return false
    else
        return false
    end
end

---@class Rule
---@field public name string
---@field public when fun(): boolean|number, any
---@field public action fun(a: any): any

---@type Rule[]
local rules = {}
rules[#rules+1] = {
    name = "mining: dig around",
    when = function ()
        local request = Memoried.getRequest "mining"
        if not request then return false end

        local priority = false
        local direction = nil
        for d = 6, 1, -1 do
            local nextPriority, p = whenMine(priority, request, d)
            if p then direction = d end
            priority = nextPriority
        end
        return priority, direction
    end,
    action = function (direction)
        local ok, reason = Memoried.getOperation(direction).dig()
        if not ok then Ex.printError(reason) end
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
        if not ok then Ex.printError(reason) end
    end
}
rules[#rules+1] = {
    name = "mining request: suck",
    when = function ()
        if not Memoried.hasRequest("mining") then return false end

        local priority = false
        priority = whenSuckSimple(priority, turtle.suck, turtle.drop)
        priority = whenSuckSimple(priority, turtle.suckDown, turtle.dropDown)
        priority = whenSuckSimple(priority, turtle.suckUp, turtle.dropUp)
        return priority
    end,
    action = function()
        turtle.suck()
        turtle.suckDown()
        turtle.suckUp()
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
        local x, y, z = Memoried.currentPosition()
        x = Memoried.memory.lastCollectMapX or x
        y = Memoried.memory.lastCollectMapY or y
        z = Memoried.memory.lastCollectMapZ or z
        for dx = -1, 1 do
            for dy = -1, 1 do
                for dz = -1, 1 do
                    local x, y, z = x + dx, y + dy, z + dz
                    if Box3.vsPoint(range, x, y, z) then
                        local location = Memoried.getLocation(x, y, z)
                        if not location or location.detect == nil or location.inspect == nil then
                            Memoried.memory.lastCollectMapY = x
                            Memoried.memory.lastCollectMapY = y
                            Memoried.memory.lastCollectMapY = z
                            return collectMapInfoPriority
                        end
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
            local location = Memoried.getLocation(x, y, z)
            if not location or location.detect == nil or location.inspect == nil then
                Memoried.memory.lastCollectMapY = x
                Memoried.memory.lastCollectMapY = y
                Memoried.memory.lastCollectMapY = z
                return collectMapInfoPriority
            end
        end
        return false

    end,
    action = function()
        local ok, reason = mineTo(
            20,
            Memoried.memory.lastCollectMapY,
            Memoried.memory.lastCollectMapY,
            Memoried.memory.lastCollectMapY,
            true,
            false
        )
        if not ok then Ex.printError(reason) end
    end
}
rules[#rules+1] = {
    name = "collect around map",
    when = function()
        local cx, cy, cz = Memoried.currentPosition()
        for d = 1, 6 do
            local op = Memoried.getOperation(d)
            local nx, ny, nz = op.currentNormal()
            local x, y, z = cx + nx, cy + ny, cz + nz

            local location = Memoried.getLocation(x, y, z)
            if not location then return collectMapInfoPriority, d end
            if location.detect == nil then return collectMapInfoPriority, d end
            if location.inspect == nil then return collectMapInfoPriority, d end
        end
        return false
    end,
    action = function (d)
        local gd = Memoried.toGlobalDirection(d)
        Memoried.getOperation(Memoried.toLocalDirection(gd)).detect()
        Memoried.getOperation(Memoried.toLocalDirection(gd)).inspect()
    end,
}
rules[#rules+1] = {
    name = "walk",
    when = function ()
        return 100
    end,
    action = function ()
        turtle.forward()
        turtle.forward()
        turtle.forward()
        -- Memoried.move()

        -- local getOperation = Memoried.getOperation
        -- local getOperationArgument = Forward
        -- local disableDig = nil
        -- local disableAttack = nil

        -- print("[0]")
        -- if getOperation(getOperationArgument).move() then return true end
        -- print("[1]", "move failure")
        -- -- 行けなかった

        -- -- ブロックがあるなら掘る
        -- if not disableDig and getOperation(getOperationArgument).detect() then

        --     -- 掘る
        --     getOperation(getOperationArgument).dig()

        --     -- 拾う
        --     getOperation(getOperationArgument).suck()
        -- end

        -- -- 掘ったら行けた?
        -- if getOperation(getOperationArgument).move() then return true end

        -- print("[2]", "move failure")

        -- -- エンティティがいる?
        -- if not getOperation(getOperationArgument).detect() then
        --     print("[3]", "wait entity")
        --     -- 待機
        --     os.sleep(2)
        --     if getOperation(getOperationArgument).move() then return true end
        -- end

        -- if not disableAttack then
        --     -- エンティティがいる?
        --     while not getOperation(getOperationArgument).detect() do
        --         print("[4]", "attack entity")
        --         if getOperation(getOperationArgument).move() then return true end
        --         -- 攻撃
        --         getOperation(getOperationArgument).attack()
        --     end
        -- end

        -- -- 移動
        -- local ok, reason = getOperation(getOperationArgument).move()
        -- if ok then return true end
        -- print("[5]", "move failure")

        -- -- 失敗
        -- return false, reason
    end
}

-- インベントリが満タンならチェストまで移動して入れる
-- ホームに帰れなくなりそうなら帰るか燃料を探す ( 高優先度 )

local function evaluateRules()
    local maxPriorityRuleCount = 0
    local maxPriorityRules = {}
    local maxPriorityResults = {}

    while true do
        local maxPriority = -99999999
        for i = 1, #rules do
            local rule = rules[i]
            local priority, result = rule.when()
            if priority then
                if maxPriority <= priority then
                    if maxPriority < priority then
                        Ex.clearTable(maxPriorityRules)
                        Ex.clearTable(maxPriorityResults)
                        maxPriorityRuleCount = 0
                    end
                    maxPriorityRuleCount = maxPriorityRuleCount+1
                    maxPriorityRules[maxPriorityRuleCount] = rule
                    maxPriorityResults[maxPriorityRuleCount] = result
                    maxPriority = priority
                end
                print("  -", "'"..rule.name.."'", "@"..tostring(priority))
            end
        end
        if maxPriorityRuleCount == 0 then return true end

        local index = math.random(1, maxPriorityRuleCount)
        local rule = maxPriorityRules[index]
        local result = maxPriorityResults[index]
        Ex.clearTable(maxPriorityRules)
        Ex.clearTable(maxPriorityResults)
        maxPriorityRuleCount = 0

        print("#", "'"..rule.name.."'", "@"..tostring(maxPriority))
        rule.action(result)

        if math.random(1, 10) <= 1 then
            local json = Json.stringify(Memoried.memory, {
                space = " ",
                indent = " ",
                maxWidth = 0,
            })
            if json then
                local f = io.open("memory.json", "w+")
                if f then
                    f:write(json)
                    f:close()
                end
            end
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
    print("# mining")
    local options = getDefaultMiningOptions()
    parseMiningOptions(options, {...})
    print("options: ")
    print("- down", options.down)
    print("- forward", options.forward)
    print("- right", options.right)
    print("")

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
