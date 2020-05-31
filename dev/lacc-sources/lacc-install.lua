local args = {...}
local commandName = "lacc"

-- remote setup mode
-- usage: `pastebin run W13jSN37 remote-setup`
if #args == 1 and string.lower(args[1]) == "remote-setup" then
    local function pastebin(map)
        for id, name in pairs(map) do
            local path = fs.combine(commandName, name..".lua")
            local fullPath = shell.resolve(path)
            if fs.exists(fullPath) then fs.delete(fullPath) end
            shell.run("pastebin", "get", id, path)
        end
    end
    return pastebin {
        ["6ARHfeVq"] = "json",
        ["fhcDWcP5"] = "lacc_core",
        ["U3TLpuEa"] = "lacc_gist",
        ["5HZxJq0i"] = "lacc_github",
        ["twhXYBMW"] = commandName,
    }
end
