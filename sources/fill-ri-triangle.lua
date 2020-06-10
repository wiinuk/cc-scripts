local refuel = require "refuel"
local size = ({...})[1]

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
    --[[
        size = 3
        [■^][ ][ ]
        [■] [ ][ ]
        [■] [ ][ ]
    ]]
    turtle.turnRight()
    refuel()
    turtle.forward()
    turtle.turnRight()
    refuel()
    turtle.forward()
    height = height - 1
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
    turtle.turnLeft()
    refuel()
    turtle.forward()
    turtle.turnLeft()
    height = height - 1
    --[[
        size = 3
        [■][ ][ ]
        [■][■][ ]
        [■][■][^]
    ]]
end