
-- スクリプト開始時の座標をホームとする

--- ホームを (0, 0, 0) としたときの相対座標
local position = { x = 0, y = 0, z = 0 }

-- turtle.detectDown
-- turtle.inspectDown
-- turtle.attack

local function moveDown()
    local ok, error = turtle.down()
    if ok then position.y = position.y - 1 end
    return ok, error
end

local function mineDown()
    while true do
        local ok, reason = turtle.digDown()
        if not ok then error("digDown failed: "..reason) end
        local ok, reason = turtle.suckDown()
        if not ok then error("suckDown failed: "..reason) end
        local ok, reason = moveDown()
        if not ok then error("moveDown failed: "..reason) end
    end
end

local commands = {
    mineDown = mineDown
}

local function processArguments(x, ...) commands[x](...) end
processArguments(...)
