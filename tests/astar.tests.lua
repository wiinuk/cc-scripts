package.path = package.path..";../sources/?.lua"
local AStar = require "aStar"
local Assert = require "assert"
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
local function isWall(x, y, z)
    if z ~= 0 then return true end
    if x < 0 or 4 < x then return true end
    if y < 0 or 4 < y then return true end
    return map[y+1][x+1] == 1
end
function tests.findPathSimple()
    local path = AStar.findPath(isWall, 1,1,0, 1,2,0)
    Assert.equals(path, { 1,1,0, 1,2,0 })
end

function tests.findPath()
    local path = AStar.findPath(isWall, 1,1,0, 4,4,0)
    Assert.equals(path, { 1,1,0, 1,2,0, 0,2,0, 0,3,0, 0,4,0, 1,4,0, 2,4,0, 3,4,0, 4,4,0, })
end

Assert.runTests(tests)
