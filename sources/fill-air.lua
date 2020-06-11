local refuel = require "refuel"

local args = {...}

local function digLine(n)
    for _ = 1, n do
        turtle.dig()
        refuel()
        local ok, reason = turtle.forward()
        if not ok then error(reason) end
    end
end

for _ = 1, args[2] do
    digLine(args[1])
    turtle.digDown()
    refuel()
    local ok, reason = turtle.down()
    if not ok then error(reason) end
    turtle.turnLeft()
    turtle.turnLeft()
end
