local Rules = require "rules"
local Mine = require "mine"
local Logger = require "logger"
local ArgP = require "arg-parser"

---@class Window : Terminal
---@field public getCursorPos fun(): number, number
---@field public reposition fun(x: number, y: number, width: number|nil, height: number|nil): nil
---@field public setBackgroundColor fun(color_code: number): nil

local t = term.current()
local tw, th = t.getSize()
local tx, ty = t.getPosition()

---@type Window
local logWindow = window.create(term.current(), tx + tw * 0.5, ty, tw * 0.5, th, false)
logWindow.setBackgroundColor(colors.lightBlue)
logWindow.clear()

Logger.addListener(Logger.fileWriterListener("/logs/main.log"))
Logger.addListener(Logger.terminalListener(logWindow, Logger.Info))

local mainLogger = Logger.create("main")
mainLogger.addListener(Logger.printListener(Logger.Error))
mainLogger.addListener(Logger.loggerListener(Logger.getDefaultLogger()))

local function ruleThread()
    Rules.evaluate()
end

---@return string|nil loweredSubCommand
local function parseSubCommand(arguments)
    if #arguments < 1 then return nil end

    local subCommand = string.lower(arguments[1])
    local subArguments = {unpack(arguments)}
    table.remove(subArguments, 1)
    return subCommand, subArguments
end

local function logCommand(arguments)
    local sub, subArgs = parseSubCommand(arguments)
    if not sub then
        mainLogger.logError("unrecognized command", arguments[1])
        return
    end
    if 0 < #subArgs then
        mainLogger.logError("unrecognized parameter", subArgs[1])
        return
    end

    if sub == "show" then
        logWindow.setVisible(true)
    elseif sub == "hide" then
        logWindow.setVisible(false)
    else
        mainLogger.logError("unrecognized command", sub)
    end
end

---@type table<string, fun(arguments: string[]): any>
local commands = {
    mine = Mine.miningCommand,
    log = logCommand,
}
local function readAndProcessCommand()
    local arguments, error = ArgP.splitCommand(read())
    if not arguments then return mainLogger.logError("error: ", error) end

    local sub, arguments = parseSubCommand(arguments)
    if not sub then return end

    local command = commands[sub]
    if not command then return mainLogger.logError("unrecognized command", sub) end

    command(arguments)
end

local function inputThread()
    while true do
        readAndProcessCommand()
    end
end

parallel.waitForAll(ruleThread, inputThread)
