local refuel = require "refuel"

for _ = 1, ({...})[1] do
    turtle.turnRight()
    turtle.place()
    turtle.turnLeft()
    turtle.turnLeft()
    turtle.place()
    turtle.turnRight()
    refuel()
    turtle.up()
    turtle.placeDown()
end