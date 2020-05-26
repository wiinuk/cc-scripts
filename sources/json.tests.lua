local Json = require "json"
local Assert = require "assert"
local tests = {}

function tests.stringifySimple()
    Assert.equals(Json.stringify(nil), "null")
    Assert.equals(Json.stringify(0), "0")
    Assert.equals(Json.stringify(0/0), "nan")
    Assert.equals(Json.stringify("abc"), "\"abc\"")
    Assert.equals(Json.stringify(true), "true")
    Assert.equals(Json.stringify(false), "false")
    Assert.equals(Json.stringify {"a","b","c"}, [=[[ "a", "b", "c" ]]=])
end

function tests.roundtrip()
    local function roundtrip(expected)
        local source, error = Json.stringify(expected)
        if source == nil then Assert.failure("error: `"..error.."` from Json.stringify("..tostring(expected)..")") end

        local ok, actual = Json.parse(source)
        if not ok then Assert.failure("error: `"..actual.."` from Json.parse(\""..tostring(source).."\")") end

        Assert.equals(expected, actual)
    end

    local values = {
        nil,
        true,
        false,
        0,
        1,
        -1,
        -0.5,
        0/0,
        1/0,
        -1/0,
        "",
        "abc",
        "a\"b\\c",
        {},
        {1,2,3},
        { x = 10, y = 20 },
        { x = 10, y = 20, xs = { 1, 2, 3 }, d = { name = "bob", age = 256 } },
    }
    for i = 1, #values do roundtrip(values[i]) end
end

Assert.runTests(tests)
