package.path = package.path..";./libraries/?.lua"

local Tex = require "turtle_extensions"
local Tree = require "tree-core"

Tree.digTree()

-- 邪魔しないように引く

for _ = 1, 10 do
    if turtle.detectDown() then break end
    Tex.moveDown()
end

for _ = 1, 4 do
    turtle.suck()
    turtle.turnRight()
end
turtle.suckUp()
