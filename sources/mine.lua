
---@version: 0.1.8
local Memoried = require "memoried"
local ArgParser = require "arg-parser"
local Box3 = require "box3"
local Ex = require "extensions"


---@return integer|nil slotNumber
local function findEmptySlot()
    for i = 16, 1, -1 do
        if turtle.getItemCount(i) == 0 then return i end
    end
    return nil
end

local function mineMove1(move, detect, dig, suck, attack)
    if move() then return true end
    -- 行けなかった

    -- ブロックがあるなら掘る
    if detect() then

        -- 掘る
        dig()

        -- 拾う
        suck()
    end

    -- 掘ったら行けた?
    if move() then return true end

    if not detect() then
        if move() then return true end
        -- エンティティがいる?
        -- 待機
        os.sleep(1)
    end

    -- エンティティがいる?
    while not detect() do
        if move() then return true end
        -- 攻撃
        attack()
    end

    -- 移動
    local ok, reason = move()
    if ok then return true end

    -- 失敗
    Ex.printError("move failed: ", reason)
    return false
end
local function mineDown1()
    return mineMove1(
        Memoried.moveDown,
        Memoried.detectDown,
        Memoried.digDown,
        turtle.suckDown,
        turtle.attackDown
    )
end

local function mineUp1()
    return mineMove1(
        Memoried.moveUp,
        Memoried.detectUp,
        Memoried.digUp,
        turtle.suckUp,
        turtle.attackUp
    )
end

local function mineForward1()
    return mineMove1(
        Memoried.move,
        Memoried.detect,
        Memoried.dig,
        turtle.suck,
        turtle.attack
    )
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
local downMiningPriorityRatio = 1.1
local aroundMiningPriorityRatio = 1
local upMiningPriorityRatio = 0.9

local movePriorityRatio = 1
local moveDownPriorityRatio = 1.1
local moveAroundPriorityRatio = 1
local moveUpPriorityRatio = 0.9

---@class Rule
---@field public name string
---@field public when fun(): boolean|number
---@field public action fun(): any

---@param detect fun(): boolean
---@param priorityRatio number
---@param dx number
---@param dy number
---@param dz number
local function whenMine(detect, priorityRatio, dx, dy, dz)
    if not detect() then return false end

    local x, y, z = Memoried.currentPosition()
    local request = Memoried.getRequest "mining"
    if not request then return false end
    if not inMiningRequestRange(request, x + dx, y + dy, z + dz) then return false end

    local priority = Memoried.memory.requestPriority or defaultRequestPriority
    priority = priority * priorityRatio

    -- if isSunLight(x, y, z) then
    --     priority = priority * sunLightMiningPriorityRatio
    -- end
    return priority
end

---@param detect fun(): boolean
---@param priorityRatio number
---@param nx number
---@param ny number
---@param nz number
local function whenMove(detect, priorityRatio, nx, ny, nz)
    local level = turtle.getFuelLevel()
    if level ~= "unlimited" and level <= 0 then return false end

    if detect() then return false end

    local request = Memoried.getRequest "mining"
    if not request then return false end

    local x, y, z = Memoried.currentPosition()
    if not inMiningRequestRange(request, x + nx, y + ny, z + nz) then return false end

    local limit = turtle.getFuelLimit()
    local priority = Memoried.memory.requestPriority or defaultRequestPriority
    priority = priority * movePriorityRatio * priorityRatio
    if level ~= "unlimited" then priority = priority * math.min(1, 1.5 * (level / limit) + 0.5) end
    return priority
end

---@type Rule[]
local rules = {}
rules[#rules+1] = {
    name = "mining request: dig down",
    when = function ()
        return whenMine(Memoried.detectDown, downMiningPriorityRatio, 0, -1, 0)
    end,
    action = function ()
        local ok, reason = Memoried.digDown()
        if not ok then Ex.printError(reason) end
    end,
}
rules[#rules+1] = {
    name = "mining request: dig forward",
    when = function ()
        local nx, ny, nz = Memoried.currentForward()
        return whenMine(Memoried.detect, aroundMiningPriorityRatio, nx, ny, nz)
    end,
    action = function ()
        local ok, reason = Memoried.dig()
        if not ok then Ex.printError(reason) end
    end,
}
rules[#rules+1] = {
    name = "mining request: dig up",
    when = function ()
        return whenMine(Memoried.detectUp, upMiningPriorityRatio, 0, 1, 0)
    end,
    action = function ()
        local ok, reason = Memoried.digUp()
        if not ok then Ex.printError(reason) end
    end,
}
rules[#rules+1] = {
    name = "mining request: dig right",
    when = function ()
        local nx, ny, nz = Memoried.currentRight()
        return whenMine(Memoried.detectRightInMemory, aroundMiningPriorityRatio, nx, ny, nz)
    end,
    action = function ()
        if not Memoried.turnRight() then return end
        local ok, reason = Memoried.dig()
        if not ok then Ex.printError(reason) end
    end
}
rules[#rules+1] = {
    name = "mining request: dig left",
    when = function ()
        local nx, ny, nz = Memoried.currentLeft()
        return whenMine(Memoried.detectLeftInMemory, aroundMiningPriorityRatio, nx, ny, nz)
    end,
    action = function ()
        if not Memoried.turnLeft() then return end
        local ok, reason = Memoried.dig()
        if not ok then Ex.printError(reason) end
    end
}
rules[#rules+1] = {
    name = "mining request: move down",
    when = function ()
        return whenMove(Memoried.detectDown, moveDownPriorityRatio, 0, -1, 0)
    end,
    action = mineDown1
}
rules[#rules+1] = {
    name = "mining request: move up",
    when = function ()
        return whenMove(Memoried.detectUp, moveUpPriorityRatio, 0, 1, 0)
    end,
    action = mineUp1
}
rules[#rules+1] = {
    name = "mining request: move forward",
    when = function ()
        local nx, ny, nz = Memoried.currentForward()
        return whenMove(Memoried.detect, moveAroundPriorityRatio, nx, ny, nz)
    end,
    action = mineForward1
}
rules[#rules+1] = {
    name = "mining request: move right",
    when = function ()
        local nx, ny, nz = Memoried.currentRight()
        return whenMove(Memoried.detectRightInMemory, moveAroundPriorityRatio, nx, ny, nz)
    end,
    action = function ()
        if not Memoried.turnRight() then return end
        mineForward1()
    end
}
rules[#rules+1] = {
    name = "mining request: move left",
    when = function ()
        local nx, ny, nz = Memoried.currentLeft()
        return whenMove(Memoried.detectLeftInMemory, moveAroundPriorityRatio, nx, ny, nz)
    end,
    action = function ()
        if not Memoried.turnLeft() then return end
        mineForward1()
    end
}
rules[#rules+1] = {
    name = "mining request: suck forward",
    when = function ()
        local emptySlot = findEmptySlot()
        if emptySlot then
            local oldSlot = turtle.getSelectedSlot()
            turtle.select(emptySlot)
            if turtle.suck(1) then
                turtle.drop(turtle.getItemCount())
                turtle.select(oldSlot)
                return 1
            else
                return false
            end
        else
            -- TODO: 空きが無いときもアイテムをスタックできる
            return false
        end
    end,
    action = function()
        local ok, reason = turtle.suck()
        if not ok then
            Ex.printError("suck", reason)
        end
    end
}

-- インベントリが満タンならチェストまで移動して入れる
-- ホームに帰れなくなりそうなら帰るか燃料を探す
-- turn などで map 情報 ( ブロック、チェスト ) を収集する
-- move などで map 情報 ( ブロック、チェスト ) を収集する

local function evaluateRules()
    local maxPriorityRules = {}

    while true do
        local maxPriority = -99999999
        for i = 1, #rules do
            local rule = rules[i]
            local priority = rule.when()
            if priority then
                if maxPriority <= priority then
                    if maxPriority < priority then Ex.clearTable(maxPriorityRules) end
                    maxPriorityRules[#maxPriorityRules+1] = rule
                    maxPriority = priority
                end
                print(rule.name, "=>", priority)
            end
        end
        if #maxPriorityRules == 0 then return true end

        local rule = maxPriorityRules[math.random(1, #maxPriorityRules)]
        Ex.clearTable(maxPriorityRules)

        print("run", rule.name, maxPriority)
        rule.action()
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
