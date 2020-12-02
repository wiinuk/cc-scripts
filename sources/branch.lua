local refuel = require "refuel"
local Tex = require "turtle_extensions"
local Memoried = require "memoried"

local Bucket = "minecraft:bucket"
local FlowingWater = "minecraft:flowing_water"
local FlowingLava = "minecraft:flowing_lava"
local Lava = "minecraft:lava"
local LavaBucket = "minecraft:lava_bucket"
local Torch = "minecraft:torch"
local Water = "minecraft:water"
local WaterBucket = "minecraft:water_bucket"


local function findItemSlotByName(name)
    return Tex.findItemSlot(function (item) return item.name == name end)
end

local function select(slot)
    if turtle.getSelectedSlot() ~= slot then return turtle.select(slot) end
    return true
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

local function isRoadBlock(item)
    return item.name ~= Torch and not string.find(item.name, "bucket")
end

local function selectRoadBlock()
    if Tex.selectItem(isRoadBlock) then return end
    selectEmptySlot()
end

local function blockIsLava(info)
    return info and info.name == Lava or info.name == FlowingLava
end
local function downIsLava()
    local ok, info = Memoried.getOperation(Memoried.Down).inspect()
    return ok and blockIsLava(info)
end
local function upIsLava()
    local ok, info = Memoried.getOperation(Memoried.Up).inspect()
    return ok and blockIsLava(info)
end

local function makeRoad()
    if downIsLava() then
        local slot = findItemSlotByName(WaterBucket)
        if slot then
            Memoried.getOperation(Memoried.Up).move()
            turtle.select(slot)
            Memoried.getOperation(Memoried.Down).place()
            os.sleep(0.5)
            Memoried.getOperation(Memoried.Down).place()
            Memoried.getOperation(Memoried.Down).move()
        end
    end
    selectRoadBlock()
    Memoried.getOperation(Memoried.Down).place()

    if upIsLava() then
        Memoried.getOperation(Memoried.Up).move()
        selectRoadBlock()
        Memoried.getOperation(Memoried.Up).place()
        Memoried.getOperation(Memoried.Down).move()
    end
end


local forwardCount = 0
local function refuelAndGoForward()
    refuel()
    if Memoried.getOperation(Memoried.Forward).move() then
        forwardCount = forwardCount + 1
    end
end

local function pumpToBucket(bucketName, liquidName, flowingLiquidName)
    local bucketSlot = findItemSlotByName(Bucket)
    if bucketSlot and not findItemSlotByName(bucketName) then
        local ok, info = Memoried.getOperation(Memoried.Down).inspect()
        if ok then
            if info.name == liquidName or (info.name == flowingLiquidName and info.state.level == 0) then
                turtle.select(bucketSlot)
                Memoried.getOperation(Memoried.Down).place()
            end
        end
    end
end

local function pumpDown()
    pumpToBucket(WaterBucket, Water, FlowingWater)
    pumpToBucket(LavaBucket, Lava, FlowingLava)
end

local function placeTorch()
    if not Tex.selectItem(function (item) return item.name == Torch end) then return end
    Memoried.getOperation(Memoried.Back).place()
    Memoried.getOperation(Memoried.Back).detect()
end

local torchPlaceSpan = 7
local length = tonumber(({...})[1])
while forwardCount < length do
    Memoried.getOperation(Memoried.Up).dig()

    pumpDown()
    makeRoad()

    Memoried.getOperation(Memoried.Forward).dig()
    refuelAndGoForward()

    if forwardCount % torchPlaceSpan == math.floor(torchPlaceSpan / 2) then
        placeTorch()
    end
end
Memoried.getOperation(Memoried.Up).dig()
