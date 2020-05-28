local args = {...}
local commandName = "lacc"

-- remote setup mode
-- usage: `pastebin run <lacc_source_id> remote-setup`
if #args == 1 and string.lower(args[1]) == "remote-setup" then
    fs.delete(shell.resolve(commandName))
    shell.run("pastebin", "get", "6ARHfeVq", fs.combine(commandName, "json.lua"))
    shell.run("pastebin", "get", "W13jSN37", fs.combine(commandName, commandName..".lua"))
    return
end

local Json = require 'json'

local configPath = "dependencies.json"
local packageRootPath = "packages"

local function emptyConfig() return {} end

local function showUsage()
    print "Usages:"
    print(commandName.." init", "create an config file")
    print(commandName.." install", "setup dependencies")
    print(commandName.." github", "manipulate GitHub references")
    print(commandName.." gist", "manipulate Gist references")
end

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
local function writeFile(path, contents)
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
    return writeFile(path, json)
end

---@param address string
---@param headers table|nil
---@overload fun(address: string): string|nil, string|nil
local function downloadString(address, headers)
    local r = http.get(address, headers)
    if not r then return nil, "http get failed: '"..address.."'" end
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
local function downloadToFile(address, path)
    local content, reason = downloadString(address)
    if content == nil then return false, reason end

    local ok, reason = writeFile(path, content)
    if not ok then return false, reason end
    return true
end

---@param rootPath string
---@param response table
local function downloadGithubContentFiles(rootPath, response)
    if response.type == "file" then
        local address = response.download_url
        local filePath = fs.combine(rootPath, response.path)
        local ok, reason = downloadToFile(address, filePath)
        if not ok then return false, reason end

        print("github: '"..address.."' => '"..shell.resolve(filePath).."'")
        return true

    elseif response.type == "dir" then
        local ok, response = downloadJson(response.url)
        if not ok then return false, response end
        return downloadGithubContentFiles(rootPath, response)

    elseif response.type == nil then
        -- array of (file or dir)
        for _, v in ipairs(response) do
            local ok, error = downloadGithubContentFiles(rootPath, v)
            if not ok then return ok, error end
        end
        return true
    else
        return false, "unknown file type '"..response.."' at "..tostring(response.path).."'"
    end
end

---@param ownerAndRepo string
---@param path string
---@param branch string
local function downloadGithub(ownerAndRepo, branch, path)
    local headers = nil
    if branch ~= nil or branch ~= "" then
        headers = {}
        headers.ref = branch
    end
    local ok, response = downloadJson("https://api.github.com/repos/"..ownerAndRepo.."/contents/"..path, headers)
    if not ok then return false, response end

    local rootPath = fs.combine(fs.combine(packageRootPath, "github"), ownerAndRepo)
    local fullPath = shell.resolve(rootPath)
    fs.delete(fullPath)
    if fs.exists(fullPath) then return false, "Failed delete directory '"..rootPath.."'" end

    return downloadGithubContentFiles(rootPath, response)
end

---@param id string gist id.
local function downloadGist(id)
    local ok, gist = downloadJson("https://api.github.com/gists/"..id)
    if not ok then return false, gist end

    local gistRootPath = fs.combine(fs.combine(packageRootPath, "gist"), id)
    fs.delete(shell.resolve(gistRootPath))
    if fs.exists(shell.resolve(gistRootPath)) then
        return false, "Failed delete directory '"..gistRootPath.."'"
    end

    for _, f in pairs(gist.files) do
        local filePath = fs.combine(gistRootPath, f.filename)
        local ok, reason = writeFile(filePath, f.content)
        if not ok then return false, reason end

        print("gist: "..id.." '"..f.filename.."' => '"..shell.resolve(filePath).."'")
    end
    return true
end

---@param arguments string[]
local function init(arguments)
    if 0 < #arguments then
        io.stderr:write("unrecognized argument: '"..arguments[1].."'")
        return
    end
    if fs.exists(shell.resolve(configPath)) then
        print(commandName.." is already initialized in "..shell.resolve("."))
        return
    end

    local ok, error = writeJson(configPath, emptyConfig())
    if not ok then io.stderr:write(error.."\n") return end

    print("created '"..configPath.."'")
end

---@param sign string
---@return string ownerAndRepo
---@return string branch
local function splitGithubSign(sign)
    local start = string.find(sign, ":")
    if start == nil then return sign, "" end
    return string.sub(sign, 1, start - 1), string.sub(sign, start + 1)
end

---@param arguments string[]
local function install(arguments)
    if 0 < #arguments then
        io.stderr:write("unrecognized argument: '"..arguments[1].."'")
        return
    end
    local ok, result = readJson(configPath)
    if not ok then
        io.stderr:write("configure file not found. "..result.."\n")
        return
    end

    if type(result) ~= "table" then return end

    -- `[...]`
    for _, v in ipairs(result) do
        if v[1] == "gist" then
            if #v ~= 2 or type(v[2]) ~= "string" then
                io.stderr:write('invalid format in "'..configPath..'", e.g. `["gist", "<gist_id>"]`\n')
                return
            end

            -- `["gist", "<id>"]`
            local ok, reason = downloadGist(v[2])
            if not ok then
                io.stderr:write(reason.."\n")
                return
            end

        elseif v[1] == "github" then
            local sign = ""
            local path = ""
            if #v == 2 and type(v[2]) == "string" then
                sign = v[2]
            elseif #v == 3 and type(v[2]) == "string" and type(v[3]) == "string" then
                sign = v[2]
                path = v[3]
            else
                io.stderr:write('invalid format in "'..configPath..'"\n')
                io.stderr:write('e.g. `["github", "<repository>"]`\n')
                io.stderr:write('e.g. `["github", "<repository>", "<path>"]`\n')
                return
            end

            local ownerAndRepo, branch = splitGithubSign(sign)
            local ok, error = downloadGithub(ownerAndRepo, branch, path)
            if not ok then
                io.stderr:write(error.."\n")
                return
            end
        end
    end
end

---@param arguments string[]
---@return string|nil loweredSubCommand
local function parseSub(arguments)
    if #arguments < 1 then return nil end

    local subCommand = string.lower(arguments[1])
    local subArguments = {unpack(arguments)}
    table.remove(subArguments, 1)
    return subCommand, subArguments
end

local function showGithubAddUsage()
    print("Usage:")
    print(commandName.." github add <repository> [<path>]")
    print("<repository>", "`<owner>/<repo>[:<branch>]`")
    print("<owner>", "repository owner name on github")
    print("<repo>", "repository name on github")
    print("<branch>", "specify the desired branch")
    print("<path>", "path to file or dir to add")
    print("Example:")
    print(commandName.." github add lua/lua")
    print(commandName.." github add lua/lua:master manual/manual.of")
end

---@param arguments string[]
local function githubAdd(arguments)
    if #arguments < 2 then
        io.stderr:write("missing argument '<repository>'\n")
        return showGithubAddUsage()
    end
    if 2 < #arguments then
        io.stderr:write("unrecognised argument: '"..arguments[2].."'\n")
        return showGithubAddUsage()
    end

    local ok, result = readJson(configPath)
    if not ok then
        io.stderr:write("configure file not found. "..result.."\n")
        return
    end

    -- TODO:
    if type(result) ~= "table" then result = emptyConfig() end

    local sign = arguments[1]
    local ownerAndRepo, branch = splitGithubSign(sign)
    local ownerAndRepo = string.lower(ownerAndRepo)
    local path = arguments[2]

    for _, value in pairs(result) do
        if
            type(value) == "table" and
            string.lower(tostring(value[1])) == "github"
        then
            local ownerAndRepo2 = splitGithubSign(tostring(value[2]))
            if ownerAndRepo == string.lower(ownerAndRepo2) then
                print(configPath.." contains 'github "..ownerAndRepo.."' already.")
                return
            end
        end
    end

    result[#result+1] = {"github", sign, path}
    local ok, error = writeJson(configPath, result)
    if not ok then io.stderr:write(error) end

    local ok, reason = downloadGithub(ownerAndRepo, branch, path)
    if not ok then io.stderr:write(reason) end
    return
end

local function showGithubUsage()
    print("Usage:")
    print(commandName.." github <subcommand> <options>")
    print("List of <subcommand>:")
    print("add <repository> [<path>]", "add github repository")
end

---@param arguments string[]
local function github(arguments)
    local subCommand, subArguments = parseSub(arguments)
    if subCommand == nil then
        io.stderr:write("missing subcommand\n")
        return showGithubUsage()
    end

    if subCommand == "add" then return githubAdd(subArguments)
    else
        io.stderr:write("unrecognized subcommand '"..subCommand.."'\n")
        return showGithubUsage()
    end
end

---@param arguments string[]
local function gistAdd(arguments)
    if #arguments < 1 then
        io.stderr:write("requires gist id. e.g. `"..commandName.." gist add <gist_id>`\n")
        return
    end
    if 1 < #arguments then
        io.stderr:write("unrecognised argument: `"..arguments[2].."e.g. `"..commandName.." gist add <gist_id>`\n")
        return
    end

    local id = arguments[1]

    local ok, result = readJson(configPath)
    if not ok then
        io.stderr:write("configure file not found. "..result.."\n")
        return
    end

    -- TODO:
    if type(result) ~= "table" then result = emptyConfig() end

    for _, value in pairs(result) do
        if
            type(value) == "table" and
            string.lower(tostring(value[1])) == "gist" and
            string.lower(tostring(value[2])) == id
        then
            print(configPath.." contains 'gist "..id.."' already.")
            return
        end
    end

    result[#result+1] = {"gist", id}
    local ok, error = writeJson(configPath, result)
    if not ok then io.stderr:write(error) end

    local ok, reason = downloadGist(id)
    if not ok then io.stderr:write(reason) end
    return
end

local function showGistUsage()
    print("Usage:")
    print(commandName.." gist <subcommand> <options>")
    print("List of <subcommand>:")
    print("add <id>", "add a new dependency from gist")
end

---@param arguments string[]
local function gist(arguments)
    local subCommand, subArguments = parseSub(arguments)
    if subCommand == nil then
        io.stderr:write("missing subcommand\n")
        return showGistUsage()
    end

    if subCommand == "add" then return gistAdd(subArguments)
    else
        io.stderr:write("unrecognized subcommand '"..subCommand.."'\n")
        return showGistUsage()
    end
end

---@param arguments string[]
local function processArguments(arguments)
    local subCommand, subArguments = parseSub(arguments)
    if subCommand == nil then return showUsage() end

    if subCommand == "install" then return install(subArguments)
    elseif subCommand == "init" then return init(subArguments)
    elseif subCommand == "github" then return github(subArguments)
    elseif subCommand == "gist" then return gist(subArguments)
    else return showUsage() end
end

processArguments {...}
