local Vec2 = require "vec2"
local Ex = require "extensions"
local Logger = require "logger"

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

---@class DropHistory
---@field public position integer[]
---@field public item ItemDetail

local memory = {
    -- { dart = 10, sand = 3 }
    blockToDigTryCount = {},
    blockToDigSuccessCount = {},
    itemToFuelLevel = {},
    -- { 0,0,0, 0,0,1, 0,1,1 }
    moveHistory = {},
    setTorchHistory = {},
    -- { { position = { 1, 2, 3 }, item = { ... } }, }
    ---@type DropHistory[]
    dropHistory = {},
    -- { { 1, 2, 3 }, { 1, 2, 1 } }
    chestHistory = {},
    -- { { name = "mining", options = ... }, { name = "attack" } }
    requests = {},
    -- { "0,0,0" = ..., "0,0,-1" = ... }
    map = {},
    -- { nil, "minecraft:diamond_pickaxe", ... }
    equippedItemNames = {}
}
---@param name string
local function hasRequest(name)
    return memory.requests[name] ~= nil
end

---@param name string
---@return Request|nil
local function getRequest(name)
    return memory.requests[name]
end
local function removeRequest(name)
    memory.requests[name] = nil
end

---@param request Request
local function addRequest(request)
    if memory.requests[request.name] then
        return false, "request '"..request.name.."' in memory"
    end
    memory.requests[request.name] = request
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
---@field public drops ItemDetail[]|nil
local function clearLocation(location)
    location.move = nil
    location.inspect = nil
    location.detect = nil
    location.drops = nil
end

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
    return (math.modf(x)), y, (math.modf(z))
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
local function currentUp() return 0, 1, 0 end
local function currentDown() return 0, -1, 0 end

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
        return (localDirection + angleY - 1) % 4 + 1
    end
    return localDirection
end

---@param globalDirection integer
local function toLocalDirection(globalDirection)
    if globalDirection == nil then
        error(debug.traceback())
    end
    if 1 <= globalDirection and globalDirection <= 4 then
        return (globalDirection - angleY - 1) % 4 + 1
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
---@param data InspectResult
local function addHistory(data, x, y, z)
    if data.name == "minecraft:chest" then
        Logger.logInfo("add chest history", x, y, z)
        memory.chestHistory[#memory.chestHistory+1] = { x, y, z }
    end
end
local function inspectDown()
    local ok, data = turtle.inspectDown()
    local x, y, z = position[1], position[2] - 1, position[3]
    local l = getOrMakeLocation(x, y, z)
    if ok then
        l.inspect = data
        addHistory(data, x, y, z)

    else
        l.inspect = false
    end
    return ok, data
end
local function inspectUp()
    local ok, data = turtle.inspectUp()
    local x, y, z = position[1], position[2] + 1, position[3]
    local l = getOrMakeLocation(x, y, z)
    if ok then
        l.inspect = data
        addHistory(data, x, y, z)
    else
        l.inspect = false
    end
    return ok, data
end
local function inspect()
    local ok, data = turtle.inspect()
    local x, y, z = currentForward()
    local x, y, z = position[1] + x, position[2] + y, position[3] + z
    local l = getOrMakeLocation(x, y, z)
    if ok then
        l.inspect = data
        addHistory(data, x, y, z)
    else
        l.inspect = false
    end
    return ok, data
end

---@param move fun(): boolean
---@param nx number
---@param ny number
---@param nz number
local function moveGeneric(move, nx, ny, nz)
    local level = turtle.getFuelLevel()
    if level ~= "unlimited" and level <= 0 then
        print "empty fuel"
        return false
    end

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

---@param inspect fun(): boolean, any
---@param dig fun(): boolean, any
---@param nx number
---@param ny number
---@param nz number
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

---@return string|nil
local function equippedItemName(localDirection)
    return memory.equippedItemNames[localDirection]
end

local function equipGeneric(equip, localDirection)
    local item = turtle.getItemDetail()
    local ok, reason = equip()
    if ok then
        memory.equippedItemNames[localDirection] =
            (item and item.name) or nil
    end
    return ok, reason
end

---@generic T
---@param turn fun(): boolean, any
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

local function equipFailure()
    return false, "invalid direction"
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
---@field public drop fun(count: integer): boolean
---@field public inspect fun(): boolean, InspectResult
---@field public attack fun(): boolean
---@field public equip fun(): boolean
---@field public place fun(signText: string): boolean

local function anyItemSpace()
    for i = 1, 16 do
        if turtle.getItemSpace(i) ~= 0 then return true end
    end
    return false
end

local function suckGeneric(suck, count, currentNormal)
    local ok, reason = suck(count)

    if not ok and count ~= 0 and anyItemSpace() then
        -- 1 個以上のアイテムを拾おうとしていて、
        -- スロットの空きがあるのに拾えなかったなら、アイテムは無いはず

        local x, y, z = currentPosition()
        local nx, ny, nz = currentNormal()
        x = x + nx
        y = y + ny
        z = z + nz
        local location = getOrMakeLocation(x, y, z)

        -- drop していない場合と区別するため、空の配列を代入する
        local drops = location.drops or {}
        Ex.clearArray(drops)
        location.drops = drops
    end
    return ok, reason
end

local function suck(count)
    return suckGeneric(turtle.suck, count, currentForward)
end

local function dropGeneric(drop, count, currentNormal)
    local x, y, z = currentPosition()
    local nx, ny, nz = currentNormal()
    x = x + nx
    y = y + ny
    z = z + nz

    local itemDetail = turtle.getItemDetail()
    local ok, reason = drop(count)
    local location = getOrMakeLocation(x, y, z)

    -- drop していない場合と区別するため、空の配列を代入する
    local drops = location.drops
    if not drops then drops = {} location.drops = drops end

    -- 落としたはずのアイテムを記録
    if ok and itemDetail then
        drops[#drops+1] = itemDetail
        local history = memory.dropHistory
        history[#history+1] = {
            position = { x, y, z },
            item = itemDetail,
        }
    end

    return ok, reason
end

local function drop(count)
    return dropGeneric(turtle.drop, count, currentForward)
end

local function addPlaceHistory(item, tx, ty, tz)
    if item.name == "minecraft:torch" then
        memory.setTorchHistory[#memory.setTorchHistory+1] = { tx, ty, tz }
    end
end
local function placeGeneric(place, signText, currentNormal)
    local item = turtle.getItemDetail()
    local ok, reason = place(signText)
    local x, y, z = currentPosition()
    local nx, ny, nz = currentNormal()
    local tx, ty, tz = x + nx, y + ny, z + nz
    local l = getOrMakeLocation(tx, ty, tz)
    if ok then
        l.detect = nil
        l.drops = {}
        l.inspect = nil
        l.move = nil
        addPlaceHistory(item, tx, ty, tz)
    end
    l.place = ok
    return ok, reason
end
local function place(signText)
    return placeGeneric(turtle.place, signText, currentForward)
end
local function placeDown(signText)
    return placeGeneric(turtle.placeDown, signText, currentDown)
end
local function placeUp(signText)
    return placeGeneric(turtle.placeUp, signText, currentUp)
end

---@type DirectionOperations[]
local directionOperations = {
    [Forward] = {
        name = "forward",
        detect = detect,
        currentNormal = currentForward,
        dig = dig,
        place = place,
        move = move,
        suck = suck,
        drop = drop,
        inspect = inspect,
        attack = turtle.attack,
        equip = equipFailure,
    },
    [Left] = {
        name = "left",
        detect = makeTurnAndDo(turnLeft, detect),
        currentNormal = currentLeft,
        dig = makeTurnAndDo(turnLeft, dig),
        place = makeTurnAndDo(turnLeft, place),
        move = makeTurnAndDo(turnLeft, move),
        suck = makeTurnAndDo(turnLeft, suck),
        drop = makeTurnAndDo(turnLeft, drop),
        inspect = makeTurnAndDo(turnLeft, inspect),
        attack = makeTurnAndDo(turnLeft, turtle.attack),
        equip = function () return equipGeneric(turtle.equipLeft, Left) end,
    },
    [Back] = {
        name = "back",
        detect = makeTurnAndDo(turnRight2, detect),
        currentNormal = currentBack,
        dig = makeTurnAndDo(turnRight2, dig),
        place = makeTurnAndDo(turnRight2, place),
        move = makeTurnAndDo(turnRight2, move),
        suck = makeTurnAndDo(turnRight2, suck),
        drop = makeTurnAndDo(turnRight2, drop),
        inspect = makeTurnAndDo(turnRight2, inspect),
        attack = makeTurnAndDo(turnRight2, turtle.attack),
        equip = equipFailure,
    },
    [Right] = {
        name = "right",
        detect = makeTurnAndDo(turnRight, detect),
        currentNormal = currentRight,
        dig = makeTurnAndDo(turnRight, dig),
        place = makeTurnAndDo(turnRight, place),
        move = makeTurnAndDo(turnRight, move),
        suck = makeTurnAndDo(turnRight, suck),
        drop = makeTurnAndDo(turnRight, drop),
        inspect = makeTurnAndDo(turnRight, inspect),
        attack = makeTurnAndDo(turnRight, turtle.attack),
        equip = function () return equipGeneric(turtle.equipRight, Right) end,
    },
    [Down] = {
        name = "down",
        detect = detectDown,
        currentNormal = currentDown,
        dig = digDown,
        place = placeDown,
        move = moveDown,
        suck = function (count) return suckGeneric(turtle.suckDown, count, currentDown) end,
        drop = function (count) return dropGeneric(turtle.dropDown, count, currentDown) end,
        inspect = inspectDown,
        attack = turtle.attackDown,
        equip = equipFailure,
    },
    [Up] = {
        name = "up",
        detect = detectUp,
        currentNormal = currentUp,
        dig = digUp,
        place = placeUp,
        move = moveUp,
        suck = function (count) return suckGeneric(turtle.suckUp, count, currentUp) end,
        drop = function (count) return dropGeneric(turtle.dropUp, count, currentUp) end,
        inspect = inspectUp,
        attack = turtle.attackUp,
        equip = equipFailure,
    },
}
---@param localDirection integer
---@return DirectionOperations
local function getOperation(localDirection)
    return directionOperations[localDirection]
end
---@param globalDirection integer Direction
---@return DirectionOperations
local function getOperationAt(globalDirection)
    return directionOperations[toLocalDirection(globalDirection)]
end

setAir(getOrMakeLocation(currentPosition()))

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
    removeRequest = removeRequest,

    equippedItemName = equippedItemName,

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
    clearLocation = clearLocation,

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
    getOperationAt = getOperationAt,
}
