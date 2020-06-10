local refuel = require "refuel"
local size = tonumber(({...})[1])

local height = size
for _ = 1, size, 2 do
    --[[
        size = 3
        [ ][ ][ ]
        [ ][ ][ ]
        [^][ ][ ]
    ]]
    turtle.placeDown()
    for _ = 2, height do
        refuel()
        turtle.forward()
        turtle.placeDown()
    end
    height = height - 1
    if height <= 0 then break end

    turtle.turnRight()
    refuel()
    turtle.forward()
    turtle.turnRight()
    refuel()
    turtle.forward()
    --[[
        size = 3
        [■^][ ][ ]
        [■] [ ][ ]
        [■] [ ][ ]
    ]]
    --[[
        size = 3
        [■][ ][ ]
        [■][v][ ]
        [■][ ][ ]
    ]]
    turtle.placeDown()
    for _ = 2, height do
        refuel()
        turtle.forward()
        turtle.placeDown()
    end
    --[[
        size = 3
        [■][ ] [ ]
        [■][■] [ ]
        [■][■v][ ]
    ]]
    height = height - 1
    if height <= 0 then break end

    turtle.turnLeft()
    refuel()
    turtle.forward()
    turtle.turnLeft()
    --[[
        size = 3
        [■][ ][ ]
        [■][■][ ]
        [■][■][^]
    ]]
end