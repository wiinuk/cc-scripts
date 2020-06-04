local Heap = require "heap"

---@alias AStarKey integer

---@class AStarFinder
---@field public goalX integer
---@field public goalY integer
---@field public goalZ integer
---@field public isWall fun(x: integer, y: integer, z: integer): boolean
---@field public hCost fun(x: integer, y: integer, z: integer, goalX: integer, goalY: integer, goalZ: integer): number
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

local function hCost(x, y, z, goalX, goalY, goalZ)
    return (goalX - x) + (goalY - y) + (goalZ - z)
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
    local hCost = self.hCost(
        x, y, z,
        self.goalX, self.goalY, self.goalZ
    )
    -- static weighing
    self.positionToScore[key] = cost + hCost * 5

    Heap.push(self.opens, key, self.compareNodeOfCost)
    -- printNode(self, "open", key)
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
local function findPath(isWall, startX, startY, startZ, goalX, goalY, goalZ)
    ---@type AStarFinder
    local self = {
        goalX = goalX,
        goalY = goalY,
        goalZ = goalZ,
        isWall = isWall,
        hCost = hCost,
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

    local startKey = positionToKey(startX, startY, startZ)
    open(self, startKey)

    while true do
        local pk = Heap.pop(self.opens, self.compareNodeOfCost)
        if not pk then return false end
        local px, py, pz = keyToPosition(pk)

        -- printNode(self, "pop", pk)
        if px == self.goalX and py == self.goalY and pz == self.goalZ then return makePath(self, pk) end

        for i = 1, #neighborNormals, 3 do
            local x, y, z = px + neighborNormals[i], py + neighborNormals[i+1], pz + neighborNormals[i+2]
            if not isWall(x, y, z) then
                open(self, positionToKey(x, y, z), pk)
            end
        end
        self.positionToStatus[pk] = Closed
        -- printNode(self, "closed", pk)
    end
end

return {
    isValidPosition = isValidPosition,
    findPath = findPath,
}
