
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

return {
    printError = printError,
    clearTable = clearTable,
}