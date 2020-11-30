local Tex = require "turtle_extensions"
local selectItem = Tex.selectItem
local move = Tex.move
local moveUp = Tex.moveUp
local moveDown = Tex.moveDown
local moveBack = Tex.moveBack


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
local function forwardIsLeaves()
    local ok, info = turtle.inspect()
    return ok and info.name == Leaves
end
local function upIsLeaves()
    local ok, info = turtle.inspectUp()
    return ok and info.name == Leaves
end

local function findAndMoveToLog()
    -- 周りを見回す
    for _ = 1, 4 do
        -- 木を発見した
        if forwardIsLog() then return true end

        -- 草を発見した
        if forwardIsLeaves() then
            -- 進む
            turtle.dig()
            move()

            -- 見回す
            if findAndMoveToLog() then return true end
        end
        turtle.turnRight()
    end
    return false
end

local function digAndMoveForwardLog()
    if not findAndMoveToLog() then return false end
    turtle.dig()

    -- [L]
    -- [^]
    move()
    -- [?][?][?]
    -- [?][^][?]
    return true
end

local function maybeDigLeaves(self)
    return
        self.digTryCount == 0 or
        0.5 < self.digSuccessCount / self.digTryCount
end

local function digAndCountUp(self)
    self.digTryCount = self.digTryCount + 1
    if turtle.dig() then
        self.digSuccessCount = self.digSuccessCount + 1
    end
end
local function forgetDigCountUp(self, n)
    if math.random(1, 3) == 1 then
        self.digTryCount = math.max(0, self.digTryCount - n)
        self.digSuccessCount = math.max(0, self.digSuccessCount - n)
    end
end
local function digLogAndLeaves(self)
    -- [L][L]
    -- [L][^]
    turtle.dig()
    turtle.turnLeft()
    turtle.dig()
    -- [L][ ]
    -- [ ][<]

    if maybeDigLeaves(self) then
        turtle.turnLeft()
        digAndCountUp(self)
        turtle.turnLeft()
        digAndCountUp(self)
        turtle.turnLeft()
    else
        forgetDigCountUp(self, 2)
        turtle.turnRight()
    end
end

local function digNormalTree()
    -- 上に掘っていく
    local upCount = 0
    while upIsLog() do
        turtle.digUp()
        moveUp()
        upCount = upCount + 1
    end

    -- 下に降りる
    for _ = 1, upCount do
        moveDown()
    end

    -- 初期位置より下に掘っていく
    while downIsLog() do
        turtle.digDown()
        moveDown()
    end

    -- 苗があるなら植える
    if selectItem(function (item) return item.name == Sapling end) then
        moveUp()
        turtle.placeDown()
    end
end

local function moveToRightBack()
    local moveRight = 0

    -- 右下に合わせる
    turtle.turnRight()
    if digForwardLog() then
        -- [L][L]
        -- [>][L]
        move()
        -- [L][L]
        -- [ ][>]
        moveRight = 1
    else
        -- [L][L]
        -- [L][>]
    end
    turtle.turnLeft()
    -- [L][L]
    -- [L][^]
    return moveRight
end
local function downToRoot()
    local downCount = 0
    -- 根元に降りる
    while downIsLog() do
        turtle.digDown()
        moveDown()
        downCount = downCount + 1
    end
    return downCount
end
local function digUpAndForwardAndRight(self, downCount)
    digLogAndLeaves(self)
    local upCount = 0
    while 0 < downCount or upIsLog() or upIsLeaves() do
        turtle.digUp()
        moveUp()
        -- 葉も採取
        digLogAndLeaves(self)
        downCount = downCount - 1
        upCount = upCount + 1
    end
    return upCount
end
local function moveToLeftForward()
    move()
    turtle.turnLeft()
    turtle.dig()
    move()
    turtle.turnRight()
end
local function downDig(self, upCount)
    for _ = 1, upCount do
        if maybeDigLeaves(self) then
            -- 葉も採取
            digAndCountUp(self)
            turtle.turnLeft()
            digAndCountUp(self)
            turtle.turnRight()
        else
            forgetDigCountUp(self, 2)
        end
        turtle.digDown()
        moveDown()
    end
end

local function findSimpleHugeSaplingSlot()
    return Tex.findItemSlot(function(item)
        return
            item.name == Sapling and
            treeDamageToIsSimpleHuge[item.damage] and
            4 <= item.count
    end)
end

local function plantSapling()

    -- 植えられる巨木の苗木を持っているなら選択して
    local slot = findSimpleHugeSaplingSlot()

    -- 4か所に植える
    if slot then
        turtle.select(slot)

        moveUp()
        turtle.placeDown()
        moveBack()
        turtle.placeDown()
        turtle.turnRight()
        move()
        turtle.turnLeft()
        turtle.placeDown()
        move()
        turtle.placeDown()
        return true
    end
    return false
end
local function moveToInitialPosition(rightCount, downCount)
    for _ = 1, downCount do
        moveUp()
    end
    local moveRight = -rightCount + 1
    if 0 < moveRight then
        turtle.turnRight()
        for _ = 1, moveRight do
            move()
        end
        turtle.turnLeft()
    end
    if moveRight < 0 then
        turtle.turnLeft()
        for _ = 1, -moveRight do
            move()
        end
        turtle.turnRight()
    end

    turtle.turnRight()
    turtle.turnRight()
    for _ = 1, 2 do
        turtle.dig()
        move()
    end
    turtle.turnRight()
    turtle.turnRight()

    for _ = 1, -downCount do
        turtle.digDown()
        moveDown()
    end
end
local function digHugeTree()
    local self = {
        digTryCount = 0,
        digSuccessCount = 0,
    }
    -- [?][L][?]
    -- [?][^][?]
    local rightCount = moveToRightBack()
    -- [L][L]
    -- [L][^]
    local downCount = downToRoot()

    -- 上と前と左を掘りながら上昇
    local upCount = digUpAndForwardAndRight(self, downCount)

    -- 残った左上の原木の上に移動
    -- [L][ ]
    -- [ ][^]
    moveToLeftForward()
    -- [^][ ]
    -- [ ][ ]

    -- 掘りながら下降
    downDig(self, upCount)

    -- 苗木を植える
    if plantSapling() then
        downCount = downCount - 1
        rightCount = rightCount + 1
    end

    moveToInitialPosition(rightCount, downCount)
end

--- - 掘れる道具を装備している必要がある
--- - 目の前に原木または原木につながる葉がある必要がある
local function digTree()
    if not digAndMoveForwardLog() then return false, "log not found" end

    -- 巨木
    if forwardIsLog() then
        digHugeTree()
    else
        digNormalTree()
    end
end

return {
    findSimpleHugeSaplingSlot = findSimpleHugeSaplingSlot,
    digTree = digTree,
}
