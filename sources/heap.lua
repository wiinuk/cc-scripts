local function defaultCompare(x, y)
    if x < y then return -1 end
    if x == y then return 0 end
    return 1
end

---@generic
---@param heap T[]
---@param value T
---@param compare fun(x: T, y: T): integer
---@overload fun(heap: T[], value: T)
local function push(heap, value, compare)
    compare = compare or defaultCompare

    local n = #heap+1
    heap[n] = value

    while n ~= 1 do
        local i = math.modf((n - 2) / 2) + 1
        if compare(heap[n], heap[i]) > 0 then
            heap[n], heap[i] = heap[i], heap[n]
        end
        n = i
    end
end

---@generic T
---@param heap T[]
---@param compare fun(x: T, y: T): integer
---@return T|nil
---@return nil|string
---@overload fun(heap: T[]): T|nil, nil|string
local function pop(heap, compare)
    local n = #heap
    if n == 0 then return nil, "empty heap" end

    compare = compare or defaultCompare

    local result = heap[1]
    heap[1] = heap[n]
    table.remove(heap)

    local i = 1
    local j = 2 * (i - 1) + 2
    while j < n do
        if j ~= n - 1 and compare(heap[j], heap[j + 1]) < 0 then
            j = j + 1
        end

        if compare(heap[i], heap[j]) < 0 then
            heap[j], heap[i] = heap[i], heap[j]
        end
        i = j
        j = 2 * (i - 1) + 2
    end
    return result
end

local function peek(heap)
    local n = #heap
    if n == 0 then return nil, "empty heap" end
    return heap[1]
end

return {
    pop = pop,
    push = push,
    peek = peek,
}