package.path = package.path..";./libraries/?.lua"
local Logger = require "logger"
local Memoried = require "memoried"
local Mex = require "memoried_extensions"
local Names = require "minecraft-names"
local Tex = require "turtle_extensions"
local Vec3 = require "vec3"

local goToOptions = {
    isMovable = function (x, y, z)
        Logger.logDebug("Check", x, y, z)

        if Memoried.getLocation(x, y, z) == nil then return true end
        return Mex.isMovableInMemory(x, y, z)
    end,
    disableDig = true,
    maxRetryCount = 10,
}

local function collectMemory(direction)
    local x, y, z = Memoried.currentPosition()
    local cx, cy, cz = Memoried.getOperationAt(direction).currentNormal()
    if Memoried.getLocation(x + cx, y + cy, z + cz) then return end
    Memoried.getOperationAt(direction).detect()
end

--- 記憶にない場所は行けるとして、記憶にないブロックにぶつかるなどして移動に失敗したなら周辺情報を収集してリトライする
local function goTo(x, y, z)
    local retryCount = 0
    while true do
        local cx, cy, cz = Memoried.currentPosition()
        if Mex.goTo(x, y, z, goToOptions) then return true end

        collectMemory(Memoried.Forward)
        collectMemory(Memoried.Back)
        collectMemory(Memoried.Up)
        collectMemory(Memoried.Down)
        collectMemory(Memoried.Right)
        collectMemory(Memoried.Left)
        local ok, reason = Mex.goTo(x, y, z, goToOptions)
        if ok then return true end

        local nx, ny, nz = Memoried.currentPosition()
        if 100 < retryCount or (cx == nx and cy == ny and cz == nz) then
            return false, reason
        end

        Logger.logDebug("goTo failure[", retryCount, "] @", nx, ny, nz, reason)
        retryCount = retryCount + 1
    end
end
local function goToRelative(relativeX, relativeY, relativeZ)
    local x, y, z = Memoried.currentPosition()
    return goTo(x + relativeX, y + relativeY, z + relativeZ)
end


local function dig(globalDirection)
    Memoried.getOperationAt(globalDirection).dig()
end

--- インベントリの空スロットに拾ったアイテムを入れる。
--- 条件に合わなければ捨てる。
--- 拾ったアイテムが入ったスロットは選択される。
local function suckToEmptyItemSlot(localDirection, predicate)

    -- 空スロットを選択
    local slot = Tex.findLastEmptySlot()
    if not slot then return false, "empty slot not found" end
    turtle.select(slot)

    -- アイテムを拾う
    local ok, reason = Memoried.getOperation(localDirection).suck()
    if not ok then return false, reason end

    -- 条件に一致しているなら終わり
    if predicate(turtle.getItemDetail(slot)) then return true end

    -- 一致していないなら捨てる
    local ok, reason = Memoried.getOperation(localDirection).drop()
    if not ok then return false, reason end
    return false, "item did not match the predicate"
end

local function findItemSlotByName(name)
    return Tex.findItemSlot(function (item) return item.name == name end)
end

local function selectItemByName(name)
    return Tex.selectItem(function (item) return item.name == name end)
end

local function waitAdd(message, predicate)
    if Tex.selectItem(predicate) then return end

    Logger.log(message)
    while not Tex.selectItem(predicate) do
        if suckToEmptyItemSlot(Memoried.Up, predicate) then return end
        if suckToEmptyItemSlot(Memoried.Down, predicate) then return end

        for _ = 1, 4 do
            if suckToEmptyItemSlot(Memoried.Right, predicate) then return end
        end
    end
end
local function waitAddByName(name)
    return waitAdd(
        "'"..name.."' is required. Wait for it to be added.",
        function (item) return item.name == name end
    )
end

local function replaceToImperviousBlock(globalDirection)
    local ok, block = Memoried.getOperationAt(globalDirection).inspect()
    if ok and block.name == Names.Dirt then return true end

    waitAddByName(Names.Dirt)
    Memoried.getOperationAt(globalDirection).place()
end

local growableBlockNameSet = {
    [Names.Dirt] = true,
    [Names.Grass] = true,
}
local function replaceToGrowableBlock(globalDirection)
    local ok, data = Memoried.getOperationAt(globalDirection).inspect()
    if ok and data.name == Names.Dirt then return true end

    waitAdd(
        "Growable block is required. Wait for it to be added.",
        function (item) return growableBlockNameSet[item.name] end
    )
    Memoried.getOperationAt(globalDirection).place()
end

local function initLine(forwardCount)
    local ix, iy, iz = Memoried.currentPosition()
    local initialForward = Memoried.toGlobalDirection(Memoried.Forward)
    local initialBack = Memoried.toGlobalDirection(Memoried.Back)
    local initialRight = Memoried.toGlobalDirection(Memoried.Right)
    local initialLeft = Memoried.toGlobalDirection(Memoried.Left)

    local function recovery(reason)
        goTo(ix, iy, iz)
        Logger.logError("goTo failure:", reason)
        return error(reason)
    end

    local function goToRelativeWithRecovery(x, y, z)
        local ok, reason = goToRelative(x, y, z)
        if ok then return end

        return recovery(reason)
    end

    local function goToOrRecovery(x, y, z)
        local ok, reason = goTo(x, y, z)
        if ok then return end

        return recovery(reason)
    end

    local function mineToRelative(relativeX, relativeY, relativeZ)
        local x, y, z = Memoried.currentPosition()
        local ok, reason = Mex.mineTo(5, x + relativeX, y + relativeY, z + relativeZ)
        if ok then return true end

        return recovery(reason)
    end

    --- 指定された方向に、掘って1マス移動する
    ---
    --- ### 早く確実に移動するのが目的
    --- - 周りを見渡す動きがない
    --- - 大事なブロックを壊す可能性がある
    --- - 掘れないブロックもある
    local function mineAround(globalDirection)
        return mineToRelative(Memoried.getOperationAt(globalDirection).currentNormal())
    end

    local function buildWaterwayBlocks()
        mineAround(Memoried.Down)
        replaceToImperviousBlock(initialBack)
        replaceToGrowableBlock(initialRight)
        replaceToGrowableBlock(initialLeft)
        replaceToImperviousBlock(Memoried.Down)

        for _ = 3, forwardCount do
            mineAround(initialForward)
            replaceToGrowableBlock(initialRight)
            replaceToGrowableBlock(initialLeft)
            replaceToImperviousBlock(Memoried.Down)
        end

        mineAround(initialForward)
        replaceToGrowableBlock(initialRight)
        replaceToGrowableBlock(initialLeft)
        replaceToImperviousBlock(Memoried.Down)
        replaceToImperviousBlock(initialForward)
    end

    local function relativeBackAndPlaceWaterBucket(backCount)
        for _ = 1, backCount do
            mineAround(initialBack)
        end

        waitAddByName(Names.WaterBucket)
        Memoried.getOperationAt(Memoried.Down).place()
    end

    local function relativeForwardAndWaterPump(forwardCount)
        mineToRelative(0, 0, forwardCount)
        if selectItemByName(Names.Bucket) then
            Memoried.getOperation(Memoried.Down).place()
        end
    end

    -- f=1 1↓
    -- f=2 1↓ 2↓
    -- f=3 1↓ >< 2↓
    -- f=4 1↓ 3↑ 2↓ 4↓
    -- f=5 1↓ 3↑ 2↓ >< 4↓
    -- f=6 1↓ 3↑ 2↓ 5↑ 4↓ 6↓
    -- f=7 1↓ 3↑ 2↓ 5↑ 4↓ >< 6↓
    local function fillWaterway()
        local lastTorchX, lastTorchY, lastTorchZ = Memoried.currentPosition()
        local function setTorch()
            local x, y, z = Memoried.currentPosition()
            if Vec3.manhattanDistance(lastTorchX, lastTorchY, lastTorchZ, x, y, z) < 5 then return end

            lastTorchX, lastTorchY, lastTorchZ = x, y, z

            if not findItemSlotByName(Names.Torch) then return end
            if not findItemSlotByName(Names.Dirt) then return end

            selectItemByName(Names.Dirt)
            Memoried.getOperationAt(initialForward).place()
            mineAround(Memoried.Up)
            selectItemByName(Names.Torch)
            Memoried.getOperationAt(initialForward).place()
            mineAround(Memoried.Down)
        end

        relativeBackAndPlaceWaterBucket(0)
        if forwardCount <= 1 then return end

        relativeBackAndPlaceWaterBucket(math.min(2, forwardCount - 1))

        for i = 1, math.floor((forwardCount - 2) / 2) do
            relativeForwardAndWaterPump(1)
            setTorch()
            relativeBackAndPlaceWaterBucket(math.min(3 + i * 2, forwardCount) - (i * 2))
        end

        if forwardCount < 3 then return end

        relativeForwardAndWaterPump(1)
        relativeForwardAndWaterPump(0)
        relativeForwardAndWaterPump(0)
    end

    local function placeReeds(moveDirection)
        local function placeReedsCore()
            dig(Memoried.Down)

            -- サトウキビはなくてもいい
            if selectItemByName(Names.Reeds) then
                Memoried.getOperationAt(Memoried.Down).place()
            end

            -- 縦 3マス分の空間を作る
            dig(Memoried.Up)
        end

        placeReedsCore()

        for _ = 2, forwardCount do
            mineAround(moveDirection)
            placeReedsCore()
        end
    end

    goToRelativeWithRecovery(1, 0, 1)
    buildWaterwayBlocks()

    mineAround(Memoried.Up)

    fillWaterway()

    if findItemSlotByName(Names.Reeds) then
        goToOrRecovery(ix, iy, iz)
        mineAround(Memoried.Up)
        mineAround(initialForward)

        placeReeds(initialForward)
        for _ = 1, 2 do mineAround(initialRight) end
        placeReeds(initialBack)
    end
end

local function init(forwardCount, lineCount)
    local initialForward = Memoried.toGlobalDirection(Memoried.Forward)
    for _ = 1, lineCount do
        local x, y, z = Memoried.currentPosition()
        Memoried.getOperationAt(initialForward).detect()
        initLine(forwardCount)
        goTo(x + 3, y, z)
        Memoried.getOperationAt(initialForward).detect()
    end
end

local function showHelp()
    print "Usage:"
    print "  sugar-corn-farm init <forward> <right>"
    print "  "
end

local function initCommand(args)
    if #args < 2 then return showHelp() end

    local forwardCount = tonumber(args[1])
    local lineCount = tonumber(args[2])
    return init(forwardCount, lineCount)
end

local function command(args)
    Logger.addListener(Logger.printListener(Logger.Debug))
    Logger.addListener(Logger.fileWriterListener "logs/sugar-corn-farm.log")

    if #args == 0 then return showHelp() end

    if args[1] == "init" then
        local args = {unpack(args)}
        table.remove(args, 1)
        return initCommand(args)
    end

    Logger.logError("unrecognized command", args[1])
    return
end

command {...}
