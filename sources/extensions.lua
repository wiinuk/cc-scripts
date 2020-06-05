
local function printError(...)
    local messages = {...}
    for i = 1, #messages do
        messages[i] = tostring(messages[i])
    end
    io.stderr:write(table.concat(messages, "\t").."\n")
end

local function clearTable(table)
    for k in pairs(table) do
        table[k] = nil
    end
end

local function clearArray(table)
    for i = #table, 1, -1 do
        table[i] = nil
    end
end

local function noop() end

local function clamp(x, minBound, maxBound)
    return math.max(minBound, math.min(maxBound, x))
end

return {
    printError = printError,
    clearTable = clearTable,
    clearArray = clearArray,
    noop = noop,
    clamp = clamp,
}