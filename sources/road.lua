local refuel = require "refuel"


for _ = 0, ({...})[1] do
    turtle.turnLeft()
    turtle.place()
    turtle.turnRight()
    turtle.turnRight()
    turtle.place()
    turtle.turnLeft()
    refuel()
    turtle.back()
    turtle.place()
end
