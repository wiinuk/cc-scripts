local Ex = require "extensions"


---@class LogListener
---@field onMessage fun(self: LogListener, level: integer, message1: any, message2: any, messageN: any)
---@field dispose fun()

local Output = 1
local Error = 2
local Warning = 3
local Info = 4
local Debug = 5

local defaultLogListeners = {}

---@param listener LogListener
local function addListener(listener)
    local id = #defaultLogListeners+1
    defaultLogListeners[id] = listener
    return id
end

local function logCore(level, ...)
    for i = 1, #defaultLogListeners do
        defaultLogListeners[i]:onMessage(level, ...)
    end
end
local function log(...) logCore(Output, ...) end
local function logError(...) logCore(Error, ...) end
local function logInfo(...) logCore(Info, ...) end
local function logDebug(...) logCore(Debug, ...) end

local levels = {"O","E","W","I","D"}
-- local logPath = "logs/mine.log"
-- local logFile = nil
local function initLogFile(self)
    if fs.exists(self.logPath) then
        fs.delete(self.logPath)
    end
    self.logFile = io.open(self.logPath, "w+") or true
end
local function writeLog(self, level, ...)
    if not self.logFile then initLogFile(self) end
    local logFile = self.logFile
    if logFile == true then return end

    local args = {...}
    for i = 1, #args do args[i] = tostring(args[i]) end

    logFile:write(levels[level])
    logFile:write("\t")
    logFile:write(table.concat(args, "\t"))
    logFile:write("\n")
    logFile:flush()
end
local function closeFile(self)
    self.logFile = nil
    self.dispose = Ex.noop
    self.onMessage = Ex.noop
end
---@param logPath string
---@return LogListener
local function fileWriterListener(logPath)
    return {
        logPath = logPath,
        logFile = nil,
        onMessage = writeLog,
        dispose = closeFile,
    }
end

local function printWithColor(textColor, ...)
    local color = term.getTextColor()
    term.setTextColor(textColor)
    print(...)
    term.setTextColor(color)
end
local function printLog(self, level, ...)
    if level <= self.logLevel then
        if level == Error then
            printWithColor(colors.red)
        elseif level == Warning then
            printWithColor(colors.yellow)
        elseif level == Info then
            printWithColor(colors.lightBlue)
        elseif level == Debug then
            printWithColor(colors.gray)
        else
            print(...)
        end
    end
end
---@param logLevel integer|nil
---@return LogListener
local function printListener(logLevel)
    logLevel = logLevel or Error
    return {
        logLevel = logLevel,
        onMessage = printLog,
        dispose = Ex.noop,
    }
end

addListener(printListener(Output))

return {
    Output = Output,
    Error = Error,
    Warning = Warning,
    Info = Info,
    Debug = Debug,

    logCore = logCore,
    log = log,
    logError = logError,
    logInfo = logInfo,
    logDebug = logDebug,

    addListener = addListener,

    printListener = printListener,
    fileWriterListener = fileWriterListener,
}