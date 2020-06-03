package.path = package.path..";../sources/?.lua"

local ArgP = require "arg-parser"
local Assert = require "assert"
local tests = {}

function tests.tokenize()
    Assert.equals(ArgP.splitCommand "", {})
    Assert.equals(ArgP.splitCommand [[ ab cd "ef gh'" 'ij "kl' ]], {"ab", "cd", "ef gh'", 'ij "kl'})
end

Assert.runTests(tests)
