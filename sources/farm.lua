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
    end
    error("slot not found")
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

local function dig()
    local ok, item = turtle.inspectDown()
    if ok and isDig(item) then turtle.digDown() end
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

local function isSeed(i) return contains(seedNames, i) end

while downIsPlant() do
    if not findItem(isSeed) then
        error("requires: ", table.concat(seedNames, " or "))
    end
    dig()
    selectItem(isSeed)
    turtle.placeDown()
    turtle.forward()
end

print("end")
