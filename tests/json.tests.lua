package.path = package.path..";../dev/lacc-sources/?.lua"
package.path = package.path..";../sources/?.lua"

local Json = require "json"
local Assert = require "assert"
local pretty = require "pretty"
local tests = {}

function tests.stringifySimple()
    Assert.equals(Json.stringify(nil), "null")
    Assert.equals(Json.stringify(0), "0")
    Assert.equals(Json.stringify(0/0), "nan")
    Assert.equals(Json.stringify("abc"), "\"abc\"")
    Assert.equals(Json.stringify(true), "true")
    Assert.equals(Json.stringify(false), "false")
    Assert.equals(Json.stringify {"a","b","c"}, '["a","b","c"]')
end

---@param options StringifyOptions|nil
local function roundtrip(expected, options)
    local source, error = Json.stringify(expected, options)
    if source == nil then Assert.failure("error: `"..error.."` from Json.stringify("..pretty(expected)..")") end

    local ok, actual = Json.parse(source)
    if not ok then Assert.failure("error: `"..actual.."` from Json.parse(\""..pretty(source).."\")") end

    Assert.equals(expected, actual)
end

function tests.nanRoundtrip() roundtrip(0/0) end
function tests.infRoundtrip() roundtrip(1/0) end
function tests.minusInfRoundtrip() roundtrip(-1/0) end
function tests.stringRoundtrip() roundtrip("A") end

function tests.roundtrip()
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
        "\b\f\n\r\t\"\\",
        "/'",
        {},
        {1,2,3},
        { x = 10, y = 20 },
        { x = 10, y = 20, xs = { 1, 2, 3 }, d = { name = "bob", age = 256 } },
    }
    local spaces = {
        nil,
        "",
        "  ",
    }
    local indents = {
        nil,
        "",
        "  ",
    }
    local maxWidths = {
        0,
        64,
        9999,
    }
    for _, value in ipairs(values) do
        roundtrip(value, nil)

        for _, indent in ipairs(indents) do
            for _, maxWidth in ipairs(maxWidths) do
                for _, space in ipairs(spaces) do
                    local options = { space = space, indent = indent, maxWidth = maxWidth }
                    roundtrip(value, options)
                end
            end
        end
    end
end

Assert.runTests(tests)
