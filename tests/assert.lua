package.path = package.path..";../sources/?.lua"

local pretty = require "pretty"

local function tablePath(path, key)
    local t = type(key)
    key = tostring(key)

    if t == "number" then
        return path.."["..key.."]"
    elseif string.match(key, "^[%l%u_][%w_]*$") then
        return path.."."..key
    else
        return path..'["'..key..'"]'
    end
end

---@param visitedTablesA table
---@param visitedTablesB table
---@param path string
---@return boolean success
---@return string|nil path
---@return any|nil differenceA
---@return any|nil differenceB
local function deepDiff(a, b, path, visitedTablesA, visitedTablesB)
    if a == b then return true end

    local at = type(a)
    local bt = type(b)
    if at ~= bt then return false, "type("..path..")", at, bt end

    -- nan
    if at == "number" and a ~= a and b ~= b then return true end

    if at == "table" then
        if visitedTablesA[a] == true or visitedTablesB[b] == true then
            return false, "cycle("..path..")", a, b
        end
        visitedTablesA[a] = true
        visitedTablesB[b] = true

        local aKeys = {}
        local bKeys = {}
        for ak in pairs(a) do aKeys[ak] = true end
        for bk in pairs(b) do bKeys[bk] = true end

        for ak, av in pairs(a) do
            local kPath = tablePath(path, ak)
            if not bKeys[ak] then
                return false, kPath, av, nil
            else
                local ok, diffPath, diffA, diffB = deepDiff(av, b[ak], kPath, visitedTablesA, visitedTablesB)
                if not ok then return false, diffPath, diffA, diffB end
            end
        end
        for bk, bv in pairs(b) do
            local kPath = tablePath(path, bk)
            if not aKeys[bk] then
                return false, kPath, nil, bv
            else
                local av = a[bk]
                if not visitedTablesA[av] and not visitedTablesB[bv] then
                    local ok, diffPath, diffA, diffB = deepDiff(av, bv, kPath, visitedTablesA, visitedTablesB)
                    if not ok then return false, diffPath, diffA, diffB end
                end
            end
        end
        return true
    end

    return false, path, a, b
end

---@param message string
---@param level integer
---@overload fun(message: string): nil
local function failure(message, level)
    if level == nil then level = 1 end
    assert(false, debug.traceback(message, level + 1))
end

--- `assert(deepEquals(nan, nan))`
--- `assert(deepEquals({x=1,y=2}, {x=1,y=2}))`
---@generic T
---@param a T
---@param b T
---@param message string|nil
local function deepEquals(a, b, message)
    local ok, path, diffA, diffB = deepDiff(a, b, "", {}, {})
    if not ok then
        local location = ""
        if path ~= "" then
            location = ", at: `"..path.."`, a: "..pretty(diffA)..", b: "..pretty(diffB)
        end
        if message
        then message = "'"..message.."', "
        else message = ""
        end
        failure(message.."deepEquals("..pretty(a)..", "..pretty(b)..")"..location, 2)
    end
end

--- ``
--- `assert(not equals(nan, nan))`
---@generic T
---@param a T
---@param b T
---@param message string|nil
local function equals(a, b, message)
    if not (a == b) then
        if message
        then message = "'"..message.."', "
        else message = ""
        end
        failure(message..pretty(a).." == "..pretty(b), 2)
    end
end

---@param tests table
local function runTests(tests)
    print "starting tests"
    local totalCount = 0
    local failures = {}
    for k, test in pairs(tests) do
        local ok, error = pcall(test)

        totalCount = totalCount + 1

        if ok then
            print("", k)
        else
            print("", k, "[FAIL]")
            failures[#failures+1] = { name = k, messages = { error } }
        end
    end
    print "finished"

    for i = 1, #failures do
        local f = failures[i]
        print("Failed", f.name)
        print "ErrorMessage:"
        for _, v in ipairs(f.messages) do print(v) end
    end
    print ""
    print("Total tests: "..totalCount..",", "Passed: "..totalCount - #failures..",", "Failed: "..#failures)
    if #failures ~= 0 then
        print "Test Run Failed."
    else
        print "Test Run Successful."
    end
end

return {
    deepEquals = deepEquals,
    shallowEquals = equals,
    equals = deepEquals,
    failure = failure,
    runTests = runTests,
}
