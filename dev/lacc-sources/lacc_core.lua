local Json = require 'json'
local commandName = "lacc"
local configPath = "dependencies.json"
local packageRootPath = "packages"
local lockPath = commandName.."/lock.json"
local logPath = commandName.."/log.log"


local function openLogFile()
    local logPath = shell.resolve(logPath)
    if fs.exists(logPath) then fs.delete(logPath) end
    local f, reason = io.open(logPath, "w+")
    if not f then
        print("can not opened log file", reason)
        return true
    end
    return f
end

local Output = 1
local Error = 2
local Warning = 3
local Info = 4
local Debug = 5
local levels = {"O","E","W","I","D"}

local logFile = nil
local function writeLog(level, ...)
    if not logFile then logFile = openLogFile() end
    if logFile == true then return end

    local args = {...}
    for i = 1, #args do args[i] = tostring(args[i]) end

    logFile:write(tostring(levels[level]))
    logFile:write("\t")
    logFile:write(table.concat(args, "\t"))
    logFile:write("\n")
    logFile:flush()
end

local outputLevel = Error
local function logCore(level, ...)
    if level <= outputLevel then print(...) end
    writeLog(level, ...)
end

local function log(...) logCore(Output, ...) end
local function logError(...) logCore(Error, ...) end
local function logWarning(...) logCore(Warning, ...) end
local function logInfo(...) logCore(Info, ...) end
local function logDebug(...) logCore(Debug, ...) end

---@param path string
local function readString(path)
    local f, reason = io.open(shell.resolve(path), "r")
    if not f then return nil, "Failed opening file '"..path.."' for reading: "..reason end

    local data = f:read("*a")
    f:close()
    return data
end

---@param path string
---@return boolean success
---@return any|string valueOrError
local function readJson(path)
    local contents, reason = readString(path)
    if contents == nil then return false, reason end
    return Json.parse(contents)
end

---@param path string
---@param contents string
local function writeString(path, contents)
    local f, reason = io.open(shell.resolve(path), "w+")
    if not f then return false, "Failed opening file '"..path.."' for writing: "..reason end
    local f2, reason = f:write(contents)
    if not f2 then
        f:close()
        return false, reason
    end
    f:close()
    return true
end

---@param path string
---@param value any
---@return boolean success
---@return string error
local function writeJson(path, value)
    local json, error = Json.stringify(value, { maxWidth = 0, indent = " ", space = " " })
    if json == nil then return false, error end
    return writeString(path, json)
end

---@param address string
---@param headers table|nil
---@overload fun(address: string): string|nil, string|nil
local function downloadString(address, headers)
    local r, reason = http.get(address, headers)
    if not r then return nil, "http get failed: '"..address.."', "..tostring(reason) end
    local contents = r:readAll()
    r:close()
    return contents
end
---@param headers table|nil
---@overload fun(address: string): boolean, any|string
local function downloadJson(address, headers)
    local result, reason = downloadString(address, headers)
    if result == nil then return false, reason end
    return Json.parse(result)
end

local function emptyConfig() return {} end

---@param arguments string[]
---@return string|nil loweredSubCommand
local function parseSubCommand(arguments)
    if #arguments < 1 then return nil end

    local subCommand = string.lower(arguments[1])
    local subArguments = {unpack(arguments)}
    table.remove(subArguments, 1)
    return subCommand, subArguments
end

return {
    log = log,
    logError = logError,
    logWarning = logWarning,
    logInfo = logInfo,
    logDebug = logDebug,

    readJson = readJson,
    writeString = writeString,
    writeJson = writeJson,
    downloadString = downloadString,
    downloadJson = downloadJson,

    commandName = commandName,
    configPath = configPath,
    packageRootPath = packageRootPath,
    lockPath = lockPath,

    emptyConfig = emptyConfig,

    parseSubCommand = parseSubCommand,
}
