local Json = require "json"
local Logger = require "logger"

local sides = { "forward", "left", "back", "right", "bottom", "top", }

local function getPeripheralSidesByType(type)
    local ss = {}
    for _, s in ipairs(sides) do
        if type and peripheral.getType(s) == type then
            ss[#ss+1] = s
        end
    end
    return ss
end

local function getPeripheralSideByType(type, options)
    local ss = getPeripheralSidesByType(type)
    if #ss <= 0 then
        if options and options.noWait then return end

        Logger.log("waiting for a", type, "to be mounted")
        repeat
            os.pullEvent "peripheral"
            Logger.log("checking")
            ss = getPeripheralSidesByType(type)
        until 0 < #ss
        Logger.log("confirmed the mount of the", type)
    end

    local s = ss[1]
    if 2 <= #ss then
        Logger.log "choose side:"
        s = read(nil, ss)
    end
    return s
end

local function receiveThread()
    rednet.open(getPeripheralSideByType "modem")
    Logger.log("starting receive")

    while true do
        local id, message = rednet.receive()
        local ok, result = Json.parse(message)
        if ok and result.__typeId == Logger.LoggerMessageTypeId then
            Logger.logCore(result.level, tostring(id)..">", unpack(result.messages))
        else
            Logger.log(tostring(id)..">", message)
        end
    end
end


local monitor = peripheral.find "monitor"
if monitor then
    monitor.setTextScale(0.5)
    Logger.addListener(Logger.terminalListener(monitor, Logger.Debug))
end

Logger.addListener(Logger.printListener(Logger.Info))
shell.openTab("shell")
receiveThread()
