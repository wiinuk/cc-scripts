---@param value any
---@param buffer any[]
---@param visitedTables table
local function write(value, buffer, visitedTables)
    local t = type(value)
    if t == "table" then
        if visitedTables[value] then
            buffer[#buffer+1] = "..."
            return
        end
        visitedTables[value] = true

        buffer[#buffer+1] = "{ "
        if 0 < #value then
            -- array
            for _, v in ipairs(value) do
                write(v, buffer, visitedTables)
                buffer[#buffer+1] = ", "
            end
        else
            -- map
            for k, v in pairs(value) do
                if
                    string.match(k, "^[%l%u_][%w]*$") and
                    not string.match(k, "^(and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)$") then
                    buffer[#buffer+1] = k
                else
                    buffer[#buffer+1] = '["'
                    buffer[#buffer+1] = k
                    buffer[#buffer+1] = '"]'
                end
                buffer[#buffer+1] = " = "
                write(v, buffer, visitedTables)
                buffer[#buffer+1] = ", "
            end
        end
        buffer[#buffer+1] = " }"
    else
        buffer[#buffer+1] = value
    end
end

---@param value any
---@return string
local function pretty(value)
    local buffer = {}
    write(value, buffer, {})
    return table.concat(buffer)
end

return pretty
