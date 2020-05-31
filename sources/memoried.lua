local Vec2 = require "vec2"

-- スクリプト開始時の座標をホームとする

--- ホームを (x: 0, y: 0, z: 0) としたときの相対座標
local position = { 0, 0, 0 }
--- 0,1,2,3
--- - 顔が `0, 0, 1` を向いているなら `0`
--- - 顔が `-1, 0, 0` を向いているなら `1`
--- - 顔が `0, 0, -1` を向いているなら `2`
--- - 顔が `1, 0, 0` を向いているなら `3`
local angleY = 0

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

--- -9999 … 9999
---@param x number
---@param y number
---@param z number
local function locationKey(x, y, z)
    return tostring(x)..","..tostring(y)..","..tostring(z)
end

---@class InspectResult
---@field public name string
---@field public metadata integer
---@field public state table|nil

---@class Location
---@field public detect boolean|nil
---@field public inspect InspectResult|boolean|nil
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
local function setAir(l)
    l.move = true
    l.inspect = false
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

---@param x number
---@param y number
---@param z number
local function applyRotationTruncate(x, y, z)
    local x, z = Vec2.rotate(angleY * 0.5 * math.pi, x, z)
    return math.modf(x), y, math.modf(z)
end
--- 顔の方向を表す長さ 1 のベクトルを返す。
--- 最初の顔の方向は `0, 0, 1`
--- ```lua
--- x, y, z = currentForward()
--- assert(x == 0 and y == 0 and z == 1)
--- turnRight()
--- x, y, z = currentForward()
--- assert(x == 1 and y == 0 and z == 0)
--- turnRight()
--- x, y, z = currentForward()
--- assert(x == 0 and y == 0 and z == -1)
--- ```
---@return integer x
---@return integer y
---@return integer z
local function currentForward()
    return applyRotationTruncate(0, 0, 1)
end
--- 顔の右の方向を表す長さ 1 のベクトルを返す
---@return integer x
---@return integer y
---@return integer z
local function currentRight()
    return applyRotationTruncate(1, 0, 0)
end
--- 顔の左の方向を表す長さ 1 のベクトルを返す
---@return integer x
---@return integer y
---@return integer z
local function currentLeft()
    return applyRotationTruncate(-1, 0, 1)
end
--- 顔の後ろの方向を表す長さ 1 のベクトルを返す
---@return integer x
---@return integer y
---@return integer z
local function currentBack()
    return applyRotationTruncate(0, 0, -1)
end

--- 世界のY軸上の角度[ラジアン] をタートルから見た角度に変換する
---
--- 角度
---   - `0, 0, 1` の角度が `0`
---   - `-1, 0, 0` の角度が `(1/2)*π`
---   - `0, 0, -1` の角度が `π`
---   - `1, 0, 0` の角度が `(3/2)*π`
---@param globalAngleY number ラジアン
---@return integer localAngleY
local function toLocalAngleY(globalAngleY)
    return (globalAngleY - angleY * (math.pi * 0.5)) % (math.pi * 2)
end

---@param localDirection integer
local function toGlobalDirection(localDirection)
    if 1 <= localDirection and localDirection <= 4 then
        return (localDirection + angleY) % 4 + 1
    end
    return localDirection
end

---@param globalDirection integer
local function toLocalDirection(globalDirection)
    if 1 <= globalDirection and globalDirection <= 4 then
        return (globalDirection - angleY) % 4 + 1
    end
    return globalDirection
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
    local x, y, z = currentForward()
    getOrMakeLocation(position[1] + x, position[2] + y, position[3] + z).detect = ok
    return ok
end
local function inspectDown()
    local ok, data = turtle.inspectDown()
    local l = getOrMakeLocation(position[1], position[2] - 1, position[3])
    if ok then l.inspect = data
    else l.inspect = false end
    return ok, data
end
local function inspectUp()
    local ok, data = turtle.inspectUp()
    local l = getOrMakeLocation(position[1], position[2] + 1, position[3])
    if ok then l.inspect = data
    else l.inspect = false end
    return ok, data
end
local function inspect()
    local ok, data = turtle.inspect()
    local x, y, z = currentForward()
    local l = getOrMakeLocation(position[1] + x, position[2] + y, position[3] + z)
    if ok then l.inspect = data
    else l.inspect = false end
    return ok, data
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
    local x, y, z = currentForward()
    return moveGeneric(turtle.forward, x, y, z)
end

---@return boolean success
---@return any reason
local function turnRight()
    local ok, reason = turtle.turnRight()
    if ok then angleY = (angleY - 1) % 4 end
    return ok, reason
end
local function turnLeft()
    local ok, reason = turtle.turnLeft()
    if ok then angleY = (angleY + 1) % 4 end
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
    setAir(getOrMakeLocation(x + nx, y + ny, z + nz))

    return true
end

local function digDown()
    return digGeneric(inspectDown, turtle.digDown, 0, -1, 0)
end
local function digUp()
    return digGeneric(inspectUp, turtle.digUp, 0, 1, 0)
end
local function dig()
    local x, y, z = currentForward()
    return digGeneric(inspect, turtle.dig, x, y, z)
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
local function detectBackInMemory()
    local x, y, z = currentPosition()
    local nx, ny, nz = currentBack()
    return detectInMemory(x + nx, y + ny, z + nz)
end

---@param x number
---@param y number
---@param z number
local function canDigInMemory(x, y, z)
    -- 記憶上のマップを検索する
    local location = getLocation(x, y, z)
    if location then
        -- 動けたことがあるならブロックはない
        if location.move then return false end
        -- 当たらなかったことがあるならブロックはない
        if location.detect == false then return false end

        local inspect = location.inspect
        if inspect then
            -- 同じブロックを掘ったことがあるか
            local digSuccessCount = memory.blockToDigSuccessCount[inspect.name]
            if digSuccessCount and 0 < digSuccessCount then return true end
        end

        return false
    end
    return false
end

local function makeTurnAndDo(turn, op)
    return function(...)
        local ok, reason = turn()
        if not ok then return ok, reason end
        return op(...)
    end
end

local function turnRight2()
    local ok, reason = turnRight()
    if not ok then return ok, reason end
    local ok, reason = turnRight()
    if not ok then return ok, reason end
    return true
end

local Forward = 1
local Left = 2
local Back = 3
local Right = 4
local Down = 5
local Up = 6

---@class DirectionOperations
---@field public name string
---@field public detect fun(): boolean
---@field public currentNormal fun(): integer, integer, integer
---@field public dig fun(): boolean, any
---@field public move fun(): boolean, any
---@field public suck fun(amount: number): boolean, any
---@field public inspect fun(): boolean, table

---@type DirectionOperations[]
local directionOperations = {
    [Forward] = {
        name = "forward",
        detect = detect,
        currentNormal = currentForward,
        dig = dig,
        move = move,
        suck = turtle.suck,
        inspect = inspect,
    },
    [Left] = {
        name = "left",
        detect = detectLeftInMemory,
        currentNormal = currentLeft,
        dig = makeTurnAndDo(turnLeft, dig),
        move = makeTurnAndDo(turnLeft, move),
        suck = makeTurnAndDo(turnLeft, turtle.suck),
        inspect = makeTurnAndDo(turnLeft, inspect),
    },
    [Back] = {
        name = "back",
        detect = detectBackInMemory,
        currentNormal = currentBack,
        dig = makeTurnAndDo(turnRight2, dig),
        move = makeTurnAndDo(turnRight2, move),
        suck = makeTurnAndDo(turnRight2, turtle.suck),
        inspect = makeTurnAndDo(turnRight2, inspect),
    },
    [Right] = {
        name = "right",
        detect = detectRightInMemory,
        currentNormal = currentRight,
        dig = makeTurnAndDo(turnRight, dig),
        move = makeTurnAndDo(turnRight, move),
        suck = makeTurnAndDo(turnRight, turtle.suck),
        inspect = makeTurnAndDo(turnRight, inspect),
    },
    [Down] = {
        name = "down",
        detect = detectDown,
        currentNormal = function () return 0, -1, 0 end,
        dig = digDown,
        move = moveDown,
        suck = turtle.suckDown,
        inspect = inspectDown,
    },
    [Up] = {
        name = "up",
        detect = detectUp,
        currentNormal = function () return 0, 1, 0 end,
        dig = digUp,
        move = moveUp,
        suck = turtle.suckUp,
        inspect = inspectUp,
    },
}
---@param direction integer 1|2|3|4|5|6
---@return DirectionOperations
local function getOperation(direction)
    return directionOperations[direction]
end

return {
    memory = memory,

    currentPosition = currentPosition,
    currentY = currentY,
    currentForward = currentForward,
    currentRight = currentRight,
    currentLeft = currentLeft,
    currentBack = currentBack,

    toLocalAngleY = toLocalAngleY,
    toGlobalDirection = toGlobalDirection,
    toLocalDirection = toLocalDirection,

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

    getLocation = getLocation,

    detectRightInMemory = detectRightInMemory,
    detectLeftInMemory = detectLeftInMemory,
    detectBackInMemory = detectBackInMemory,

    canDigInMemory = canDigInMemory,

    Forward = Forward,
    Left = Left,
    Back = Back,
    Right = Right,
    Down = Down,
    Up = Up,

    getOperation = getOperation,
}