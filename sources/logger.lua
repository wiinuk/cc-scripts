local Ex = require "extensions"
local pretty = require "pretty"


---@class LogListener
---@field onMessage fun(self: LogListener, level: integer, message1: any, message2: any, messageN: any)
---@field dispose fun()

---@class Logger
---@field name string
---@field logCore fun(level: integer, arg1: any, arg2: any, argN: any): nil
---@field log fun(arg1: any, arg2: any, argN: any): nil
---@field logError fun(arg1: any, arg2: any, argN: any): nil
---@field logWarning fun(arg1: any, arg2: any, argN: any): nil
---@field logInfo fun(arg1: any, arg2: any, argN: any): nil
---@field logDebug fun(arg1: any, arg2: any, argN: any): nil
---@field addListener fun(listener: LogListener): nil

local Output = 1
local Error = 2
local Warning = 3
local Info = 4
local Debug = 5

---@param name string|nil
local function create(name)
    ---@type Logger
    local logger = {
        name = name or "<anonymous>",
        ---@type LogListener[]
        _listeners = {}
    }
    ---@param listener LogListener
    function logger.addListener(listener)
        logger._listeners[#logger._listeners+1] = listener
    end
    local function logCore(level, ...)
        local ls = logger._listeners
        for i = 1, #ls do ls[i]:onMessage(level, ...) end
    end
    logger.logCore = logCore

    local Output = Output
    local Error = Error
    local Info = Info
    local Debug = Debug
    function logger.log(...) logCore(Output, ...) end
    function logger.logError(...) logCore(Error, ...) end
    function logger.logWarning(...) logCore(Warning, ...) end
    function logger.logInfo(...) logCore(Info, ...) end
    function logger.logDebug(...) logCore(Debug, ...) end

    return logger
end

local default = create("<DEFAULT_LOGGER>")
local function getDefaultLogger() return default end

---@class Terminal
---@field getTextColor fun(): number
---@field setTextColor fun(color: number): nil
---@field getLine any
---@field write fun(text: string): nil
--- Clears the screen by overwriting the whole display with blank spaces. The results are affected by the current background colour.
---@field clear fun(): nil

---@class TerminalLogListener : LogListener
---@field public logLevel integer
---@field public terminal Terminal

local function printVarArgTailWithSelf(self, write, arg1, ...)
    write(self, "\t")
    if type(arg1) == "string" then
        write(self, arg1)
    else
        write(self, pretty(arg1))
    end
    if select('#', ...) == 0 then return end
    printVarArgTailWithSelf(self, write, ...)
end
local function printVarArgHeadWithSelf(self, write, arg1, ...)
    if type(arg1) == "string" then
        write(self, arg1)
    else
        write(self, pretty(arg1))
    end
    if select('#', ...) == 0 then return end
    printVarArgTailWithSelf(self, write, ...)
end
local function printVarArgsWithSelf(self, write, ...)
    if select('#', ...) == 0 then return end
    printVarArgHeadWithSelf(self, write, ...)
end

local levels = {"O","E","W","I","D"}
local function initLogFile(self)
    if fs.exists(self._logPath) then
        fs.delete(self._logPath)
    end
    self._logFile = io.open(self._logPath, "w+") or true
end
local function regenerateLogFile(self)
    local size = fs.getSize(self._logPath)
    if fs.getFreeSpace(fs.getDrive(self._logPath)) <= size then
        self._logFile:close()
        self._logFile = nil
        fs.delete(self._logPath)

        initLogFile(self)
        if self._logFile and self._logFile ~= true then
            self._logFile:write("<<truncated. max size: ")
            self._logFile:write(tostring(size))
            self._logFile:write(" bytes>>\n")
            self._logFile:flush()
        end
    end
end
local function writeLog(self, level, ...)

    -- ドライブの空き領域チェック
    if self._logFile and 8 < math.random(1, 10) then
        regenerateLogFile(self)
    end

    -- ログファイルの存在チェック
    if self._logFile and 8 < math.random(1, 10) and not fs.exists(self._logPath) then
        self._logFile:close()
        self._logFile = nil
    end

    if not self._logFile then initLogFile(self) end
    local logFile = self._logFile
    if logFile == true then return end

    logFile:write(levels[level])
    logFile:write("\t")
    printVarArgsWithSelf(logFile, logFile.write, ...)
    logFile:write("\n")
    logFile:flush()
end
local function closeFile(self)
    self.logFile = nil
    self.dispose = Ex.noop
    self.onMessage = Ex.noop
end
---@param logFilePath string
---@return LogListener
local function fileWriterListener(logFilePath)
    return {
        _logPath = logFilePath,
        _logFile = nil,
        onMessage = writeLog,
        dispose = closeFile,
    }
end

local function printLog(self, level, ...)
    if level > self.logLevel then return end

    local oldColor = term.getTextColor()
    local color = oldColor
    if level == Error then color = colors.red
    elseif level == Warning then color = colors.yellow
    elseif level == Info then color = colors.lightBlue
    elseif level == Debug then color = colors.gray
    end
    term.setTextColor(color)
    print(...)
    term.setTextColor(oldColor)
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

---@param self TerminalLogListener
---@param level integer
local function writeTerminal(self, level, ...)
    if level > self.logLevel then return end

    local t = self.terminal
    local oldColor = t.getTextColor()
    local c = oldColor
    if level == Error then c = colors.red
    elseif level == Warning then c = colors.yellow
    elseif level == Info then c = colors.lightBlue
    elseif level == Debug then c = colors.gray
    end

    t.setTextColor(c)
    local oldTerminal = term.redirect(t)
    print(...)
    term.redirect(oldTerminal)
    t.setTextColor(oldColor)
end

---@param terminal Terminal
---@param logLevel integer|nil
---@return TerminalLogListener
local function terminalListener(terminal, logLevel)
    logLevel = logLevel or Error
    return {
        logLevel = logLevel,
        terminal = terminal,
        onMessage = writeTerminal,
        dispose = Ex.noop,
    }
end

local function writeLogger(self, level, ...)
    self._logger.logCore(level, ...)
end

---@param logger Logger
---@return LogListener
local function loggerListener(logger)
    return {
        _logger = logger,
        onMessage = writeLogger,
        dispose = Ex.noop,
    }
end

return {
    Output = Output,
    Error = Error,
    Warning = Warning,
    Info = Info,
    Debug = Debug,

    logCore = default.logCore,
    log = default.log,
    logError = default.logError,
    logInfo = default.logInfo,
    logDebug = default.logDebug,
    addListener = default.addListener,
    getDefaultLogger = getDefaultLogger,

    create = create,
    printListener = printListener,
    fileWriterListener = fileWriterListener,
    terminalListener = terminalListener,
    loggerListener = loggerListener,
}