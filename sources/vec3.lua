
local function manhattanDistance(ax, ay, az, bx, by, bz)
    return math.abs(ax - bx) + math.abs(ay - by) + math.abs(az - bz)
end

return {
    manhattanDistance = manhattanDistance,
}
