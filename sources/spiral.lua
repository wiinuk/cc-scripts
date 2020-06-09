local refuel = require "refuel"

local count = ({...})[1]

for _ = 1, count do
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    while turtle.digUp() do end
    refuel()
    while not turtle.up() do end
end

for _ = 1, count do turtle.down() end
