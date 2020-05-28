
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

local function moveDown()
    local ok, error = turtle.down()
    if ok then
        position.y = position.y - 1

        local h = memory.moveHistory
        h[#h+1] = position.x
        h[#h+1] = position.y
        h[#h+1] = position.z
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
    io.stderr:write(table.concat(messages, "\t") + "\n")
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
        if not ok then error("moveDown failed: "..reason) end
    end
end
local function mining()
    while true do
        mineDown1()
        os.sleep(0)
    end
end

-- turtle.detectDown
-- turtle.inspectDown
-- turtle.attack

local commands = {
    mining = mining
}

local function processArguments(x, ...) commands[x](...) end
processArguments(...)
