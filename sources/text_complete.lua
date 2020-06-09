local Ex = require "extensions"
local appendArray = Ex.appendArray
local pretty = require "pretty"


local function startsWith(prefix, target)
    if #target < #prefix then return false end
    for i = 1, #prefix do
        if string.byte(prefix, i) ~= string.byte(target, i) then
            return false
        end
    end
    return true
end

local function text(template)
    return function(source)
        if #template < #source then
            if not startsWith(template, source) then return false end

            local remaining = string.sub(source, #template + 1)
            return true, false, nil, remaining
        end
        if not startsWith(source, template) then return false end
        if #source == #template then return true, false, nil, "" end

        local completions = { (string.sub(template, #source + 1)) }
        return true, false, completions, ""
    end
end

local function merge(ok1, stop1, completions1, remaining1, ok2, stop2, completions2, remaining2)
    if ok1 and ok2 then
        local stop = stop1 and stop2
        if #remaining1 == #remaining2 then return true, stop, appendArray(completions1, completions2), remaining1 end
        if #remaining1 < #remaining2 then return true, stop, completions1, remaining1 end
        return true, stop, completions2, remaining2
    end
    if not ok1
    then return ok2, stop2, completions2, remaining2
    else return ok1, stop1, completions1, remaining1
    end
end

local function choice(...)
    local cs = {...}
    return function(source)
        local ok = false
        local stop = nil
        local completions = nil
        local remaining = nil

        for i = 1, #cs do
            ok, stop, completions, remaining =
                merge(ok, stop, completions, remaining, cs[i](source))
        end

        return ok, stop, completions, remaining
    end
end

local function append(rs, rs2)
    if not rs or #rs == 0 then return rs2 end
    if not rs2 or #rs2 == 0 then return nil end

    local result = {}
    for i = 1, #rs do
        local r = rs[i]
        for j = 1, #rs2 do
            result[#result+1] = r..rs2[j]
        end
    end
    return result
end

local function sequence(...)
    local cs = {...}
    return function(source)
        local source = source
        local isStop = false
        local rs = nil
        for i = 1, #cs do
            local ok, s, rs2, r = cs[i](source)
            if not ok then return false end
            if s and r == "" then return true, s, rs2, r end

            source = r
            isStop = isStop and s
            rs = append(rs, rs2)
        end
        return true, isStop, rs, source
    end
end

local function group(c)
    return function(source)
        local ok, _, cs, r = c(source)
        if ok then return true, true, cs, r end
        return false
    end
end

local function repeat0(c)
    return function(source)
        local isStop = false
        local rs = nil
        local source = source
        while true do
            local ok, s, rs2, r = c(source)
            if not ok then return true, isStop, rs, source end
            if s and r == "" then return true, s, rs2, r end
            if #source <= #r then return true, isStop, rs, source end

            isStop = isStop and s
            rs = append(rs, rs2)
            source = r
        end
    end
end

local function optional(c) return choice(c, text "") end

return {
    text = text,
    choice = choice,
    sequence = sequence,
    group = group,
    repeat0 = repeat0,
    optional = optional,
}