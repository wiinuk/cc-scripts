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

local messageHandlers = {}
local function addHandler(type, handler)
    local hs = messageHandlers[type] or {}
    hs[#hs+1] = handler
    messageHandlers[type] = hs
end

addHandler("rednet_message", function(id, message)
    local ok, result = Json.parse(message)
    if ok and result.__typeId == Logger.MessageTypeId then
        Logger.logCore(result.level, tostring(id)..">", unpack(result.messages))
    else
        Logger.log(tostring(id)..">", message)
    end
end)

local function onPeripheralChanged()
    local m = peripheral.find("monitor")
    if m then
        m.setTextScale(0.5)
        Logger.addListener(Logger.terminalListener(m, Logger.Debug))
    end
end
onPeripheralChanged()
addHandler("peripheral", onPeripheralChanged)
addHandler("peripheral_detach", onPeripheralChanged)

local function processEvent(event, ...)
    local handlers = messageHandlers[event]
    if handlers then
        for _, handler in ipairs(handlers) do
            handler(...)
        end
    end
end

local function eventLoop()
    while true do processEvent(os.pullEvent()) end
end


Logger.addListener(Logger.printListener(Logger.Info))
shell.openTab("shell")
rednet.open(getPeripheralSideByType "modem")
Logger.log("starting receive")
eventLoop()
