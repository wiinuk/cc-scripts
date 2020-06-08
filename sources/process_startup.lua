local args = {...}
if #args < 1 then return end

local function addPath(dir)
    shell.setPath(shell.path()..":"..dir)
    local c = term.getTextColor()
    term.setTextColor(colors.lightGray)
    print("add", dir, "to PATH")
    term.setTextColor(c)
end

addPath(args[1])
