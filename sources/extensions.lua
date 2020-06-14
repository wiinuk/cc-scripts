
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

local function id(...) return ... end
local function noop() end
local function const(arg1, ...)
    if 0 < select("#", ...) then
        local args = {...}
        return function() return arg1, unpack(args) end
    else
        return function() return arg1 end
    end
end

local function clamp(x, minBound, maxBound)
    return math.max(minBound, math.min(maxBound, x))
end

---@generic T
---@param array1 table<integer, T>
---@param array2 table<integer, T>
---@return table<integer, T>
local function appendArray(array1, array2)
    if (not array1 or #array1 == 0) and (not array2 or #array2 == 0) then return nil end

    local result = {}
    if array1 then
        for i = 1, #array1 do result[#result+1] = array1[i] end
    end
    if array2 then
        for i = 1, #array2 do result[#result+1] = array2[i] end
    end
    return result
end

local function existsArray(array, predicate)
    for _, v in ipairs(array) do
        if predicate(v) then return true end
    end
    return false
end
local function containsArray(array, target)
    return existsArray(array, function (x) return x == target end)
end

---@generic T
---@param array table<integer, T>
---@param toPriority fun(item: T): number|nil
---@return T|nil maxPriorityItem
---@return number|nil maxPriority
local function maxByArray(array, toPriority)
    if not array or #array == 0 then return end

    local maxPriority = -1 / 0
    local maxPriorityItem = nil
    for i = 1, #array do
        local item = array[i]
        local priority = toPriority(item, i)
        if priority and maxPriority <= priority then
            maxPriorityItem = item
            maxPriority = priority
        end
    end
    return maxPriorityItem, maxPriority
end

return {
    printError = printError,
    clearTable = clearTable,
    clearArray = clearArray,
    appendArray = appendArray,
    containsArray = containsArray,
    existsArray = existsArray,
    maxByArray = maxByArray,
    noop = noop,
    id = id,
    const = const,
    clamp = clamp,
}