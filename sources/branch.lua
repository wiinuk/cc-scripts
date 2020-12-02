local refuel = require "refuel"
local Tex = require "turtle_extensions"
local Memoried = require "memoried"
local Mex = require "memoried_extensions"
local Logger = require "logger"
local Json = require "json"

local Bucket = "minecraft:bucket"
local FlowingWater = "minecraft:flowing_water"
local FlowingLava = "minecraft:flowing_lava"
local Lava = "minecraft:lava"
local LavaBucket = "minecraft:lava_bucket"
local Torch = "minecraft:torch"
local Water = "minecraft:water"
local WaterBucket = "minecraft:water_bucket"
local CobbleStone = "minecraft:cobblestone"

local settingsPath = ".settings/branch.json"
local logPath = "logs/branch.log"

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

---@param globalDirection number
local function refuelAndGo(globalDirection)
    refuel()
    if Memoried.getOperationAt(globalDirection).move() then
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

local settings = {
    totalBlockCount = 0,
    blockNameToCount = {}
}

local function loadSettings()
    local file, reason = io.open(settingsPath, "r")
    if not file then Logger.logWarning("The file", settingsPath, "could not be opened:", reason); return end
    local contents = file:read("*a")
    file:close()

    local ok, value = Json.parse(contents)
    if not ok or type(value) ~= "table" then Logger.logError("The file", settingsPath, "could not be parsed:", value); return end

    for k, v in pairs(value) do settings[k] = v end
    Logger.logInfo("Loaded:", settingsPath)
end

local function saveSettings()
    local json = Json.stringify(settings)

    local file, reason = io.open(settingsPath, "w")
    if not file then Logger.logError("The file", settingsPath, "could not be opened:", reason); return end
    local _, reason = file:write(json)
    file:close()

    if reason then Logger.logError("Failed to write to file ", settingsPath, "."); return end
    Logger.logInfo("Saved:", settingsPath)
end

local function updateBlockRarity(inspectData)
    local count = (settings.blockNameToCount[inspectData.name] or 0) + 1
    settings.blockNameToCount[inspectData.name] = count
    settings.totalBlockCount = settings.totalBlockCount + 1

    local rarity = (settings.blockNameToCount[inspectData.name] or 0) / settings.totalBlockCount
    Logger.logDebug(inspectData.name, count, "/", settings.totalBlockCount, "=", string.format("%0.2f", rarity * 100), "%")
    if 9 < math.random(1, 10) then saveSettings() end
end
local function dynamicBlockRarity(inspectData)
    updateBlockRarity(inspectData)

    if settings.totalBlockCount == 0 then return 0.5 end
    return (settings.blockNameToCount[inspectData.name] or 0) / settings.totalBlockCount
end

local ignoreBlockNameSet = {
    [Lava] = true,
    [Torch] = true,
    [Water] = true,
    [FlowingLava] = true,
    [FlowingWater] = true,
    [CobbleStone] = true,
}
local topDigDirections = {
    Memoried.Down,
    Memoried.Left,
    Memoried.Right,
}
local upDigDirections = {
    Memoried.Left,
    Memoried.Right,
    Memoried.Up,
}
local allDigDirections = {
    Memoried.Down,
    Memoried.Left,
    Memoried.Right,
    Memoried.Up,
    Memoried.Forward,
    Memoried.Back,
}

local function goTo(x, y, z)
    if Mex.goTo(x, y, z) then return true end

    local _, path = Mex.findNearMovablePath(x, y, z, true)
    if path then return Mex.goToGoal(100, path) end

    return false, "path not found"
end

local function digUntil(globalDirection)
    local function updateRarityAndDig(globalDirection)
        local ok, data = Memoried.getOperationAt(globalDirection).inspect()
        if ok then updateBlockRarity(data) end
        return Memoried.getOperationAt(globalDirection).dig()
    end
    local success = false
    while updateRarityAndDig(globalDirection) do success = true end
    return success
end

local function mineAroundAndReturn(rareBlockRate, digDirections, depth)
    if 10 < depth then return end

    local currentDirection = Memoried.toGlobalDirection(Memoried.Forward)

    local globalDirections = {}
    for i, d in ipairs(digDirections) do
        globalDirections[i] = Memoried.toGlobalDirection(d)
    end

    for _, d in ipairs(globalDirections) do
        local ok, data = Memoried.getOperationAt(d).inspect()
        if ok and not ignoreBlockNameSet[data.name] and dynamicBlockRarity(data) <= rareBlockRate then
            Logger.logInfo("rare block!!!", Json.stringify(data))

            local cx, cy, cz = Memoried.currentPosition()
            digUntil(d)
            Memoried.getOperationAt(d).move()
            mineAroundAndReturn(rareBlockRate, allDigDirections, (depth or 0) + 1)

            local ok, reason = goTo(cx, cy, cz)
            if not ok then
                Logger.logError("goTo failure:", reason)
                return error("goTo failure:", reason)
            end
        end
    end
    Memoried.getOperationAt(currentDirection).detect()
end

local args = {...}
if #args == 0 then
    print("Usage:")
    print("  branch <forward> [no-collect] [no-return]")
    print("")
    print("Options:")
    print("  forward     Distance to move forward.")
    print("  no-collect  Does not collect the ore around.")
    print("  no-return   It does not return to the starting position.")
    return
end

local length = tonumber(args[1])
local noCollect = false
local noReturn = false
for i = 2, #args do
    local argument = args[i]
    if argument == "no-collect" then noCollect = true
    elseif argument == "no-return" then noReturn = true
    else return error("Unexpected argument '"..argument.."'")
    end
end

local torchPlaceSpan = 7
local rareBlockRate = 0.1
Logger.addListener(Logger.printListener(Logger.Debug))
Logger.addListener(Logger.fileWriterListener(logPath))
loadSettings()

--- globalDirection
local mineDirection = Memoried.Forward

while forwardCount < length do

    -- アイテムが満杯なら終わり
    Tex.compactItems()
    if not Tex.findLastEmptySlot() then
        Logger.log("Mining was interrupted at ", forwardCount, "m because there were no empty slots.")
        break
    end

    if not noCollect then
        mineAroundAndReturn(rareBlockRate, topDigDirections, 0)
        if digUntil(Memoried.Up) then
            Memoried.getOperationAt(Memoried.Up).move()
            mineAroundAndReturn(rareBlockRate, upDigDirections, 0)
            Memoried.getOperationAt(Memoried.Down).move()
        end
    else
        digUntil(Memoried.Up)
        Memoried.getOperationAt(Memoried.Up).detect()
    end

    pumpDown()
    makeRoad()

    digUntil(mineDirection)
    refuelAndGo(mineDirection)

    if forwardCount % torchPlaceSpan == math.floor(torchPlaceSpan / 2) then
        placeTorch()
    end
end
digUntil(Memoried.Up)

saveSettings()

-- 帰る
if not noReturn then
    Memoried.getOperationAt(Memoried.Up).move()
    Memoried.getOperation(Memoried.Back).detect()
    while 0 < forwardCount do
        forwardCount = forwardCount - 1
        Memoried.getOperation(Memoried.Forward).move()
    end
    Memoried.getOperationAt(Memoried.Down).move()
    Memoried.getOperationAt(mineDirection).detect()
end
