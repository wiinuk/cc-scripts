
local function isEmptyFuel()
    local level = turtle.getFuelLevel()
    return level ~= "unlimited" and level <= 0
end

local function emptyFuelMessage()
    local turn = turtle.turnLeft
    if math.random(1, 3) == 1 then
        turn = turtle.turnRight
    end
    turn()
    turn()
    turn()
    turn()
end

--- `{ ["minecraft:coal"] = 320, ["minecraft:stone"] = 0 ... }`
local itemNameToFuelLevel = {}

local function refuel()
    local slots = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            local name = item.name
            local level = itemNameToFuelLevel[name]
            if level then
                if 0 < level then
                    slots[#slots+1] = slot
                end
            else
                turtle.select(slot)
                local oldLevel = turtle.getFuelLevel()
                if turtle.refuel(1) then
                    local newLevel = turtle.getFuelLevel()
                    itemNameToFuelLevel[name] =  newLevel - oldLevel
                    return true
                else
                    itemNameToFuelLevel[name] = 0
                end
            end
        end
    end
    if #slots then return false end

    turtle.select(math.random(1, #slots))
    turtle.refuel(1)
    return true
end

return function()
    if isEmptyFuel() then
        refuel()
        if isEmptyFuel() then
            print("need fuel")
            while isEmptyFuel() do
                refuel()
                emptyFuelMessage()
            end
            print("tasty!")
        end
    end
end