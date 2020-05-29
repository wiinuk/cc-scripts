
---@class Box3
---@field public minX number
---@field public minY number
---@field public minZ number
---@field public maxX number
---@field public maxY number
---@field public maxZ number

---@param box Box3
---@param x number
---@param y number
---@param z number
local function expandByPoint(box, x, y, z)
    box.minX = math.min(box.minX, x)
    box.minY = math.min(box.minY, y)
    box.minZ = math.min(box.minZ, z)
    box.maxX = math.max(box.maxX, x)
    box.maxY = math.max(box.maxY, y)
    box.maxZ = math.max(box.maxZ, z)
end

---@param x number
---@param y number
---@param z number
---@return Box3
local function newFromPoint(x, y, z)
    return {
        minX = x, minY = y, minZ = z,
        maxX = x, maxY = y, maxZ = z,
    }
end

---@param box Box3
---@param x number
---@param y number
---@param z number
local function vsPoint(box, x, y, z)
    return
        (x >= box.minX and x <= box.maxX) and
        (y >= box.minY and y <= box.maxY) and
        (z >= box.minZ and z <= box.maxZ)
end

return {
    newFromPoint = newFromPoint,
    expandByPoint = expandByPoint,
    vsPoint = vsPoint,
}