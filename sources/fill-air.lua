local refuel = require "refuel"

local function digLine(forward)
    for _ = 1, forward do
        turtle.dig()
        refuel()
        local ok, reason = turtle.forward()
        if not ok then error(reason) end
    end
end

local function figWall(forward, down)
    for _ = 1, down do
        digLine(forward)
        turtle.digDown()
        refuel()
        local ok, reason = turtle.down()
        if not ok then error(reason) end
        turtle.turnLeft()
        turtle.turnLeft()
    end
end

local args = {...}
figWall(args[1], args[2])
