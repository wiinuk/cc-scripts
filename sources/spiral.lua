local refuel = require "refuel"

local count = ({...})[1]

local function digAround()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
end
for _ = 1, count do
    digAround()
    turtle.digUp()
    refuel()
    turtle.up()
end

for _ = 1, 2 do
    turtle.dig()
    refuel()
    turtle.forward()
end

for _ = 1, count do
    digAround()
    turtle.digDown()
    refuel()
    turtle.down()
end
