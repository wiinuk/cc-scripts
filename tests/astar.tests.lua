package.path = package.path..";../sources/?.lua"
local AStar = require "aStar"
local Assert = require "assert"
local Checker = require "random_checker"
local tests = {}

local _ = 0
local W = 1
local map = {
    {_,_,_,_,_},
    {_,_,W,_,_},
    {_,_,W,_,W},
    {_,W,W,_,_},
    {_,_,_,_,_},
}
local function isMovable(x, y, z)
    if z ~= 0 then return false end
    if x < 0 or 4 < x then return false end
    if y < 0 or 4 < y then return false end
    return map[y+1][x+1] % 2 == 0
end
function tests.findPathSimple()
    local path = AStar.findPath(isMovable, 1,1,0, 1,2,0)
    Assert.equals(path, { 1,1,0, 1,2,0, })
end

function tests.findPath()
    local path = AStar.findPath(isMovable, 1,1,0, 4,4,0)
    Assert.equals(path, { 1,1,0, 1,2,0, 0,2,0, 0,3,0, 0,4,0, 1,4,0, 2,4,0, 3,4,0, 4,4,0, })
end

function tests.startAndResumeSimple()
    local finder = AStar.newFinder(isMovable)
    local path, state = AStar.start(finder, 1,1,0, 1,2,0)
    Assert.equals({ path = path, state = state }, { path = { 1,1,0, 1,2,0, }, state = "ready" })

    local path, state = AStar.start(finder, 1,1,0, 1,2,0)
    Assert.equals({ path = path, state = state }, { path = { 1,1,0, 1,2,0, }, state = "ready" })
end

function tests.findPathEqualsProperty()
    local mapSize = 5
    local function isMovableFromMap(map)
        return function(x, y, z)
            if z ~= 0 then return false end
            if x < 1 or mapSize < x then return false end
            if y < 1 or mapSize < y then return false end
            local b = map[y][x]
            return (b % 5) / 5 < 0.5
        end
    end
    local function findPathIndex(x, y, z, path)
        if not path then return end

        for i = 1, #path, 3 do
            if x == path[i] and y == path[i+1] and z == path[i+2] then
                return ((i - 1) / 3) + 1
            end
        end
    end
    local function prettyMap(isMovable, startX, startY, goalX, goalY, path)
        local lines ={}
        lines[#lines+1] = "╭"..string.rep("┄", mapSize).."╮"
        for y = 1, mapSize do
            local line = ""
            for x = 1, mapSize do
                local c = " "
                if isMovable(x, y, 0) then
                    if x == startX and y == startY then c = "S"
                    elseif x == goalX and y == goalY then c = "G"
                    else
                        local i = findPathIndex(x, y, 0, path)
                        if i then
                            c = string.sub(string.format("%x", i), 1, 1)
                        end
                    end
                else
                    c = "█"
                end
                line = line..c
            end
            lines[#lines+1] = "┆"..line.."┆"
        end
        lines[#lines+1] = "╰"..string.rep("┄", mapSize).."╯"
        return table.concat(lines, "\n")
    end
    local function deriveStart(isMovable)
        for y = 1, mapSize do
            for x = 1, mapSize do
                if isMovable(x, y, 0) then
                    return x, y
                end
            end
        end
    end
    local function deriveGoal(isMovable, startX, startY)
        for x = mapSize, 1, -1 do
            for y = mapSize, 1, -1 do
                if isMovable(x, y, 0) and x ~= startX and y ~= startY then
                    return x, y
                end
            end
        end
    end
    local function setupMap(map)
        local isMovable = isMovableFromMap(map)

        local startX, startY = deriveStart(isMovable)
        if not startX then return end

        local goalX, goalY = deriveGoal(isMovable, startX, startY)
        if not goalX then return end

        return isMovable, startX, startY, goalX, goalY
    end

    local arb = Checker.fixedLengthArray(Checker.fixedLengthArray(Checker.byte, mapSize), mapSize)
    Checker.checkThrowOnFailure(arb, function (map)
        local isMovable, startX, startY, goalX, goalY = setupMap(map)
        if not isMovable then return print("invalid map") end

        local expected = AStar.findPath(isMovable, startX, startY, 0, goalX, goalY, 0)

        local finder = AStar.newFinder(isMovable)

        local path, state = AStar.start(finder, startX, startY, 0, goalX, goalY, 0, 1)
        while state == "suspended" do
            path, state = AStar.resume(finder, 1)
        end
        Assert.equals(state, "ready")
        Assert.equals(path, expected, "first\n"..prettyMap(isMovable, startX, startY, goalX, goalY, expected))

        local path, state = AStar.start(finder, startX, startY, 0, goalX, goalY, 0, 1)
        while state == "suspended" do
            path, state = AStar.resume(finder, 1)
        end
        Assert.equals(state, "ready")
        Assert.equals(path, expected, "second\n"..prettyMap(isMovable, startX, startY, goalX, goalY, expected))
    end)
end

Assert.runTests(tests)
