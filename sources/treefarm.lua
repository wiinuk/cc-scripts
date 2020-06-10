local refuel = require "refuel"
local Tex = require "turtle_extensions"
local selectItem = Tex.selectItem


local Log = "minecraft:log"
local Sapling = "minecraft:sapling"
local Leaves = "minecraft:leaves"

local treeDamageToIsSimpleHuge = {
    [0] = false, -- オーク
    [1] = true, -- マツ
    [2] = false, -- シラカバ
    [3] = true, -- ジャングル
    [4] = false, -- アカシア
    [5] = true, -- ダークオーク
}
local function inspectIsLog(inspect)
    local ok, info = inspect()
    return ok and info.name == Log and info.state.axis == "y"
end

local function forwardIsLog()
    return inspectIsLog(turtle.inspect)
end
local function digForwardLog()
    if forwardIsLog() then return turtle.dig() end
    return false
end
local function downIsLog()
    return inspectIsLog(turtle.inspectDown)
end
local function upIsLog()
    return inspectIsLog(turtle.inspectUp)
end
local function upIsLeaves()
    local ok, info = turtle.inspectUp()
    return ok and info.name == Leaves
end

local function digAndMoveForwardLog()
    for _ = 1, 4 do
        if forwardIsLog() then break end
        turtle.turnRight()
    end
    if not digForwardLog() then return false end

    -- [L]
    -- [^]
    refuel()
    turtle.forward()
    -- [?][?][?]
    -- [?][^][?]
    return true
end

local function digAround()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnLeft()
end

local function digNormalTree()
    -- 上に掘っていく
    local upCount = 0
    while upIsLog() do
        turtle.digUp()
        refuel()
        turtle.up()
        upCount = upCount + 1
    end

    -- 下に降りる
    for _ = 1, upCount do
        refuel()
        turtle.down()
    end

    -- 初期位置より下に掘っていく
    while downIsLog() do
        turtle.digDown()
        refuel()
        turtle.down()
    end

    -- 苗があるなら植える
    if selectItem(function (item) return item.name == Sapling end) then
        refuel()
        turtle.up()
        turtle.placeDown()
    end
end

local function moveToRightBack()
    -- 右下に合わせる
    turtle.turnRight()
    if digForwardLog() then
        -- [L][L]
        -- [>][L]
        refuel()
        turtle.forward()
        -- [L][L]
        -- [ ][>]
    else
        -- [L][L]
        -- [L][>]
    end
    turtle.turnLeft()

end
local function downToRoot()
    local downCount = 0
    -- 根元に降りる
    while downIsLog() do
        turtle.digDown()
        refuel()
        turtle.down()
        downCount = downCount + 1
    end
    return downCount
end
local function digUpAndForwardAndRight(downCount)
    digAround()
    local upCount = 0
    while 0 < downCount or upIsLog() or upIsLeaves() do
        turtle.digUp()
        refuel()
        turtle.up()
        digAround()
        downCount = downCount - 1
        upCount = upCount + 1
    end
    return upCount
end
local function moveToLeftForward()
    refuel()
    turtle.forward()
    turtle.turnLeft()
    turtle.dig()
    refuel()
    turtle.forward()
    turtle.turnRight()
end
local function downDig(upCount)
    for _ = 1, upCount do
        turtle.digDown()
        refuel()
        turtle.down()
    end
end
local function plantSapling()

    -- 植えられる巨木の苗木を持っているなら選択して
    local selected = selectItem(function(item)
        return
            item.name == Sapling and
            treeDamageToIsSimpleHuge[item.damage] and
            4 <= item.count
    end)

    -- 4か所に植える
    if selected then
        refuel()
        turtle.up()
        turtle.placeDown()
        turtle.back()
        turtle.placeDown()
        turtle.turnRight()
        refuel()
        turtle.forward()
        turtle.turnLeft()
        turtle.placeDown()
        refuel()
        turtle.forward()
        turtle.placeDown()
    end
end
local function digHugeTree()
    -- [?][L][?]
    -- [?][^][?]
    moveToRightBack()
    -- [L][L]
    -- [L][^]
    local downCount = downToRoot()

    -- 上と前と左を掘りながら上昇
    local upCount = digUpAndForwardAndRight(downCount)

    -- 残った左上の原木の上に移動
    -- [L][ ]
    -- [ ][^]
    moveToLeftForward()
    -- [^][ ]
    -- [ ][ ]

    -- 掘りながら下降
    downDig(upCount)

    -- 苗木を植える
    plantSapling()

    -- 邪魔しないように引く
    for _ = 1, 4 do
        refuel()
        turtle.back()
    end

    for _ = 1, 2 do
        refuel()
        turtle.down()
    end

    for _ = 1, 4 do
        turtle.suck()
        turtle.turnRight()
    end
    turtle.suckUp()
end

local function digTree()
    if not digAndMoveForwardLog() then return error("log not found") end

    -- 巨木
    if forwardIsLog() then
        digHugeTree()
    else
        digNormalTree()
    end
end

digTree()

-- digAndMoveForwardLog()
-- moveToRightBack()
-- print(downToRoot())
-- print(digUpAndForwardAndRight(1)) -- 14
-- moveToLeftForward()
-- downDig(14)
-- plantSapling()