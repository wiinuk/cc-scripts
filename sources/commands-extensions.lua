local pretty = require "pretty"

local function foldHead(state, folder, length, head, ...)
    if length == 0 then return state end
    return foldHead(folder(state, head), folder, select("#", ...), ...)
end
local function fold(state, folder, ...)
    return foldHead(state, folder, select("#", ...), ...)
end

local function execCommand(...)
    local function appendArgs(args, arg)
        if arg == nil then return args end
        if type(arg) ~= "string" then
            arg = textutils.serializeJSON(arg, true)
        end
        args[#args+1] = arg
        return args
    end

    local args = fold({}, appendArgs, ...)
    local command = table.concat(args, " ")
    local ok, result = commands.exec(command)
    print(pretty(ok), "`"..command.."`", "=>", pretty(result))
    return ok, result
end

return {
    exec = execCommand,
}