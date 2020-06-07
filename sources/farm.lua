local w = io.open("./logs/farm.log", "w+")

local function findItem(predicate)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and predicate(item) then return i end
    end
    return false
end
local function selectItem(predicate)
    local slot = findItem(predicate)
    if slot then
        local ok, reason = turtle.select(slot)
        if not ok then error(reason) end
    else
        error("item not found:"..debug.traceback())
    end
end

local seedNames = {
    "minecraft:carrot",
    "minecraft:wheat_seeds",
}
local plantNames = {
    "minecraft:wheat",
    "minecraft:carrots",
}
local function exists(array, predicate)
    for _, v in ipairs(array) do
        if predicate(v) then return true end
    end
    return false
end
local function contains(array, target)
    return exists(array, function (x) return x == target end)
end

local function isPlant(item)
    return contains(plantNames, item.name)
end

local function isDig(item)
    return isPlant(item) and 7 <= item.state.age
end

local function isSeed(item)
    return contains(seedNames, item.name)
end

local function dig()
    if not findItem(isSeed) then
        error("requires: "..table.concat(seedNames, " or "))
    end
    local ok, item = turtle.inspectDown()
    if ok and isDig(item) then
        turtle.digDown()
        selectItem(isSeed)
        turtle.placeDown()
    end
end

local function isFarm()
    local ok, item = turtle.inspectDown()
    if ok and isPlant(item) then return true end

    if not ok then
        if not findItem(function (i) return i.name:match("minecraft:[%w_]*hoe") end)
        then
            error("requires: hoe")
        end

        turtle.down()
        local ok, item = turtle.inspectDown()
        if ok and item.name == "minecraft:dirt" then
            turtle.up()
            turtle.equipRight()
            return
        end
    end
end

local function downIsPlant()
    local ok, item = turtle.inspectDown()
    return ok and isPlant(item)
end

local function fuelCheck()
    local level = turtle.getFuelLevel()
    if level ~= "unlimited" and level <= 0 then
        error("empty fuel")
    end
end

local function digLine()
    while true do
        if not downIsPlant() then
            print("down is not plant")
            if not turtle.back() then fuelCheck() end
            return
        end
        dig()
        if not turtle.forward() then
            fuelCheck()
            print("move to forward failed")
            return
        end
    end
end

local function main()
    print("starting")
    local isLeft = true
    while true do
        digLine()
        if isLeft then
            turtle.turnLeft()
        else
            turtle.turnRight()
        end

        if not turtle.forward() then
            fuelCheck()
            if isLeft then
                turtle.turnLeft()
            else
                turtle.turnRight()
            end
        else
            if isLeft then
                turtle.turnLeft()
            else
                turtle.turnRight()
            end
        end
        isLeft = not isLeft
    end

    print("end")
end

local ok, reason = pcall(main)
if not ok then
    w:write(tostring(reason))
    w:flush()
    error(reason)
end
