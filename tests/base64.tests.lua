package.path = package.path..";../dev/lacc-sources/?.lua"
package.path = package.path..";../sources/?.lua"

local Base64 = require "base64"
local Assert = require "assert"
local pretty = require "pretty"
local tests = {}

function tests.encodeSimple()
    Assert.equals(Base64.encode(""), "")
    Assert.equals(Base64.encode("abcdefg"), "YWJjZGVmZw==")
    Assert.equals(Base64.encode("Hello, world"), "SGVsbG8sIHdvcmxk")
end

local function roundtrip(expected)
    local source = Base64.encode(expected)

    local actual, reason = Base64.decode(source)
    if not actual then Assert.failure("error: `"..reason.."` from Base64.decode(\""..pretty(source).."\")") end
    Assert.equals(expected, actual)
end

function tests.roundtripPropertyTest()
    local values = {}
    for size = 1, 100 do
        local bytes = {}
        local length = math.random(0, size)
        for _ = 1, length do
            bytes[#bytes+1] = math.random(0, 255)
        end
        values[#values+1] = string.char(unpack(bytes))
    end

    for _, value in ipairs(values) do
        roundtrip(value)
    end
end

Assert.runTests(tests)
