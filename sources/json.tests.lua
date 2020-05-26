local Json = require("json")

local function deepEq(a, b)
    if a == b then return true end

    local at = type(a)
    local bt = type(b)
    if at ~= bt then return false end
    if at == "number" then
        -- nan
        if at ~= at and bt ~= bt then return true end
        return false
    elseif at == "table" then
end
local function assertEquals(a, b)
    if not (a == b) then
        assert(false, string.format("assertEquals(%s, %s)", tostring(a), tostring(b)))
    end
end

local tests = {}

function tests.stringifySimple()
    assertEquals(Json.stringify(nil), "null")
    assertEquals(Json.stringify(0), "0")
    assertEquals(Json.stringify(0/0), "nan")
    assertEquals(Json.stringify "abc", "\"abc\"")
    assertEquals(Json.stringify(true), "true")
    assertEquals(Json.stringify(false), "false")
    assertEquals(Json.stringify {"a","b","c"}, [=[[ "a", "b", "c" ]]=])
    assertEquals(Json.stringify({ x = 10, y = 20, list = {1, 2, 3} }), [[{ "y": 10, "x": 20, "list": [ 1, 2, 3 ] }]])

    local d = { x = 10, y = 20 }
    print(tostring(d))
end

for k, test in pairs(tests) do
    test()
end