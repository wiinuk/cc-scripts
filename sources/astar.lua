local Heap = require "heap"

---@alias AStarKey integer

---@class AStarFinder
---@field public state string
---@field public goalX integer
---@field public goalY integer
---@field public goalZ integer
---@field public isMovable fun(x: integer, y: integer, z: integer): boolean
---@field public opens table<integer, AStarKey> @heap

---@field public compareNodeOfCost fun(a: AStarKey, b: AStarKey): number
---@field public positionToStatus table<AStarKey, integer>
---@field public positionToCost table<AStarKey, number>
---@field public positionToScore table<AStarKey, number>
---@field public positionToParent table<AStarKey, AStarKey>

local Open = 1
local Closed = -1

local function isInt17(x)
    return -65536 <= x and x <= 65535 and math.modf(x) == x
end

---@param x integer
---@param y integer
---@param z integer
local function isValidPosition(x, y, z)
    return isInt17(x) and isInt17(y) and isInt17(z)
end

-- 3要素の整数ベクトルを1つの成分当たり 17bit づつ使って double に格納する
-- double の安全な整数は 53bit

--- -65536 <= x <= 65535
local function positionToKey(x, y, z)
    return
        (x + 65536 --[[ 0x10000 ]]) * 17179869184 --[[ 0x400000000 ]] +
        (y + 65536) * 131072 --[[ 0x20000 ]] +
        (z + 65536)
end

--- double に格納された3要素の整数ベクトルを取り出す
local function keyToPosition(key)
    local x = math.modf(key / 17179869184 --[[ 0x400000000 ]]) % 131072 --[[ 0x20000 ]] - 65536 --[[ 0x10000 ]]
    local y = math.modf(key / 131072 --[[ 0x20000 ]]) % 131072 - 65536
    local z = key % 131072 - 65536
    return x, y, z
end

local function printNode(self, message, key)
    local x, y = keyToPosition(key)
    local cost = self.positionToCost[key]
    local score = self.positionToScore[key]
    print(message, x, y, "c:", cost, "s:", score)
end
local function open(self, key, parentKey)
    if self.positionToStatus[key] then return end

    self.positionToStatus[key] = Open
    self.positionToParent[key] = parentKey
    local cost = (self.positionToCost[parentKey] or 0) + 1
    self.positionToCost[key] = cost

    local x, y, z = keyToPosition(key)

    -- static weighing
    local hCost = (self.goalX - x) + (self.goalY - y) + (self.goalZ - z)
    self.positionToScore[key] = cost + hCost * 5

    Heap.push(self.opens, key, self.compareNodeOfCost)
    if self._debug then printNode(self, "open", key) end
end

local function reverse(xs)
    local n = #xs
    for i = 1, math.floor(n / 2) do
      xs[i], xs[n - i + 1] = xs[n - i + 1], xs[i]
    end
end

local function makePath(self, n)
    local path = {}
    while n do
        local x, y, z = keyToPosition(n)
        path[#path+1] = z
        path[#path+1] = y
        path[#path+1] = x
        n = self.positionToParent[n]
    end
    reverse(path)
    return path
end
local neighborNormals = {
    1,0,0,
    0,1,0,
    0,0,1,
    -1,0,0,
    0,-1,0,
    0,0,-1,
}

---@param isMovable fun(x: integer, y: integer, z: integer): boolean
---@return AStarFinder
local function newFinder(isMovable)
    ---@type AStarFinder
    local self = {
        state = "ready",
        goalX = nil,
        goalY = nil,
        goalZ = nil,
        isMovable = isMovable,
        opens = {},

        positionToCost = {},
        positionToScore = {},
        positionToStatus = {},
        positionToParent = {},
    }
    function self.compareNodeOfCost(a, b)
        local c = self.positionToScore[b] - self.positionToScore[a]
        if c ~= 0 then return c end
        return self.positionToCost[b] - self.positionToCost[a]
    end
    return self
end

local function suspendedToReady(self)
    self.state = "ready"
    self.goalX = nil
    self.goalY = nil
    self.goalZ = nil
    self.opens = {}
    self.positionToStatus = {}
    self.positionToCost = {}
    self.positionToScore = {}
    self.positionToParent = {}
end
local function readyToSuspended(self, goalX, goalY, goalZ)
    self.state = "suspended"
    self.goalX, self.goalY, self.goalZ = goalX, goalY, goalZ
end

local function getBestPath(self)
    local k = Heap.peek(self.opens)
    if k then return makePath(self, k), self.positionToScore[k] end
    return
end

local function findCore(self, maxStep)
    local step = 1
    local compareNodeOfCost = self.compareNodeOfCost
    local goalX, goalY, goalZ = self.goalX, self.goalY, self.goalZ
    local isMovable = self.isMovable
    local positionToStatus = self.positionToStatus
    local opens = self.opens
    local pop = Heap.pop
    local isDebugMode = self._debug

    while step <= maxStep do
        local pk = pop(opens, compareNodeOfCost)
        if not pk then
            suspendedToReady(self)
            return nil, self.state
        end

        local px, py, pz = keyToPosition(pk)

        if isDebugMode then printNode(self, "pop", pk) end
        if px == goalX and py == goalY and pz == goalZ then
            local path = makePath(self, pk)
            suspendedToReady(self)
            return path, self.state
        end

        for i = 1, #neighborNormals, 3 do
            local x, y, z = px + neighborNormals[i], py + neighborNormals[i+1], pz + neighborNormals[i+2]
            if isMovable(x, y, z) then
                open(self, positionToKey(x, y, z), pk)
            end
        end
        positionToStatus[pk] = Closed
        if isDebugMode then printNode(self, "closed", pk) end
        step = step + 1
    end
    return nil, self.state
end

--- requires: 'ready' state
---@param finder AStarFinder
---@param startX integer
---@param startY integer
---@param startZ integer
---@param goalX integer
---@param goalY integer
---@param goalZ integer
---@return integer[] pathOrNil
---@return string lastFinderState
local function initialize(finder, startX, startY, startZ, goalX, goalY, goalZ)
    if finder.state ~= "ready" then return error("invalid state '"..finder.state.."', requires: 'ready'") end
    readyToSuspended(finder, goalX, goalY, goalZ)

    local startKey = positionToKey(startX, startY, startZ)
    open(finder, startKey)
end

--- requires: 'suspended' state
---@param finder AStarFinder
---@param maxStep integer|nil
---@return integer[] pathOrNil
---@return string lastFinderState
local function resume(finder, maxStep)
    if finder.state ~= "suspended" then return error("invalid state '"..finder.state.."', requires: 'suspended'") end
    return findCore(finder, maxStep or (1/0))
end

---@param isMovable fun(x: integer, y: integer, z: integer): boolean
---@param startX integer
---@param startY integer
---@param startZ integer
---@param goalX integer
---@param goalY integer
---@param goalZ integer
---@return integer[] pathOrNil
local function findPath(isMovable, startX, startY, startZ, goalX, goalY, goalZ)
    local finder = newFinder(isMovable)
    initialize(finder, startX, startY, startZ, goalX, goalY, goalZ)
    return (resume(finder))
end

return {
    isValidPosition = isValidPosition,
    newFinder = newFinder,
    initialize = initialize,
    resume = resume,
    findPath = findPath,
    getBestPath = getBestPath,
}
