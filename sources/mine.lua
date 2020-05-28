
---@version: 0.0.6

-- スクリプト開始時の座標をホームとする

--- ホームを (0, 0, 0) としたときの相対座標
local position = { x = 0, y = 0, z = 0 }
local memory = {
    -- { dart = 10, sand = 3 }
    blockToDigTryCount = {},
    blockToDigSuccessCount = {},
    -- { 0,0,0, 0,0,1, 0,1,1 }
    moveHistory = {},
}

local function pushPosition()
    local h = memory.moveHistory
    h[#h+1] = position.x
    h[#h+1] = position.y
    h[#h+1] = position.z
end

local function moveDown()
    local ok, error = turtle.down()
    if ok then
        position.y = position.y - 1
        pushPosition()
    end
    return ok, error
end
local function moveUp()
    local ok, error = turtle.up()
    if ok then
        position.y = position.y + 1
        pushPosition()
    end
    return ok, error
end

local function digGeneric(inspect, dig)
    local ok, info = inspect()
    if not ok then return false, info end
    local blockName = info.name

    memory.blockToDigTryCount[blockName] = (memory.blockToDigTryCount[blockName] or 0) + 1
    local ok, info = dig()

    if not ok then return false, info end

    memory.blockToDigSuccessCount[blockName] = (memory.blockToDigSuccessCount[blockName] or 0) + 1
    return true
end

local function digDown()
    return digGeneric(turtle.inspectDown, turtle.digDown)
end
local function digUp()
    return digGeneric(turtle.inspectUp, turtle.digUp)
end

local function printError(...)
    local messages = {...}
    for i = 1, #messages do
        messages[i] = tostring(messages[i])
    end
    io.stderr:write(table.concat(messages, "\t").."\n")
end

local function mineMove1(move, detect, dig, suck, attack)
    if move() then return true end
    -- 行けなかった

    -- ブロックがあるなら掘る
    if detect() then

        -- 掘る
        dig()

        -- 拾う
        local ok, reason = suck()
        if not ok then

            -- 拾えなかった
            printError("suck failed:", reason)
        end
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
    printError("move failed: ", reason)
    return false
end
local function mineDown1()
    return mineMove1(
        moveDown,
        turtle.detectDown,
        digDown,
        turtle.suckDown,
        turtle.attackDown
    )
end

local function mineUp1()
    return mineMove1(
        moveUp,
        turtle.detectUp,
        digUp,
        turtle.suckUp,
        turtle.attackUp
    )
end
local function selectMostCommonItemSlot()
    local maxFitness = 0
    local maxFitnessSlotNumber = nil
    for i = 1, 16 do
        local slotItem = turtle.getItemDetail()
        -- スロットが空なら nil
        -- ダメージがあるアイテムは除く
        if slotItem and slotItem.damage == 0 then

            -- local tryCount = memory.blockToDigTryCount[slotItem.name] or 0
            local successCount = memory.blockToDigSuccessCount[slotItem.name] or 0
            local fitness = successCount + slotItem.count
            if maxFitness < fitness then
                maxFitness = fitness
                maxFitnessSlotNumber = i
            end
        end
    end
    if maxFitnessSlotNumber then
        turtle.select(maxFitnessSlotNumber)
        return true
    else
        return false, "all item slot is empty"
    end
end

---@class MiningOptions
---@field public minY integer

---@param options MiningOptions
local function downMining(options)
    local function fillIfLava()
        local ok, info = turtle.inspectDown()
        if ok and info.name == "minecraft:lava" then
            local ok, reason = selectMostCommonItemSlot()
            if not ok then return false, reason end

            return turtle.placeDown()
        end
        return true
    end

    while -options.minY <= position.y do

        -- 溶岩なら埋める
        local ok, reason = fillIfLava()
        if not ok then
            printError("fill lava failed: "..tostring(reason))
        end

        if not mineDown1() then return end
        os.sleep(0)
    end
end

local function upTo(y)
    while position.y ~= y do
        local ok, error = mineUp1()
        if not ok then return false, error end
    end
    return true
end

---@param options MiningOptions
local function mining(options)
    local startY = position.y

    print("down mining...")
    downMining(options)

    print("up to "..tostring(startY).."...")
    upTo(startY)

    print("y: "..tostring(position.y))
end

---@param arguments string[]
---@param options MiningOptions
local function parseMiningOptions(options, arguments)
    local i = 1
    while i <= #arguments do
        local arg = arguments[i]
        if
            string.lower(arg) == string.lower("--down") or
            string.lower(arg) == "-d"
        then
            i = i + 1
            if i <= #arguments then
                -- TODO: check format
                options.minY = tonumber(arguments[i])
                i = i + 1
            else
                return error("requires <down>")
            end
        else
            return error("unrecognized argument"..arg)
        end
    end
    return true
end
local function miningCommand(...)
    ---@type MiningOptions
    local options = {
        minY = 10
    }
    print("# mining")
    parseMiningOptions(options, {...})
    print("options: ")
    print("- minY", options.minY)
    print("")
    mining(options)
end

-- turtle.detectDown
-- turtle.inspectDown
-- turtle.attack

local commands = {
    mining = miningCommand
}

local function processArguments(x, ...) commands[x](...) end
processArguments(...)
