package.path = package.path..";./libraries/?.lua"
local Tex = require "turtle_extensions"
local findItem = Tex.findItemSlot
local selectItem = Tex.selectItem
local eachItem = Tex.eachItem
local Names = require "minecraft-names"

local Chest = Names.Chest
local Coal = Names.Coal

local w = io.open("./logs/farm.log", "w+")

local plantNames = {
    Names.Wheat,
    Names.Carrots,
    Names.Potatoes,
}
local seedNames = {
    Names.WheatSeeds,
    Names.Carrot,
    Names.Potato,
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

local slipMoveCount = 0
local maxSlipCount = 10
local minSleepClock = 8
local sleepClock = minSleepClock

local function isDigAtDown()
    local ok, item = turtle.inspectDown()
    return ok and isDig(item)
end
local function dig()
    if not findItem(isSeed) then
        error("requires: "..table.concat(seedNames, " or "))
    end

    if isDigAtDown() then
        Tex.compactItems()
        turtle.digDown()
        selectItem(isSeed)
        turtle.placeDown()

        slipMoveCount = 0
        sleepClock = minSleepClock
    else
        if maxSlipCount < slipMoveCount then
            print("sleeping", sleepClock, "s")
            os.sleep(sleepClock)
            sleepClock = sleepClock * 2
            slipMoveCount = 0
        end
    end
end

local function isPlantAtDown()
    local ok, item = turtle.inspectDown()
    return ok and isPlant(item)
end

local function isEmptyFuel()
    local level = turtle.getFuelLevel()
    return level ~= "unlimited" and level <= 0
end
local function refuel()
    eachItem(function (item, index)
        turtle.select(index)
        turtle.refuel(1)
        return item
    end)
end
local function fuelCheck()
    if isEmptyFuel() then
        refuel()
        if isEmptyFuel() then
            print("empty fuel")
            while isEmptyFuel() do
                local turn = turtle.turnLeft
                if math.random(1,2) == 1 then turn = turtle.turnRight end
                for _ = 1, 4 do turn() end
                refuel()
            end
            print("replenished", turtle.getFuelLevel(), "fuels")
        end
    end
end

local down = {
    drop = turtle.dropDown,
    suck = turtle.suckDown,
}
local forward = {
    drop = turtle.drop,
    suck = turtle.suck,
}
local function getNeighborChestOps()
    local ok, item = turtle.inspectDown()
    if ok and item.name == Chest then return down end
    local ok, item = turtle.inspect()
    if ok and item.name == Chest then return forward end
    return
end
local function craftAndPutChest()

    -- チェストがあるか
    local chestOp = getNeighborChestOps()
    if not chestOp then return end

    -- 小麦のスロットを検索
    local slot = findItem(function (i) return i.name == Names.Wheat end)
    if not slot then return end
    if turtle.getItemCount(slot) < 3 then return end

    -- 小麦の他のアイテムはチェストに入れる
    local drop = chestOp.drop
    eachItem(function (_, s)
        if s ~= slot then
            turtle.select(s)
            drop()
        end
    end)

    -- 小麦をスロットに均等に配置
    local wheatCount = turtle.getItemCount(slot)
    local breadCount = math.modf(wheatCount / 3)
    turtle.select(slot)
    turtle.transferTo(1, breadCount)
    turtle.select(slot)
    turtle.transferTo(2, breadCount)
    turtle.select(slot)
    turtle.transferTo(3, wheatCount - breadCount * 2)

    -- クラフト
    turtle.craft()

    -- チェストから種を含むアイテムを全てとる
    while chestOp.suck() do end

    -- 種以外をチェストに返す
    eachItem(function (i, s)
        if not isSeed(i) or not i.name == Coal then
            turtle.select(s)
            chestOp.drop()
        end
    end)
end

local function forwardOnPlant()
    if not turtle.forward() then
        craftAndPutChest()
        fuelCheck()
        return false
    end
    if not isPlantAtDown() then
        craftAndPutChest()
        if not turtle.back() then fuelCheck() end
        return false
    else
        if not isDigAtDown() then
            print("slip")
            slipMoveCount = slipMoveCount + 1
        end
    end
    return true
end

local function digLine()
    while forwardOnPlant() do
        dig()
    end
end

local function main()
    print("starting")
    local turn = turtle.turnLeft
    local turnInv = turtle.turnRight
    while true do
        digLine()
        turn()

        if not forwardOnPlant() then
            turn, turnInv = turnInv, turn
            turn()
            turn()
            if not forwardOnPlant() then
                turn()
            end
        else
            turn()
            turn, turnInv = turnInv, turn
        end
    end

    print("end")
end

local ok, reason = pcall(main)
if not ok then
    w:write(tostring(reason))
    w:flush()
    error(reason)
end
