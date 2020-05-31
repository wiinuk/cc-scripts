local Core = require "lacc_core"
local Gist = require "lacc_gist"
local Github = require "lacc_github"

local commandName = "lacc"


local function showUsage()
    print "Usages:"
    print(commandName.." init", "create an config file")
    print(commandName.." install", "setup dependencies")
    print(commandName.." github", "manipulate GitHub references")
    print(commandName.." gist", "manipulate Gist references")
end

---@param arguments string[]
local function init(arguments)
    if 0 < #arguments then
        io.stderr:write("unrecognized argument: '"..arguments[1].."'")
        return
    end
    if fs.exists(shell.resolve(Core.configPath)) then
        print(commandName.." is already initialized in "..shell.resolve("."))
        return
    end

    local ok, error = Core.writeJson(Core.configPath, Core.emptyConfig())
    if not ok then io.stderr:write(error.."\n") return end

    print("created '"..Core.configPath.."'")
end

---@param arguments string[]
local function install(arguments)
    if 0 < #arguments then
        io.stderr:write("unrecognized argument: '"..arguments[1].."'")
        return
    end
    local ok, result = Core.readJson(Core.configPath)
    if not ok then
        io.stderr:write("configure file not found. "..result.."\n")
        return
    end

    if type(result) ~= "table" then return end

    -- `[...]`
    for _, v in ipairs(result) do
        if v[1] == "gist" then
            return Gist.installGist(v)

        elseif v[1] == "github" then
            return Github.installGithub(v)
        end
    end
end

---@param arguments string[]
local function processArguments(arguments)
    local subCommand, subArguments = Core.parseSubCommand(arguments)
    if subCommand == nil then return showUsage() end

    if subCommand == "install" then return install(subArguments)
    elseif subCommand == "init" then return init(subArguments)
    elseif subCommand == "github" then
        return Github.processGithubCommand(subArguments)

    elseif subCommand == "gist" then
        return Gist.processGistCommand(subArguments)

    else return showUsage() end
end

processArguments {...}