package.path = package.path..";./libraries/?.lua"

local TT = require "tt-core"
local mainLogger = TT.mainLogger
local Rules = require "rules"
local Logger = require "logger"
local BasicRules = require "basic_rules"
local ArgParser = require "arg-parser"
local parseSubCommand = ArgParser.parseSubCommand
local splitCommand = ArgParser.splitCommand
local TTBasic = require "tt-basic-rules"
local TTTree = require "tt-tree-rules"

Logger.addListener(Logger.fileWriterListener "/logs/tt.log")

mainLogger.addListener(Logger.printListener(Logger.Info))
mainLogger.addListener(Logger.loggerListener(Logger.getDefaultLogger()))

local function ruleThread()
    Rules.add(
        -- BasicRules.collectAroundMapRule,
        -- BasicRules.craftTorchRule,
        -- BasicRules.setTorchRule,
        BasicRules.refuelRule,
        -- BasicRules.goHomeRule,
        TTBasic.checkHomeRule,
        TTBasic.collectMapRule,
        TTTree.treeFarmingRule,
        TTTree.suckSaplingRule
    )
    Rules.evaluate()
end

local history = {}
local normalizedInputToCount = {}

local function trim(s)
    return s:match "^%s*(.-)%s*$"
end

---@param input string
local function normalize(input)
    local args = splitCommand(input)
    if not args then return trim(input:lower()) end
    return table.concat(args, " "):lower()
end

local function addHistory(input)
    local key = normalize(input)
    if normalizedInputToCount[key] then
        for i = #history, 1, -1 do
            local old = history[i]
            if normalize(old) == key then
                table.remove(history, i)
            end
        end
        normalizedInputToCount[key] = normalizedInputToCount[key] + 1
    else
        normalizedInputToCount[key] = 1
    end
    history[#history+1] = input
end
local sumCommands = {}

local function complete(prefix)
    return shell.complete(prefix)
end

local function readAndProcessCommand()
    local oldColor = term.getTextColor()
    term.setTextColor(colors.lightBlue)
    term.write("TT> ")
    term.setTextColor(oldColor)

    local input = read(nil, history, complete)
    addHistory(input)

    local arguments, error = splitCommand(input)
    if not arguments then return mainLogger.logError("error: ", error) end

    local sub, subArguments = parseSubCommand(arguments)
    if not sub then return end

    local subCommand = sumCommands[sub]
    if subCommand then return subCommand(subArguments) end

    shell.run(unpack(arguments))
end

local function inputThread()
    while true do
        readAndProcessCommand()
    end
end

parallel.waitForAll(ruleThread, inputThread)
