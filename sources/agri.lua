local ArgP = require "arg-parser"
local Logger = require "logger"
local Memoried = require "memoried"
local M = require "memoried_extensions"
local globalDirectionToPosition = M.globalDirectionToPosition
local Rules = require "rules"
local BasicRules = require "basic_rules"
local Completion = require "text_complete"
local choice = Completion.choice
local sequence = Completion.sequence
local text = Completion.text
local repeat0 = Completion.repeat0
local Ex = require "extensions"
local appendArray = Ex.appendArray
local containsArray = Ex.containsArray


local mainLogger = Logger.create "main logger"

local Down = Memoried.Down
local DisableDig = true
local DisableAttack = true
local EnableNoMovableGoal = true
local StoneButton = "minecraft:stone_button"

local plantNames = {
    "minecraft:wheat",
    "minecraft:carrots",
    "minecraft:potatoes",
}
local seedNames = {
    "minecraft:wheat_seeds",
    "minecraft:carrot",
    "minecraft:potato",
}
local function inspectIsFarm(info)
    return info and (containsArray(plantNames, info.name) or info.name == StoneButton)
end
local function inspectDownIsFarm()
    local ok, info = Memoried.getOperationAt(Down).inspect()
    return ok and inspectIsFarm(info)
end

local function isFarmInMemory(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    return location and location.inspect and inspectIsFarm(location.inspect)
end

local function hasFarmConfirmation(x, y, z)
    local location = Memoried.getLocation(x, y, z)
    return location and location.inspect ~= nil
end

local function findNearNoFarmConfirmationPosition(fx, fy, fz)
    -- 基準の農場の周りに、農場判定が終わっていない場所があるか確認する
    for d = 1, 6 do
        local nx, ny, nz = M.directionToNormal(d)
        local tx, ty, tz = fx + nx, fy + ny, fz + nz
        if not hasFarmConfirmation(tx, ty, tz) then
            local cx, cy, cz = Memoried.currentPosition()
            return { cx, cy, cz, tx, ty+1, tz}, Down
        end
    end
end

local collectFarmRule = {
    name = "farming: collect farmland",
    when = function()
        local request = Memoried.getRequest "farming"
        if not request then
            Logger.logDebug("request not found")
            return false
        end

        -- 最後に探索した農場の位置を取得
        if not request.lastFarmX then

            -- 無かったので現在の下が農場か判定
            if not inspectDownIsFarm() then return false end

            -- 現在の下を農場とする
            request.lastFarmX, request.lastFarmY, request.lastFarmZ =
                globalDirectionToPosition(Down)
        end
        local fx = request.lastFarmX
        local fy = request.lastFarmY
        local fz = request.lastFarmZ

        -- 農場か未判定の場所を探す
        local path, direction = findNearNoFarmConfirmationPosition(fx, fy, fz)
        if path then return 1, path, direction end
    end,
    action = function(self, path, direction)
        local ok, reason = M.goToGoal(5, path, DisableDig, DisableAttack)
        if not ok then return Logger.logError(self.name, reason) end

        local _, info = Memoried.getOperationAt(direction).inspect()
        if inspectIsFarm(info) then
            local request = Memoried.getRequest "farming"
            local fx, fy, fz = globalDirectionToPosition(direction)
            mainLogger.logInfo("registered:", fx, fy, fz, "is farm")
            request.lastFarmX = fx
            request.lastFarmY = fy
            request.lastFarmZ = fz
        else
            Logger.logDebug("not farm")
        end
    end,
}

local function workerThread()
    Rules.add(
        collectFarmRule,

        BasicRules.collectAroundMapRule,
        BasicRules.craftTorchRule,
        -- BasicRules.setTorchRule,
        BasicRules.refuelRule,
        BasicRules.goHomeRule
    )
    return Rules.evaluate()
end

local function farmingCommand()
    local ok, reason = Memoried.addRequest { name = "farming" }
    if not ok then
        mainLogger.logError(reason)
    end
end

local space = text " "
local trivias0 = repeat0(space)
local function token(s) return sequence(trivias0, text(s)) end
local function param(s) return sequence(space, token(s)) end
local internalCommands = {
    farming = {
        grammar = text "",
        process = farmingCommand,
    },
    goodby = {
        grammar = choice(param "see", param "you"),
        process = function (...) print(...) end,
    }
}
local function findArrayIndex(array, item)
    for i = 1, #array do
        if array[i] == item then return i end
    end
    return
end

local function commendsToComplete(commands)
    local cs = {}
    for k, v in pairs(commands) do
        cs[#cs+1] = sequence(token(k), v.grammar)
    end
    return choice(unpack(cs))
end

local inputToCount = {}
local inputSet = {}
local function addHistory(input)
    if input == "" then return end

    if inputToCount[input] then
        inputToCount[input] = inputToCount[input] + 1
        local i = findArrayIndex(inputSet, input)
        table.remove(inputSet, i)
    else
        inputToCount[input] = 1
    end
    inputSet[#inputSet+1] = input
end
local function getHistory()
    return inputSet
end

local internalCommandsComplete = commendsToComplete(internalCommands)
local function complete(completion, prefix)
    if #prefix == 0 then return nil end

    local ok, _, cs, r = completion(prefix)
    if not ok or (r and 0 < #r) then return nil end
    return cs
end
local function autoComplete(prefix)
    local xs1 = complete(internalCommandsComplete, prefix)
    local xs2 = shell.complete(prefix)
    local x = appendArray(xs1, xs2)
    return x
end
local function readAndProcessCommand()
    term.write("$ ")
    local input = read(nil, getHistory(), autoComplete)
    addHistory(input)
    local arguments, error = ArgP.splitCommand(input)
    if not arguments then return mainLogger.logError("error: ", error) end

    local sub, subArguments = ArgP.parseSubCommand(arguments)
    if not sub then return end

    local command = internalCommands[sub]
    if command then return command.process(subArguments) end

    local ok, reason = shell.run(unpack(arguments))
    if not ok then
        mainLogger.logError(reason)
    end
end

local function uiThread()
    while true do
        readAndProcessCommand()
    end
end

Logger.addListener(Logger.fileWriterListener "/logs/sugar_corn.log")
mainLogger.addListener(Logger.loggerListener(Logger.getDefaultLogger()))
mainLogger.addListener(Logger.printListener(Logger.Info))

parallel.waitForAll(workerThread, uiThread)
