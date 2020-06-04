package.path = package.path..";../sources/?.lua"
local Assert = require "assert"
local Heap = require "heap"
local Checker = require "random_checker"
local pretty = require "pretty"
local tests = {}


function tests.pushPop()
    local h = {}
    Heap.push(h, 2)
    Heap.push(h, 1)
    Heap.push(h, 9)

    Assert.equals(Heap.pop(h), 9)
    Assert.equals(Heap.pop(h), 2)
    Assert.equals(Heap.pop(h), 1)
    Assert.equals(Heap.pop(h), nil)
end

function tests.pushPopProperty()
    local function greaterThan(a, b) return a > b end

    local arb = Checker.array(Checker.int32)
    Checker.checkThrowOnFailure(arb, function (xs)
        local actual = {}
        local expected = {}
        for _, v in ipairs(xs) do
            Heap.push(actual, v)
            expected[#expected+1] = v
        end
        table.sort(expected, greaterThan)
        for i = 1, #xs do
            Assert.equals(Heap.pop(actual), expected[i], "expected: "..pretty(expected).." at "..i)
        end
        Assert.equals(Heap.pop(actual), nil)
    end)
end

Assert.runTests(tests)
