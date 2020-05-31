package.path = package.path..";../sources/?.lua"

require "cc_mock"
local Memoried = require "memoried"
local Assert = require "assert"
local tests = {}

function tests.directionRoundtrip()
    for d = 1, 6 do
        local g = Memoried.toGlobalDirection(d)
        local l = Memoried.toLocalDirection(g)
        Assert.equals(d, l, tostring(d).." => "..tostring(g).." => "..tostring(l))
    end
    for d = 1, 6 do
        local l = Memoried.toLocalDirection(d)
        local g = Memoried.toGlobalDirection(l)
        Assert.equals(d, g, tostring(d).." => "..tostring(l).." => "..tostring(g))
    end
end

Assert.runTests(tests)
