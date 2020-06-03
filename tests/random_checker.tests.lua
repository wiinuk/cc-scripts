local Assert = require "assert"
local Checker = require "random_checker"

local tests = {}
function tests.findSmallestFailureTest()
    local _, minValue, minReason = Checker._findSmallestFailureTest(
        100,
        Checker.byte.shrinker,
        function (x) if 1 <= x and x <= 10 then error(tonumber(x).." is bad number") end end,
        10,
        "initial reason(10)"
    )
    Assert.equals(minValue, 1, minReason)

    local _, minValue, minReason = Checker._findSmallestFailureTest(
        100,
        Checker.byte.shrinker,
        function (x) if x == 10 or x == 8 or x == 7 then error("don't like "..tonumber(x)) end end,
        10,
        "initial reason(10)"
    )
    Assert.equals(minValue, 7, minReason)
end

---@generic T
---@param it fun(): T|nil
---@return T[]
local function iteratorToArray(it)
    local result = {}
    for x in it do result[#result+1] = x end
    return result
end

local function shrinkToArray(arbitrary, value)
    return iteratorToArray(arbitrary.shrinker(value))
end

local function identity(...) return ... end

function tests.shrinkArray()
    local byteArray = Checker.array(Checker.byte)
    Assert.equals(shrinkToArray(byteArray, {}), {})
    Assert.equals(shrinkToArray(byteArray, { 0 }), { {} })
    Assert.equals(shrinkToArray(byteArray, { 10 }), { {}, { 0 }, { 5 }, { 8 }, { 9 } })
    Assert.equals(shrinkToArray(byteArray, { 0, 1 }), { { 1 }, { 0 }, { 0, 0 } })
end

function tests.convertArbitrary()
    local arb = Checker._convertArbitrary(Checker.byte, identity, identity, "byte")
    Assert.equals(shrinkToArray(arb, 4), { 0, 2, 3 })
end

function tests.stringArb()
    Assert.equals(shrinkToArray(Checker.string, "abc"), { "bc", "ac", "ab", "aba", "abb", "aac" })
end

Assert.runTests(tests)
