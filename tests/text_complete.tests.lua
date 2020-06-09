package.path = package.path..";../sources/?.lua"
local Complete = require "text_complete"
local text = Complete.text
local choice = Complete.choice
local sequence = Complete.sequence
local group = Complete.group
local repeat0 = Complete.repeat0
local optional = Complete.optional
local Assert = require "assert"
local tests = {}


local function toTable(ok, isStop, completions, remaining)
    if ok then return { tag = "Complete", isStop = isStop, completions = completions, remaining = remaining } end
    return { tag = "NoMatch" }
end

local function nilIfEmpty(xs) if xs and #xs == 0 then return nil end return xs end
local function complete(xs) return { tag = "Complete", isStop = false; completions = nilIfEmpty(xs), remaining = "" } end
local function stop(xs) return { tag = "Complete", isStop = true; completions = nilIfEmpty(xs), remaining = "" } end
local function remaining(r) return { tag = "Complete", isStop = false; completions = nil, remaining = r } end
local function noMatch() return { tag = "NoMatch" } end

function tests.text()
    Assert.equals(toTable(text "ab" "ab"), complete {})
    Assert.equals(toTable(text "" ""), complete {})
    Assert.equals(toTable(text "ab" ""), complete {"ab"})
    Assert.equals(toTable(text "" "ab"), remaining "ab")
    Assert.equals(toTable(text "ab" "a"), complete {"b"})
    Assert.equals(toTable(text "ab" "b"), noMatch())
    Assert.equals(toTable(text "a" "ab"), remaining "b")
    Assert.equals(toTable(text "b" "ab"), noMatch())
end

function tests.choice()
    Assert.equals(toTable(choice(text "a", text "ab") "abc"), remaining "c")
    Assert.equals(toTable(choice(text "a", text "abc") "ab"), complete {"c"})
    Assert.equals(toTable(choice(sequence(group(text "a"), text "x"), sequence(group(text "b"), text "y")) ""), stop {"a","b"})
end

function tests.sequence()
    Assert.equals(toTable(sequence(group(text "a"), group(text "b")) ""), stop {"a"})
    Assert.equals(toTable(sequence(text "ab", text "c") "a"), complete {"bc"})
    Assert.equals(toTable(sequence(text "ab", text "c") "ab"), complete {"c"})
    Assert.equals(toTable(sequence(text "ab", text "cd") "abc"), complete {"d"})

    Assert.equals(toTable(sequence(group(text "a"), text "bc") "ab"), complete {"c"})
end

function tests.repeat0()
    local repeatAB = group(text "ab")
    Assert.equals(toTable(repeat0(repeatAB) ""), stop {"ab"})
    Assert.equals(toTable(repeat0(repeatAB) "a"), stop {"b"})
    Assert.equals(toTable(repeat0(repeatAB) "ab"), stop {})
    Assert.equals(toTable(repeat0(repeatAB) "aba"), stop {"b"})
    Assert.equals(toTable(repeat0(repeatAB) "abab"), stop {})
    Assert.equals(toTable(repeat0(repeatAB) "ababa"), stop {"b"})

end

function tests.sequenceAndRepeat0()
    Assert.equals(toTable(sequence(repeat0(text "a"), text "bc") "ab"), complete {"c"})
end

local space = text " "
local function repeat1(c) return sequence(c, repeat0(c)) end
local trivia = repeat0(space)
local function token(c) return group(sequence(trivia, c)) end
local function t(c) return token(text(c)) end

local direction = choice(t"up", t"down", t"forward", t"back", t"left", t"right")
local count = choice(t"2", t"3", t"4")
local movement = sequence(space, direction, optional(sequence(space, count)))
local go = sequence(t"go", repeat1(movement))
local gorilla = sequence(t"gorilla", t"banana")
local c = choice(go, gorilla)

function tests.commands()
    Assert.equals(toTable(c ""), stop {"go", "gorilla"})
    Assert.equals(toTable(c "g"), stop {"o", "orilla"})
    Assert.equals(toTable(c "go"), stop {"rilla"})
    Assert.equals(toTable(c "go "), stop {"up", "down", "forward", "back", "left", "right" })
    Assert.equals(toTable(c "go r"), stop {"ight"})
    Assert.equals(toTable(c "gor"), stop {"illa"})
    Assert.equals(toTable(c "gorilla b"), stop {"anana"})
end

Assert.runTests(tests)
