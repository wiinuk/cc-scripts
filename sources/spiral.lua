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
    turtle.digUp()
    refuel()
    turtle.up()
end

for _ = 1, count do
    refuel()
    turtle.down()
end

for _ = 1, 2 do
    refuel()
    turtle.forward()
end
