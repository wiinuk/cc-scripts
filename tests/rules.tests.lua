package.path = package.path..";../sources/?.lua"
local Assert = require "assert"
local Rules = require "rules"
local tests = {}


function tests.evaluationOrder()
    local exit = false
    local log = {}
    local function add(x)
        log[#log+1] = x
    end
    Rules.reset()
    Rules.add {
        name = "test",
        when = function()
            if exit then
                add "C"
                return false
            end
            add "A"
            return 1
        end,
        action = function()
            add "B"
            exit = true
        end
    }
    Rules.evaluate(function() return true end)
    Assert.equals(log, {"A","B","C"})
end

function tests.evaluateWhenError()
    local exit = false
    Rules.reset()
    Rules.add {
        name = "test",
        when = function ()
            if exit then return false end
            error("e")
            return 1
        end,
        action = function ()
            exit = true
        end
    }
    Assert.throws(function() Rules.evaluate(function() return true end) end)
end

function tests.evaluateActionError()
    local exit = false
    Rules.reset()
    Rules.add {
        name = "test",
        when = function ()
            if exit then return false end
            return 1
        end,
        action = function ()
            error("e")
            exit = true
        end
    }
    Assert.throws(function() Rules.evaluate(function() return true end) end)
end

function tests.parameter()
    local exit = false
    Rules.reset()
    Rules.add {
        name = "test",
        field = "ABC",
        when = function(self)
            if exit then return false end

            Assert.equals(self.field, "ABC")
            return 1, "D", "E", "F", "G", "H", "I", "J"
        end,
        action = function(self, x1, x2, x3, x4, x5, x6, x7, x8)
            Assert.equals(self.field, "ABC")
            Assert.equals({ x1, x2, x3, x4, x5, x6, x7 }, { "D", "E", "F", "G", "H", "I", "J" })
            Assert.equals(x8, nil)
            exit = true
        end
    }
    Rules.evaluate(function() return true end)
end

Assert.runTests(tests)
