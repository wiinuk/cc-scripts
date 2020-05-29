
local function parseNamedOption(arguments, key, shortKey, options, parseValue)
    if 0 == #arguments then return false end

    local arg = string.lower(arguments[1])
    if arg ~= "--"..key and arg ~= "-"..shortKey then return false end

    if #arguments < 2 then
        error("requires <"..key..">")
        return false
    end

    options[key] = parseValue(arguments[2])
    table.remove(arguments, 1)
    table.remove(arguments, 1)
    return true
end

return {
    parseNamedOption = parseNamedOption
}
