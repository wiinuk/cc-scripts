
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

---@class RefuelOptions
---@field public isFuel fun(item: ItemDetail): boolean

---@param options RefuelOptions|nil
local function refuel(options)
    local isFuel = (options and options.isFuel) or nil

    local slotAndNames = nil
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and (not isFuel or isFuel(item)) then
            local name = item.name
            local level = itemNameToFuelLevel[name]
            if level then
                if 0 < level then
                    slotAndNames = slotAndNames or {}
                    slotAndNames[#slotAndNames+1] = { slot = slot, name = name }
                end
            else
                turtle.select(slot)
                local oldLevel = turtle.getFuelLevel()
                if turtle.refuel(1) then
                    local newLevel = turtle.getFuelLevel()
                    itemNameToFuelLevel[name] = newLevel - oldLevel
                    return true, name, 1
                else
                    itemNameToFuelLevel[name] = 0
                end
            end
        end
    end
    if not slotAndNames or #slotAndNames == 0 then return false end

    -- 燃料レベルが低いアイテムを優先して消費する
    table.sort(slotAndNames, function(l, r)
        return itemNameToFuelLevel[l.name] < itemNameToFuelLevel[r.name]
    end)
    local slotAndName = slotAndNames[1]
    turtle.select(slotAndName.slot)
    return turtle.refuel(1), slotAndName.name, 1
end

return function(options)
    local _, name, count
    if isEmptyFuel() then
        _, name, count = refuel(options)
        if isEmptyFuel() then
            print("need fuel")
            while isEmptyFuel() do
                _, name, count = refuel(options)
                emptyFuelMessage()
            end
            print("tasty!")
        end
    end
    return name, count
end