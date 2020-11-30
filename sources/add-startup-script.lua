local currentDir = fs.getDir(arg[0])

local startupPath = "/startup.lua"
if fs.exists(startupPath) then return error('"'..startupPath..'" already exists.') end

local f, reason = io.open(startupPath, "w")
if not f then return error("Failed opening file '"..startupPath.."' for writing: "..reason) end

local contents = [[
local function addPath(dir)
    shell.setPath(shell.path()..":"..dir)
    local c = term.getTextColor()
    term.setTextColor(colors.lightGray)
    print("add", dir, "to PATH")
    term.setTextColor(c)
end

]].."addPath('"..currentDir.."')"

local f2, reason = f:write(contents)
if not f2 then f:close(); return error("Failed to write the file '"..startupPath.."': "..reason) end
f:close()

local function writeC(contents, color)
    local c = term.getTextColor()
    term.setTextColor(color)
    io.stdout:write(contents)
    io.stdout:flush()
    term.setTextColor(c)
end
local function writeCN(contents, color)
    writeC(contents, color);
    writeC("\n", color)
end

local stringColor = colors.orange
local otherColor = colors.lightGray
writeC("Created file ", otherColor); writeC("'"..startupPath.."'", stringColor); writeCN(".", otherColor)
writeC("After rebooting, ", otherColor); writeC("'"..currentDir.."'", stringColor); writeCN(" will be added to your PATH.", otherColor)
