local Bucket = "minecraft:bucket"
local FlowingWater = "minecraft:flowing_water"
local FlowingLava = "minecraft:flowing_lava"
local Lava = "minecraft:lava"
local LavaBucket = "minecraft:lava_bucket"
local Torch = "minecraft:torch"
local Water = "minecraft:water"
local WaterBucket = "minecraft:water_bucket"


local function findItemSlot(predicate)
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and predicate(item, slot) then return slot end
    end
    return false, "item not found"
end
local function findItemSlotByName(name)
    return findItemSlot(function (item) return item.name == name end)
end

local function select(slot)
    if turtle.getSelectedSlot() ~= slot then return turtle.select(slot) end
    return true
end

local function selectItem(predicate)
    return findItemSlot(function(item, slot)
        if predicate(item) then return select(slot) end
        return false
    end)
end

local function selectEmptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) <= 0 then
            select(slot)
            return true
        end
    end
    return false, "empty slot not found"
end

local function selectNoTorch()
    if selectItem(function (item) return item.name ~= Torch end) then return end
    selectEmptySlot()
end

local function downIsLava()
    local ok, info = turtle.inspectDown()
    return ok and info.name == Lava or info.name == FlowingLava
end

local function makeRoad()
    if downIsLava() then
        local slot = findItemSlotByName(WaterBucket)
        if slot then
            turtle.up()
            turtle.select(slot)
            turtle.placeDown()
            turtle.placeDown()
            turtle.down()
            return
        end
    end
    selectNoTorch()
    turtle.placeDown()
end

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

local function forwardOrRefuel()
    if isEmptyFuel() then
        refuel()
        if isEmptyFuel() then
            print("need fuel")
            while isEmptyFuel() do
                refuel()
                emptyFuelMessage()
                os.sleep(math.random() * 1)
            end
            print("yummy!")
        end
    end
    turtle.forward()
end

local function pumpToBucket(bucketName, liquidName, flowingLiquidName)
    local bucketSlot = findItemSlotByName(Bucket)
    if bucketSlot and not findItemSlotByName(bucketName) then
        local ok, info = turtle.inspectDown()
        if ok then
            if info.name == liquidName or (info.name == flowingLiquidName and info.state.level == 0) then
                turtle.select(bucketSlot)
                turtle.placeDown()
            end
        end
    end
end

local function pumpDown()
    pumpToBucket(WaterBucket, Water, FlowingWater)
    pumpToBucket(LavaBucket, Lava, FlowingLava)
end

local function placeTorch()
    if selectItem(function (item) return item.name == Torch end) then
        turtle.placeUp()
    end
end

for i in ({...})[1] do
    turtle.digUp()

    pumpDown()
    makeRoad()
    if i % 6 == 0 then placeTorch() end

    turtle.dig()
    forwardOrRefuel()
end