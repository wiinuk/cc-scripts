local Ex = require "extensions"
local pretty = require "pretty"
---@class T
---@class U

---@generic T
---@class Arbitrary
---@field public name string|nil
---@field public generator fun(size: integer): T
---@field public shrinker fun(x: T): fun(): boolean|nil, T

local min = math.min
local max = math.max
local modf = math.modf
local yield = coroutine.yield
local wrap = coroutine.wrap

local function noop() end
local function emptyShrinker() return noop end

---@generic T
---@generic U
---@param generator fun(size: number): T
---@param mapping fun(x: T): U
local function mapGenerator(generator, mapping)
    return function(size)
        return mapping(generator(size))
    end
end

---@generic T
---@param shrinkerOfInnerValue fun(t: T): fun(): T|nil
---@param fromInnerValue fun(t: T): U
---@param toInnerValue fun(x: U): T
---@return fun(x: U): fun(): U|nil
local function convertShrinker(shrinkerOfInnerValue, fromInnerValue, toInnerValue)
    ---@param x U
    return function(x) return wrap(function()
        for innerValue in shrinkerOfInnerValue(toInnerValue(x)) do
            yield(fromInnerValue(innerValue))
        end
    end) end
end

local function convertArbitrary(arbitraryOfInnerValue, fromInnerValue, toInnerValue, name)
    return {
        name = "convert<"..(arbitraryOfInnerValue.name or "?")..", "..(name or "?")..">",
        generator = mapGenerator(arbitraryOfInnerValue.generator, fromInnerValue),
        shrinker = convertShrinker(arbitraryOfInnerValue.shrinker, fromInnerValue, toInnerValue),
    }
end

local function nilGenerator() return nil end

--- Arbitrary of nil
---@type Arbitrary<nil>
local nilArb = {
    name = "nil",
    generator = nilGenerator,
    shrinker = emptyShrinker,
}

local function integerShrinker(n) return wrap(function ()
    if n == 0 then return end

    if n < 0 then yield(math.abs(n)) end
    yield(0)

    local i = n
    while true do
        i = modf(i / 2)
        local m = n - i
        if m < n then yield(m) else return end
    end
end)
end

local function integerGenerator(minValue, maxValue)
    return function (size)
        local size = modf(size)
        return math.random(minValue, max(minValue, min(maxValue, size)))
    end
end

--- Arbitrary of 8bit positive integer [0,255]
---@type Arbitrary<integer>
local byteArb = {
    name = "byte",
    -- TODO: 可搬性
    generator = integerGenerator(0, 255),
    shrinker = integerShrinker,
}

--- Arbitrary of 53bit integer [-9007199254740992,9007199254740991]
---@type Arbitrary<integer>
local int53 = {
    name = "int53",
    generator = integerGenerator(-9007199254740992, 9007199254740991),
    shrinker = integerShrinker,
}

--- Arbitrary of 32bit integer []
---@type Arbitrary<integer>
local int32 = {
    name = "int32",
    generator = integerGenerator(-2147483648, 2147483647),
    shrinker = integerShrinker,
}

local chars = { ("abc"):byte(1, 3) }
local function charShrinker(x) return wrap(function ()
    for _, c in ipairs(chars) do
        if c < x then yield(c) end
    end
end) end

--- Arbitrary of positive integer [0..127]
---@type Arbitrary<integer>
local charArb = {
    name = "char",
    generator = integerGenerator(0, 127),
    shrinker = charShrinker,
}

---@generic T
---@param itemGenerator fun(size: number): T
local function arrayGenerator(itemGenerator)
    return function (size)
        local result = {}
        local length = math.random(0, max(0, size))
        for i = 1, length do result[i] = itemGenerator(modf(size / 2)) end
        return result
    end
end

---@generic T
---@param x T
---@param xs T[]
---@return T[]
local function consArray(x, xs)
    local result = {}
    result[1] = x
    for i = 1, #xs do result[i + 1] = xs[i] end
    return result
end

---@param itemShrinker fun(x: T): T|nil
---@return fun(x: T[]): T[]|nil
local function arrayShrinker(itemShrinker)

    ---@generic T
    ---@param xs T[]
    ---@return fun(): T|nil
    local function shrinkArray(xs) return wrap(function()
        if #xs == 0 then return end

        local head = xs[1]
        local tail = {}
        for i = 2, #xs do tail[i - 1] = xs[i] end

        yield(tail)

        for smallTail in shrinkArray(tail) do
            yield(consArray(head, smallTail))
        end
        for smallHead in itemShrinker(head) do
            yield(consArray(smallHead, tail))
        end
    end) end

    return shrinkArray
end

--- Arbitrary of array of T
---@generic T
---@param arbitrary Arbitrary<T>
---@return Arbitrary<T[]> arbitraryOfArray
local function arrayArb(arbitrary)
    return {
        name = "array<"..(arbitrary.name or "?")..">",
        generator = arrayGenerator(arbitrary.generator),
        shrinker = arrayShrinker(arbitrary.shrinker),
    }
end

local function codePointsToString(cs)
    return string.char(unpack(cs))
end
local function stringToBytes(s)
    return {string.byte(s, 1, #s)}
end

--- Arbitrary of string ( char array based )
---@type Arbitrary<string>
local stringArb = convertArbitrary(arrayArb(charArb), codePointsToString, stringToBytes, "string")

--- Arbitrary of binary ( byte array based )
---@type Arbitrary<string>
local binaryArb = convertArbitrary(arrayArb(byteArb), codePointsToString, stringToBytes, "binary")

---@class CheckConfig
---@field public minSize integer
---@field public maxSize integer
---@field public maxCount integer
---@field public randomSeed integer|nil
---@field public maxShrinkCount integer
---@field public pretty fun(value: any): string|nil
---@field public printError fun(message: string)
---@field public printNormal fun(message: string)
---@field public onFailure fun()

---@return CheckConfig
local function newDefaultConfig()
    return {
        minSize = 1,
        maxSize = 100,
        maxCount = 100,
        randomSeed = nil,
        maxShrinkCount = 50,
        pretty = pretty,
        printNormal = print,
        printError = print,
        onFailure = Ex.noop,
    }
end
local function newThrowOnFailureConfig()
    local c = newDefaultConfig()
    local errorLines = {}

    function c.printNormal(_) end
    function c.printError(message)
        errorLines[#errorLines+1] = message
    end
    function c.onFailure()
        error(table.concat(errorLines, "\n"))
    end
    return c
end

---@param test fun(value: T): any
---@param value T
---@return boolean success
---@return any error
local function runTest(test, value)
    local ok, result = pcall(test, value)
    if not ok then return ok, result end
    if result == false then return false, "fail like value '"..tostring(result).."'" end
    return true
end

local function findSmallestFailureTest(maxRetry, shrinker, test, failedValue, failedReason)
    local retryCount = 0
    local shrinkCount = 0

    local function find(failedValue, failedReason)
        for smallValue in shrinker(failedValue) do
            if maxRetry < retryCount then return shrinkCount, failedValue, failedReason end

            local ok, reason = runTest(test, smallValue)
            retryCount = retryCount + 1

            if not ok then
                shrinkCount = shrinkCount + 1
                return find(smallValue, reason)
            end
        end
        return shrinkCount, failedValue, failedReason
    end
    return find(failedValue, failedReason)
end

---@generic T
---@param arbitrary Arbitrary<T>
---@param test fun(value: T): any
---@param config CheckConfig|nil
local function check(arbitrary, test, config)
    ---@type CheckConfig
    local d = newDefaultConfig()
    config = config or d

    local minSize = config.minSize or d.minSize
    local maxSize = config.maxSize or d.maxSize
    local maxCount = config.maxCount or d.maxCount
    local printNormal = config.printNormal or d.printNormal
    local printError = config.printError or d.printError
    ---@type integer|nil
    local randomSeed = config.randomSeed or d.randomSeed
    local maxShrinkCount = config.maxShrinkCount or d.maxShrinkCount
    local prettyCore = config.pretty or d.pretty
    local onFailure = config.onFailure or d.onFailure

    local function pp(x) return prettyCore(x) or pretty(x) end
    local function showErrorMessage(seed, testCount, shrinkCount, originalValue, shrinkValue, shrinkReason)
        local shrinkMessage = ""
        if 0 < shrinkCount then shrinkMessage = " ("..tostring(shrinkCount).." shrinks)" end

        printError("failure. after "..tostring(testCount).."tests"..shrinkMessage.." (seed "..tostring(seed)..")")
        printError("original:")
        printError(pp(originalValue))
        if 0 < shrinkCount then
            printError("shrink:")
            printError(pp(shrinkValue))
        end
        printError("reason:")
        printError(pp(shrinkReason))
    end

    local seed = randomSeed or (os.clock() * 1000)
    math.randomseed(seed)

    local testCount = 0
    while testCount <= maxCount do
        local size = minSize + (maxSize - minSize) / maxCount * testCount

        -- ランダム値を生成
        local value = arbitrary.generator(size)

        -- テスト実行
        local ok, reason = runTest(test, value)
        testCount = testCount + 1

        if not ok then

            -- 失敗値を縮小
            local shrinkCount, shrinkValue, shrinkReason = findSmallestFailureTest(maxShrinkCount, arbitrary.shrinker, test, value, reason)

            showErrorMessage(seed, testCount, shrinkCount, value, shrinkValue, shrinkReason)
            onFailure()
            return
        end
    end
    printNormal("ok. passed "..tostring(maxCount).." tests")
end

local function checkThrowOnFailure(arbitrary, test)
    check(arbitrary, test, newThrowOnFailureConfig())
end

return {
    nil_ = nilArb,
    char = charArb,
    byte = byteArb,
    int32 = int32,
    int53 = int53,
    string = stringArb,
    binary = binaryArb,
    array = arrayArb,

    _convertArbitrary = convertArbitrary,

    newDefaultConfig = newDefaultConfig,
    check = check,
    checkThrowOnFailure = checkThrowOnFailure,

    _findSmallestFailureTest = findSmallestFailureTest,
}