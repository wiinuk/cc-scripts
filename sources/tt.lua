package.path = package.path..";./libraries/?.lua"

local TT = require "tt-core"
local mainLogger = TT.mainLogger
local Rules = require "rules"
local Logger = require "logger"
local BasicRules = require "basic_rules"
local TTBasic = require "tt-basic-rules"
local TTTree = require "tt-tree-rules"
local TTSorting = require "tt-sorting-rules"
local Input = require "input"

Logger.addListener(Logger.fileWriterListener "/logs/tt.log")
local ok, result = pcall(Logger.rednetListener, "left")
if ok then Logger.addListener(result) end

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
        TTTree.suckSaplingRule,

        TTSorting.checkSortedChestRule,
        TTSorting.transferItemToSortedChestRule
    )
    Rules.evaluate()
end

local function inputThread()
    while true do
        Input.readAndProcessCommand("TT> ", function(error)
            mainLogger.logError("error: ", error)
        end, {})
    end
end

parallel.waitForAll(ruleThread, inputThread)
