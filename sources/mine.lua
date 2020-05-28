
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

local function digDown()
    local ok, info = turtle.inspectDown()
    if not ok then return false, info end
    local blockName = info.name

    memory.blockToDigTryCount[blockName] = (memory.blockToDigTryCount[blockName] or 0) + 1
    local ok, info = turtle.digDown()

    if not ok then return false, info end

    memory.blockToDigSuccessCount[blockName] = (memory.blockToDigSuccessCount[blockName] or 0) + 1
    return true
end

local function printError(...)
    local messages = {...}
    for i = 1, #messages do
        messages[i] = tostring(messages[i])
    end
    io.stderr:write(table.concat(messages, "\t").."\n")
end

local function mineDown1()
    if not moveDown() then
        -- 行けなかった

        -- ブロックがあるなら
        if turtle.detectDown() then

            -- 掘る
            digDown()

            -- 拾う
            local ok, reason = turtle.suckDown()
            if not ok then

                -- 拾えなかった
                printError("suckDown failed:", reason)
            end
        end

        local ok, reason = moveDown()
        if not ok then printError("moveDown failed: "..reason) end
        return ok
    else
        return true
    end
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

    while options.minY <= position.y do

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
        local ok, error = moveUp()
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
end

---@param arguments string[]
---@param options MiningOptions
local function parseMiningOptions(options, arguments)
    local i = 1
    while i <= #arguments do
        local arg = arguments[i]
        if string.lower(arg) == string.lower("--minY") then
            i = i + 1
            if i <= #arguments then
                -- TODO: check format
                options.minY = tonumber(arguments[i])
                i = i + 1
            else
                return error("requires <minY>")
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
