local Cex = require "commands-extensions"
local execCommand = Cex.exec
local UnquoteKeys = true

local args = {...}
local sleepTime = tonumber(args[1]) or 5

local summonInfoList = {
    -- { "minecraft:witch" },
    { "minecraft:creeper" },
    -- { "minecraft:zombie", { IsBaby = 1 } },
    -- { "minecraft:skeleton" },
    -- { "minecraft:chicken", { Passengers = { { id = "zombie", IsBaby = 1 } } } },
}

while true do
    local summonInfo = summonInfoList[math.random(1, #summonInfoList)]
    local z = 0 -- math.random(-1, 1)
    execCommand("summon", summonInfo[1], "~", "~-3", "~"..tostring(z), summonInfo[2])
    os.sleep(sleepTime)
end
