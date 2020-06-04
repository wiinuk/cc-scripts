local Heap = require "heap"

---@class AStarNode
---@field public x integer
---@field public y integer
---@field public z integer
---@field public status integer
---@field public cost number
---@field public hCost number
---@field public score number
---@field public parent AStarNode|nil

---@class AStarFinder
---@field public goalX integer
---@field public goalY integer
---@field public goalZ integer
---@field public isWall fun(x: integer, y: integer, z: integer): boolean
---@field public hCost fun(x: integer, y: integer, z: integer, goalX: integer, goalY: integer, goalZ: integer): number
---@field public opens AStarNode[] @heap
---@field public positionToNode table<integer, AStarNode>

local None = 0
local Open = 1
local Closed = -1

local function isInt17(x)
    return -65536 <= x and x <= 65535 and math.modf(x) == x
end

-- 3要素の整数ベクトルを1つの成分当たり 17bit づつ使って double に格納する
-- double の安全な整数は 53bit

--- -65536 <= x <= 65535
local function positionToKey(x, y, z)
    return
        (x + 0x10000) * 0x400000000 +
        (y + 0x10000) * 0x20000 +
        (z + 0x10000)
end

--- double に格納された3要素の整数ベクトルを取り出す
local function keyToPosition(key)
    local x = (math.modf(key / 0x400000000) % 0x20000) - 0x10000
    local y = (math.modf(key / 0x20000) % 0x20000) - 0x10000
    local z = (key % 0x20000) - 0x10000
    return x, y, z
end

local function hCost(x, y, z, goalX, goalY, goalZ)
    return (goalX - x) + (goalY - y) + (goalZ - z)
end

local function compareNodeOfCost(a, b)
    local c = b.score - a.score
    if c ~= 0 then return c end
    return b.cost - a.cost
end

local function none(self, x, y, z)
    local key = positionToKey(x, y, z)
    local node = self.positionToNode[key]
    if node then return node end

    local node = {
        x = x,
        y = y,
        z = z,
        status = None,
        cost = 0,
        hCost = 0,
        score = 0,
        parent = nil,
    }
    self.positionToNode[key] = node
    return node
end

local function printNode(message, node)
    print(message, node.x, node.y, "c:", node.cost, "h:", node.hCost, "s:", node.score)
end
local function open(self, node, parent)
    if node.status ~= None then return end

    node.status = Open
    node.parent = parent
    if parent then
        node.cost = parent.cost + 1
    else
        node.cost = 0
    end
    node.hCost = self.hCost(
        node.x, node.y, node.z,
        self.goalX, self.goalY, self.goalZ
    )
    -- static weighing
    node.score = node.cost + node.hCost * 5
    Heap.push(self.opens, node, compareNodeOfCost)

    -- printNode("open", node)
end

local function reverse(xs)
    local n = #xs
    for i = 1, math.floor(n / 2) do
      xs[i], xs[n - i + 1] = xs[n - i + 1], xs[i]
    end
end

local function makePath(n)
    local path = {}
    while n do
        path[#path+1] = n.z
        path[#path+1] = n.y
        path[#path+1] = n.x
        n = n.parent
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
    local f = {
        goalX = goalX,
        goalY = goalY,
        goalZ = goalZ,
        isWall = isWall,
        hCost = hCost,
        opens = {},
        positionToNode = {},
    }
    open(f, none(f, startX, startY, startZ), nil)
    while true do
        local p = Heap.pop(f.opens, compareNodeOfCost)
        if not p then return false end

        -- printNode("pop", p)
        if p.x == f.goalX and p.y == f.goalY and p.z == f.goalZ then return makePath(p) end

        for i = 1, #neighborNormals, 3 do
            local x, y, z = p.x + neighborNormals[i], p.y + neighborNormals[i+1], p.z + neighborNormals[i+2]
            if not isWall(x, y, z) then
                open(f, none(f, x, y, z), p)
            end
        end
        p.status = Closed
        -- printNode("closed", p)
    end
end

return {
    findPath = findPath,
}
