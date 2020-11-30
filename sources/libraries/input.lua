local ArgParser = require "arg-parser"
local parseSubCommand = ArgParser.parseSubCommand
local splitCommand = ArgParser.splitCommand

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

local function complete(prefix)
    return shell.complete(prefix)
end

---@param prefix string
---@param onParseError fun(error: string): nil
---@param subCommands table<string, fun(subArguments: string[]): nil>
local function readAndProcessCommand(prefix, onParseError, subCommands)
    local oldColor = term.getTextColor()
    term.setTextColor(colors.lightBlue)
    term.write(prefix or "TF> ")
    term.setTextColor(oldColor)

    local input = read(nil, history, complete)
    addHistory(input)

    local arguments, error = splitCommand(input)
    if not arguments then return onParseError and onParseError(error) end

    local sub, subArguments = parseSubCommand(arguments)
    if not sub then return end

    local subCommand = subCommands and subCommands[sub]
    if subCommand then return subCommand(subArguments) end

    shell.run(unpack(arguments))
end

return {
    readAndProcessCommand = readAndProcessCommand
}
