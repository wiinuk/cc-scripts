local Core = require "lacc_core"

---@param id string gist id.
local function downloadGist(id)
    local ok, gist = Core.downloadJson("https://api.github.com/gists/"..id)
    if not ok then return false, gist end

    local gistRootPath = fs.combine(fs.combine(Core.packageRootPath, "gist"), id)
    fs.delete(shell.resolve(gistRootPath))
    if fs.exists(shell.resolve(gistRootPath)) then
        return false, "Failed delete directory '"..gistRootPath.."'"
    end

    for _, f in pairs(gist.files) do
        local filePath = fs.combine(gistRootPath, f.filename)
        local ok, reason = Core.writeString(filePath, f.content)
        if not ok then return false, reason end

        print("gist: "..id.." '"..f.filename.."' => '"..shell.resolve(filePath).."'")
    end
    return true
end

---@param arguments string[]
local function add(arguments)
    if #arguments < 1 then
        io.stderr:write("requires gist id. e.g. `"..Core.commandName.." gist add <gist_id>`\n")
        return
    end
    if 1 < #arguments then
        io.stderr:write("unrecognised argument: `"..arguments[2].."e.g. `"..Core.commandName.." gist add <gist_id>`\n")
        return
    end

    local id = arguments[1]

    local ok, result = Core.readJson(Core.configPath)
    if not ok then
        io.stderr:write("configure file not found. "..result.."\n")
        return
    end

    -- TODO:
    if type(result) ~= "table" then result = Core.emptyConfig() end

    for _, value in pairs(result) do
        if
            type(value) == "table" and
            string.lower(tostring(value[1])) == "gist" and
            string.lower(tostring(value[2])) == id
        then
            print(Core.configPath.." contains 'gist "..id.."' already.")
            return
        end
    end

    result[#result+1] = {"gist", id}
    local ok, error = Core.writeJson(Core.configPath, result)
    if not ok then io.stderr:write(error) end

    local ok, reason = downloadGist(id)
    if not ok then io.stderr:write(reason) end
    return
end

local function showGistUsage()
    print("Usage:")
    print(Core.commandName.." gist <subcommand> <options>")
    print("List of <subcommand>:")
    print("add <id>", "add a new dependency from gist")
end

---@param arguments string[]
local function processCommand(arguments)
    local subCommand, subArguments = Core.parseSubCommand(arguments)
    if subCommand == nil then
        io.stderr:write("missing subcommand\n")
        return showGistUsage()
    end

    if subCommand == "add" then return Core.gistAdd(subArguments)
    else
        io.stderr:write("unrecognized subcommand '"..subCommand.."'\n")
        return showGistUsage()
    end
end

---@param v string[]
local function install(v)
    if #v ~= 2 or type(v[2]) ~= "string" then
        io.stderr:write('invalid format in "'..Core.configPath..'", e.g. `["gist", "<gist_id>"]`\n')
        return
    end

    -- `["gist", "<id>"]`
    local ok, reason = downloadGist(v[2])
    if not ok then
        io.stderr:write(reason.."\n")
        return
    end
end

return {
    addGist = add,
    installGist = install,
    processGistCommand = processCommand,
}
