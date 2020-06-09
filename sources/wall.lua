local refuel = require "refuel"
local Tex = require "turtle_extensions"

if turtle.getItemCount() <= 0 then
    if not Tex.selectItem(function() return true end) then return end
end
local _, item = turtle.getItemDetail()

local function selectItem()
    Tex.selectItem(function(item2) return item2.name == item.name and item2.damage == item.damage end)
end
for _ = 1, ({...})[1] do
    turtle.turnRight()
    selectItem()
    turtle.place()
    turtle.turnLeft()
    turtle.turnLeft()
    selectItem()
    turtle.place()
    turtle.turnRight()
    refuel()
    turtle.up()
    selectItem()
    turtle.placeDown()
end
