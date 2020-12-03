package.path = package.path..";./libraries/?.lua"
local Logger = require "logger"
local Memoried = require "memoried"
local Mex = require "memoried_extensions"
local Names = require "minecraft-names"


local mainLogger = Logger.create "main-logger"
local Leaves = Names.Leaves

local function goTo(maxRetryCount, x, y, z, isMovable, disableDig, disableAttack)
    local complete, path = Mex.findPath(x, y, z, isMovable)
    if not complete then return false, "path not found" end
    local ok, reason = Mex.goToGoal(maxRetryCount, path, disableDig, disableAttack)
    if not ok then return false, reason end
    return true
end

local function isHomeChecked()
    return Memoried.ttHome
end

local function newDefaultPersistentMemory()
    return {
        startNodeAdded = false,
        openNodes = {},
        closeNodes = {},
        colorToLocations = {},
    }
end

-- local memoryPath = "/settings/tt.json"
local function loadOrCreatePersistentMemory()
    return newDefaultPersistentMemory()

    -- if not fs.exists(memoryPath) then
    --     Logger.logInfo("new creating memory")
    --     return newDefaultPersistentMemory()
    -- end

    -- local file = io.open(memoryPath, "r+")
    -- local contents = file:read("*a")
    -- file:close()

    -- local ok, result = Json.parse(contents)
    -- if not ok then return error(result) end

    -- Logger.logInfo("loading memory from", memoryPath)
    -- return result
end

local persistentMemory = loadOrCreatePersistentMemory()


local function savePersistentMemory()
    -- local json, reason = Json.stringify(persistentMemory, { space = " ", indent = "  ", maxWidth = 0 })
    -- if not json then return Logger.logError("memory stringify error", reason) end

    -- local file = io.open(memoryPath, "w+")
    -- file:write(json)
    -- file:close()

    -- Logger.logInfo("memory saved to", memoryPath)
end

local function isMovable(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    return location and (location.move == true or location.detect == false or location.inspect == false)
end

local function disableDig(direction)
    local ok, info = Memoried.getOperationAt(direction).inspect()
    return not (ok and info.name == Leaves)
end

return {
    mainLogger = mainLogger,
    goTo = goTo,
    isHomeChecked = isHomeChecked,
    persistentMemory = persistentMemory,
    savePersistentMemory = savePersistentMemory,
    isMovable = isMovable,
    disableDig = disableDig,
}
