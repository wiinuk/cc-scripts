local Vec2 = require "vec2"

-- スクリプト開始時の座標をホームとする

--- ホームを (x: 0, y: 0, z: 0) としたときの相対座標
local position = { 0, 0, 0 }
--- {x, y, z}
local facing = { 0, 0, 1 }

---@class Request
---@field public name string

local memory = {
    -- { dart = 10, sand = 3 }
    blockToDigTryCount = {},
    blockToDigSuccessCount = {},
    -- { 0,0,0, 0,0,1, 0,1,1 }
    moveHistory = {},
    -- { { name = "mining", options = ... }, { name = "attack" } }
    requests = {},
    -- {0 = ..., 1 = ...}
    map = {},
}
---@param name string
local function hasRequest(name)
    if memory.requests then
        local rs = memory.requests
        for i = 1, #rs do
            local r = rs[i]
            if r == name or (r and r.name == name) then
                return true
            end
        end
    end
    return false
end

---@param name string
---@return Request|nil
local function getRequest(name)
    if memory.requests then
        local rs = memory.requests
        for i = 1, #rs do
            local r = rs[i]
            if r == name or (r and r.name == name) then
                return r
            end
        end
    end
    return nil
end

---@param request Request
local function addRequest(request)
    memory.requests[#memory.requests+1] = request
    return true
end

---@param x number
---@param y number
---@param z number
local function locationKey(x, y, z)
    x = math.modf(x)
    y = math.modf(y)
    z = math.modf(z)
    return x + y * 0xFF + z * 0xFFFF
end

---@class InspectResult
---@field public name string
---@field public metadata integer
---@field public state table

---@class Location
---@field public detect boolean|nil
---@field public inspect InspectResult|nil
---@field public move boolean|nil

---@param x number
---@param y number
---@param z number
---@return Location|nil
local function getLocation(x, y, z)
    return memory.map[locationKey(x, y, z)]
end

---@param x number
---@param y number
---@param z number
---@return Location
local function getOrMakeLocation(x, y, z)
    local key = locationKey(x, y, z)
    local map = memory.map
    local l = map[key]
    if l then return l end

    local l = {}
    map[key] = l
    return l
end

---@param l Location
local function setToAir(l)
    l.move = true
    l.inspect = nil
    l.detect = false
end

---@return integer x
---@return integer y
---@return integer z
local function currentPosition()
    return position[1], position[2], position[3]
end
local function currentY()
    return position[2]
end
--- Returns the face orientation
---@return integer x
---@return integer y
---@return integer z
local function currentForward()
    return facing[1], facing[2], facing[3]
end
--- Returns the left direction of the face
---@return integer x
---@return integer y
---@return integer z
local function currentLeft()
    local x, z = Vec2.rotate(0.5 * math.pi, facing[1], facing[3])
    local x = math.modf(x)
    local z = math.modf(z)
    return x, facing[2], z
end
--- Returns the right direction of the face
---@return integer x
---@return integer y
---@return integer z
local function currentRight()
    local x, z = Vec2.rotate(-0.5 * math.pi, facing[1], facing[3])
    local x = math.modf(x)
    local z = math.modf(z)
    return x, facing[2], z
end
local function pushPosition()
    local h = memory.moveHistory
    h[#h+1] = position[1]
    h[#h+1] = position[2]
    h[#h+1] = position[3]
end

---@return boolean
local function detectDown()
    local ok = turtle.detectDown()
    getOrMakeLocation(position[1], position[2] - 1, position[3]).detect = ok
    return ok
end
---@return boolean
local function detectUp()
    local ok = turtle.detectUp()
    getOrMakeLocation(position[1], position[2] + 1, position[3]).detect = ok
    return ok
end
---@return boolean detected
local function detect()
    local ok = turtle.detect()
    getOrMakeLocation(position[1] + facing[1], position[2] + facing[2], position[3] + facing[3]).detect = ok
    return ok
end
---@param move fun(): boolean
---@param nx number
---@param ny number
---@param nz number
local function moveGeneric(move, nx, ny, nz)
    local x, y, z = position[1], position[2], position[3]
    x, y, z = x + nx, y + ny, z + nz
    local ok, reason = move()
    getOrMakeLocation(x, y, z).move = ok

    if ok then
        position[1] = x
        position[2] = y
        position[3] = z
        pushPosition()
    end
    return ok, reason
end

local function moveDown()
    return moveGeneric(turtle.down, 0, -1, 0)
end
local function moveUp()
    return moveGeneric(turtle.up, 0, 1, 0)
end
local function move()
    return moveGeneric(turtle.forward, facing[1], facing[2], facing[3])
end

local function turnRight()
    local ok, reason = turtle.turnRight()
    if ok then
        local x, z = Vec2.rotate(-0.5 * math.pi, facing[1], facing[3])
        facing[1] = math.modf(x)
        facing[3] = math.modf(z)
    end
    return ok, reason
end
local function turnLeft()
    local ok, reason = turtle.turnLeft()
    if ok then
        local x, z = Vec2.rotate(0.5 * math.pi, facing[1], facing[3])
        facing[1] = math.modf(x)
        facing[3] = math.modf(z)
    end
    return ok, reason
end

local function digGeneric(inspect, dig, nx, ny, nz)
    local ok, info = inspect()
    if not ok then return false, info end
    local blockName = info.name

    memory.blockToDigTryCount[blockName] = (memory.blockToDigTryCount[blockName] or 0) + 1
    local ok, info = dig()

    if not ok then return false, info end

    memory.blockToDigSuccessCount[blockName] = (memory.blockToDigSuccessCount[blockName] or 0) + 1

    local x, y, z = position[1], position[2], position[3]

    -- 空気になった
    setToAir(getOrMakeLocation(x + nx, y + ny, z + nz))

    return true
end

local function digDown()
    return digGeneric(turtle.inspectDown, turtle.digDown, 0, -1, 0)
end
local function digUp()
    return digGeneric(turtle.inspectUp, turtle.digUp, 0, 1, 0)
end
local function dig()
    return digGeneric(turtle.inspect, turtle.dig, facing[1], facing[2], facing[3])
end

---@param x number
---@param y number
---@param z number
local function detectInMemory(x, y, z)

    -- 記憶上のマップを検索する
    local location = getLocation(x, y, z)
    if location then
        local detect = location.detect

        -- 当たったことがあるならその結果を返す
        if detect == true or detect == false then return detect end

        -- 調べたことがあるか
        local inspect = location.inspect
        if inspect then

            -- 同じブロックを掘ったことがあるなら当たるとする
            local digSuccessCount = memory.blockToDigSuccessCount[inspect.name]
            if digSuccessCount and 0 < digSuccessCount then return true end
        end
    end
    return false
end

local function detectRightInMemory()
    local x, y, z = currentPosition()
    local nx, ny, nz = currentRight()
    return detectInMemory(x + nx, y + ny, z + nz)
end

local function detectLeftInMemory()
    local x, y, z = currentPosition()
    local nx, ny, nz = currentLeft()
    return detectInMemory(x + nx, y + ny, z + nz)
end

return {
    memory = memory,

    currentPosition = currentPosition,
    currentY = currentY,
    currentForward = currentForward,
    currentRight = currentRight,
    currentLeft = currentLeft,

    addRequest = addRequest,
    hasRequest = hasRequest,
    getRequest = getRequest,

    turnRight = turnRight,
    turnLeft = turnLeft,

    moveDown = moveDown,
    moveUp = moveUp,
    move = move,

    detectDown = detectDown,
    detectUp = detectUp,
    detect = detect,

    digDown = digDown,
    digUp = digUp,
    dig = dig,

    detectRightInMemory = detectRightInMemory,
    detectLeftInMemory = detectLeftInMemory,
}