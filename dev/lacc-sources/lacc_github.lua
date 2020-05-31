local Core = require "lacc_core"
local baseDomain = "https://api.github.com"

local function newHeaders()
    local ok, config = Core.readJson(fs.combine(Core.commandName, "config.json"))
    local key = (ok and config.key) or "2cf30cda5df23e85eb463e6a3ae5e44f567fef8b"
    local table = {
        ["Cache-Control"] = "max-age=0",
        DNT = "1",
        ["Sec-Fetch-Dest"] = "document",
        ["Sec-Fetch-Mode"] = "navigate",
        ["Sec-Fetch-Site"] = "cross-site",
        ["Sec-Fetch-User"] = "true",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.61 Safari/537.36",
        Authorization = "token "..key,
    }
    if ok and config.headers then
        for k, v in pairs(config.headers) do
            if v == nil then table[k] = nil
            else table[k] = tostring(v) end
        end
    end
    return table
end

local function head(ownerAndRepo, branchName)
    return Core.downloadJson(baseDomain.."/repos/"..ownerAndRepo.."/git/ref/heads/"..branchName, newHeaders())
end
local function tree(ownerAndRepo, treeSha)
    local ok, r = Core.downloadJson(baseDomain.."/repos/"..ownerAndRepo.."/git/trees/"..treeSha, newHeaders())
    if ok and r.truncated then return false, "truncated '"..r.url.."'" end
    return ok, r
end
---@return string|nil bytes
---@return string error
local function blob(ownerAndRepo, fileSha)
    local headers = newHeaders()
    headers["Accept"] = "application/vnd.github.v3.raw"
    return Core.downloadString(baseDomain.."/repos/"..ownerAndRepo.."/git/blobs/"..fileSha, headers)
end
local function repository(ownerAndRepo)
    return Core.downloadJson(baseDomain.."/repos/"..ownerAndRepo, newHeaders())
end

---@param treeResult table
---@param name string
---@return boolean success
---@return table|string entityOrError
local function findChildEntity(treeResult, name)
    local paths = {}
    for _, c in ipairs(treeResult.tree) do
        if c.path == name then return true, c end
        paths[#paths+1] = "'"..c.path.."'"
    end
    return false, "entity '"..name.."' is not found. find: ["..table.concat(paths, ", ").."]"
end

---@return string name
---@return string|nil path
local function splitPath(path)
    local index = string.find(path, "/")
    if index then return string.sub(path, 1, index-1), string.sub(path, index+1) end
    return path
end

---@return boolean success
---@return string typeOrError
---@return string|nil sha
local function entityShaAtPath(ownerAndRepo, treeSha, path)
    if path == "" then return true, "tree", treeSha end
    local name, path = splitPath(path)

    local ok, result = tree(ownerAndRepo, treeSha)
    if not ok then return ok, result end

    local ok, entity = findChildEntity(result, name)
    if not ok then return ok, entity end

    Core.log("find", "'"..name.."'", treeSha)

    if path then
        if entity.type ~= "tree" then
            return false, "entity '"..name.."' is not tree"
        end
        return entityShaAtPath(ownerAndRepo, entity.sha, path)
    else
        return true, entity.type, entity.sha
    end
end

---@class GithubEntityClient
---@field public ownerAndRepo string
---@field public pathToSha table
---@field public localRootDir string

---@param self GithubEntityClient
---@param sha string
---@param path string
local function downloadBlob(self, sha, path)
    local localPath = fs.combine(self.localRootDir, path)
    local localFullPath = shell.resolve(localPath)
    local isLatest =
        self.pathToSha[path] == sha and
        fs.exists(localFullPath) and
        not fs.isDir(localFullPath)

    if isLatest then
        Core.log("latest '"..path.."'")
        return true
    end

    local s, reason = blob(self.ownerAndRepo, sha)
    if not s then return false, reason end

    local ok, reason = Core.writeString(localPath, s)
    if not ok then return false, reason end

    self.pathToSha[path] = sha
    Core.log(baseDomain.."/repos/"..self.ownerAndRepo.."/git/blobs/"..path.." =>", "'"..localFullPath.."'")
    return true
end

local function downloadEntity(self, type, sha, path)
    if type == "blob" then return downloadBlob(self, sha, path) end
    if type == "tree" then
        local ok, result = tree(self.ownerAndRepo, sha)
        if not ok then return ok, result end

        Core.log("extract", "'"..path.."'", sha)
        for _, entity in ipairs(result.tree) do
            local ok, r = downloadEntity(self, entity.type, entity.sha, fs.combine(path, entity.path))
            if not ok then return ok, r end
        end
        return true
    end
    return false, "unknown entity type '"..type.."' "..sha
end

---@class GithubRepoLock
---@field public files table path to sha

---@class Lock
---@field public github table|nil ownerAndRepo to GithubRepoLock

---@param ownerAndRepo string `"owner/repo"`
---@param branch string allow empty string
---@param path string allow empty string
local function downloadGithub(ownerAndRepo, branch, path)
    if branch == nil or branch == "" then
        local ok, result = repository(ownerAndRepo)
        if not ok then return ok, result end
        branch = result.default_branch
    end
    Core.log("cloning", "github", ownerAndRepo, branch, "'"..path.."'")
    local ok, head = head(ownerAndRepo, branch)
    if not ok then return ok, head end

    local rootSha = head.object.sha
    local ok, type, sha = entityShaAtPath(ownerAndRepo, rootSha, path)
    if not ok then return ok, type end

    ---@type Lock
    local lock = {}
    local lockFullPath = shell.resolve(Core.lockPath)
    if fs.exists(lockFullPath) and not fs.isDir(lockFullPath) then
        local ok, result = Core.readJson(Core.lockPath)
        if not ok then return result end
        lock = result
    end
    if not lock.github then lock.github = {} end
    if not lock.github[ownerAndRepo] then lock.github[ownerAndRepo] = { files = {} } end

    ---@type GithubEntityClient
    local c = {
        ownerAndRepo = ownerAndRepo,
        pathToSha = lock.github[ownerAndRepo].files,
        localRootDir = fs.combine(Core.packageRootPath, ownerAndRepo),
    }
    local ok, reason = downloadEntity(c, type, sha, path)
    if not ok then return ok, reason end

    lock.github[ownerAndRepo].files = c.pathToSha
    return Core.writeJson(Core.lockPath, lock)
end

local function showGithubAddUsage()
    Core.log("Usage:")
    Core.log(Core.commandName.." github add <repository> [<path>]")
    Core.log("<repository>", "`<owner>/<repo>[:<branch>]`")
    Core.log("<owner>", "repository owner name on github")
    Core.log("<repo>", "repository name on github")
    Core.log("<branch>", "specify the desired branch")
    Core.log("<path>", "path to file or dir to add")
    Core.log("Example:")
    Core.log(Core.commandName.." github add lua/lua")
    Core.log(Core.commandName.." github add lua/lua:master manual/manual.of")
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
local function add(arguments)
    if #arguments < 2 then
        io.stderr:write("missing argument '<repository>'\n")
        return showGithubAddUsage()
    end
    if 2 < #arguments then
        io.stderr:write("unrecognised argument: '"..arguments[2].."'\n")
        return showGithubAddUsage()
    end

    local ok, result = Core.readJson(Core.configPath)
    if not ok then
        io.stderr:write("configure file not found. "..result.."\n")
        return
    end

    -- TODO:
    if type(result) ~= "table" then result = Core.emptyConfig() end

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
                Core.log(Core.configPath.." contains 'github "..ownerAndRepo.."' already.")
                return
            end
        end
    end

    result[#result+1] = {"github", sign, path}
    local ok, error = Core.writeJson(Core.configPath, result)
    if not ok then io.stderr:write(error) end

    local ok, reason = downloadGithub(ownerAndRepo, branch, path)
    if not ok then io.stderr:write(reason) end
    return
end

local function showGithubUsage()
    Core.log("Usage:")
    Core.log(Core.commandName.." github <subcommand> <options>")
    Core.log("List of <subcommand>:")
    Core.log("add <repository> [<path>]", "add github repository")
end

---@param arguments string[]
local function processCommand(arguments)
    local subCommand, subArguments = Core.parseSubCommand(arguments)
    if subCommand == nil then
        io.stderr:write("missing subcommand\n")
        return showGithubUsage()
    end

    if subCommand == "add" then return add(subArguments)
    else
        io.stderr:write("unrecognized subcommand '"..subCommand.."'\n")
        return showGithubUsage()
    end
end

---@param v string[]
local function install(v)
    local sign = ""
    local path = ""
    if #v == 2 and type(v[2]) == "string" then
        sign = v[2]
    elseif #v == 3 and type(v[2]) == "string" and type(v[3]) == "string" then
        sign = v[2]
        path = v[3]
    else
        io.stderr:write('invalid format in "'..Core.configPath..'"\n')
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

return {
    installGithub = install,
    processGithubCommand = processCommand,
}
