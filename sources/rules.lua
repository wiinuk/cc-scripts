local Ex = require "extensions"
local Logger = require "logger"


---@class Rule
---@field public name string
---@field public when fun(self: Rule): boolean|number, any, any
---@field public action fun(self: Rule, result1: any, result2: any): any

---@type Rule[]
local rules = {}
local function reset()
    Ex.clearArray(rules)
end

---@param rule Rule
local function add(rule)
    rules[#rules+1] = rule
end


---@param nonMatchHandler fun(): boolean
local function evaluateRules(nonMatchHandler)
    local minSleepTime = 0.5
    local maxSleepTime = 10
    local sleepTime = minSleepTime

    nonMatchHandler = nonMatchHandler or function()
        Logger.log("available rule is not found.")
        sleepTime = math.min(sleepTime * 2, maxSleepTime)
        Logger.log("sleep", tostring(sleepTime).."s")
        os.sleep(sleepTime)
    end

    local runningThreadCount = 0
    local maxPriorityRuleCount = 0
    ---@type Rule[]
    local maxPriorityRules = {}
    --- `{ result1,..,result5, { result6,..,resultN }, ... }`
    ---@type any[]
    local maxPriorityResults = {}

    local function processWhenResult(maxPriority, rule, priority, result1, result2, result3, result4, result5, ...)
        if priority then
            if maxPriority <= priority then
                if maxPriority < priority then
                    Ex.clearArray(maxPriorityRules)
                    Ex.clearArray(maxPriorityResults)
                    maxPriorityRuleCount = 0
                end
                maxPriorityRuleCount = maxPriorityRuleCount + 1

                maxPriorityRules[maxPriorityRuleCount] = rule

                -- 6 = 5(固定長の戻り値個数) + 1(残りの可変長戻り値を格納する配列)
                local i = maxPriorityRuleCount * 6
                maxPriorityResults[i - 5] = result1
                maxPriorityResults[i - 4] = result2
                maxPriorityResults[i - 3] = result3
                maxPriorityResults[i - 2] = result4
                maxPriorityResults[i - 1] = result5
                if select("#", ...) ~= 0 then maxPriorityResults[i] = {...} end

                return priority
            end
            Logger.logInfo("-", "'"..rule.name.."'", "@"..tostring(priority))
        end
        return maxPriority
    end

    while true do
        local maxPriority = -99999999
        for i = 1, #rules do
            ---@type Rule
            local rule = rules[i]
            maxPriority = processWhenResult(maxPriority, rule, rule:when())
        end
        if maxPriorityRuleCount == 0 then
            if runningThreadCount == 0 and nonMatchHandler() then return end
        else
            sleepTime = minSleepTime

            local index = math.random(1, maxPriorityRuleCount)
            local rule = maxPriorityRules[index]
            local i = index * 6
            local result1 = maxPriorityResults[i - 5]
            local result2 = maxPriorityResults[i - 4]
            local result3 = maxPriorityResults[i - 3]
            local result4 = maxPriorityResults[i - 2]
            local result5 = maxPriorityResults[i - 1]
            local result6ToN = maxPriorityResults[i]
            Ex.clearArray(maxPriorityRules)
            Ex.clearArray(maxPriorityResults)
            maxPriorityRuleCount = 0

            Logger.log("#", "'"..rule.name.."'", "@"..tostring(maxPriority))

            if result6ToN
            then rule:action(result1, result2, result3, result4, result5, unpack(result6ToN))
            else rule:action(result1, result2, result3, result4, result5)
            end
        end
    end
end

return {
    reset = reset,
    evaluate = evaluateRules,
    add = add,
}