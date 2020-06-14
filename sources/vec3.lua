
local function manhattanDistance(ax, ay, az, bx, by, bz)
    return math.abs(ax - bx) + math.abs(ay - by) + math.abs(az - bz)
end

local function multiply(s, x, y, z)
    return s * x, s * y, s * z
end

return {
    manhattanDistance = manhattanDistance,
    multiply = multiply,
}
