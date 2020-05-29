

---@param r number radians
---@param x number
---@param y number
---@return number x
---@return number y
local function rotate(r, x, y)
    local cosR = math.cos(r)
    local sinR = math.sin(r)
    return
        x * cosR - y * sinR,
        x * sinR + y * cosR
end

return {
    rotate = rotate
}