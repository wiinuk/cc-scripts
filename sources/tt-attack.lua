local Tex = require "turtle_extensions"


while true do
    turtle.attack()
    turtle.suck()
    if Tex.selectItem(function () return true end) then
        turtle.dropDown()
    end
end