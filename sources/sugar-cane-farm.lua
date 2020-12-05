package.path = package.path..";./libraries/?.lua"
local Logger = require "logger"
local Memoried = require "memoried"
local Mex = require "memoried_extensions"
local Names = require "minecraft-names"
local Tex = require "turtle_extensions"
local Vec3 = require "vec3"
local Json = require "json"

local goToOptions = {
    isMovable = function (x, y, z)
        local location = Memoried.getLocation(x, y, z)
        if location == nil then return true end

        return location.move == true or (

            -- ぶつからないで、さらに
            location.detect == false and

            -- 水だと判定されていないなら移動可能
            not (
                location.inspect and
                (
                    location.inspect.name == Names.Water or
                    location.inspect.name == Names.FlowingWater
                )
            )
        )
    end,
    disableDig = true,
    disableMove = function (direction)

        -- 水なら移動不可
        local ok, block = Memoried.getOperationAt(direction).inspect()

        local x, y, z = Memoried.currentPosition()
        local r = ok and (block.name == Names.Water or block.name == Names.FlowingWater)
        Logger.logDebug("disableMove", x, y, z, direction, block and block.name, r)
        return r
    end,
    maxRetryCount = 10,
}

local function updateMemory(direction)
    Memoried.getOperationAt(direction).detect()
    Memoried.getOperationAt(direction).inspect()
end

local directions = {
    Memoried.Forward,
    Memoried.Back,
    Memoried.Up,
    Memoried.Down,
    Memoried.Right,
    Memoried.Left,
}
--- 記憶にない場所は行けるとして、記憶にないブロックにぶつかるなどして移動に失敗したなら周辺情報を収集してリトライする
local function goTo(x, y, z)
    local cx, cy, cz = Memoried.currentPosition()
    Logger.logDebug("goTo start", cx, cy, cz, "->", x, y, z)

    local retryCount = 0
    while true do
        local cx, cy, cz = Memoried.currentPosition()
        local ok, reason = Mex.goTo(x, y, z, goToOptions)
        if ok then
            Logger.logDebug("goTo success")
            return true
        end

        Logger.logDebug("goTo failure[", retryCount, "] @", cx, cy, cz, reason)

        for i = 1, #directions do
            updateMemory(directions[i])
        end
        local ok, reason = Mex.goTo(x, y, z, goToOptions)
        if ok then return true end

        local nx, ny, nz = Memoried.currentPosition()
        if 100 < retryCount or (cx == nx and cy == ny and cz == nz) then
            return false, reason
        end

        Logger.logDebug("goTo retry[", retryCount, "] @", nx, ny, nz, reason)
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

local function managerWithInitialPosition(ix, iy, iz)
    local function recovery(reason)
        Logger.logError("recovering:", reason)
        goTo(ix, iy, iz)
        return error(reason)
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

    return {
        recovery = recovery,
        goToRelativeWithRecovery = function(x, y, z)
            local ok, reason = goToRelative(x, y, z)
            if ok then return end

            return recovery(reason)
        end,

        goToOrRecovery = function(x, y, z)
            local ok, reason = goTo(x, y, z)
            if ok then return end

            return recovery(reason)
        end,

        mineToRelative = mineToRelative,
        mineAround = mineAround,
    }
end

local function initLine(forwardCount)
    local ix, iy, iz = Memoried.currentPosition()
    local manager = managerWithInitialPosition(ix, iy, iz)
    local initialForward = Memoried.toGlobalDirection(Memoried.Forward)
    local initialBack = Memoried.toGlobalDirection(Memoried.Back)
    local initialRight = Memoried.toGlobalDirection(Memoried.Right)
    local initialLeft = Memoried.toGlobalDirection(Memoried.Left)

    local function buildWaterwayBlocks()
        manager.mineAround(Memoried.Down)
        replaceToImperviousBlock(initialBack)
        replaceToGrowableBlock(initialRight)
        replaceToGrowableBlock(initialLeft)
        replaceToImperviousBlock(Memoried.Down)

        for _ = 3, forwardCount do
            manager.mineAround(initialForward)
            replaceToGrowableBlock(initialRight)
            replaceToGrowableBlock(initialLeft)
            replaceToImperviousBlock(Memoried.Down)
        end

        manager.mineAround(initialForward)
        replaceToGrowableBlock(initialRight)
        replaceToGrowableBlock(initialLeft)
        replaceToImperviousBlock(Memoried.Down)
        replaceToImperviousBlock(initialForward)
    end

    local function relativeBackAndPlaceWaterBucket(backCount)
        for _ = 1, backCount do
            manager.mineAround(initialBack)
        end

        waitAddByName(Names.WaterBucket)
        Memoried.getOperationAt(Memoried.Down).place()
    end

    local function relativeForwardAndWaterPump(forwardCount)
        manager.mineToRelative(0, 0, forwardCount)
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
            manager.mineAround(Memoried.Up)
            selectItemByName(Names.Torch)
            Memoried.getOperationAt(initialForward).place()
            manager.mineAround(Memoried.Down)
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
            manager.mineAround(moveDirection)
            placeReedsCore()
        end
    end

    manager.goToRelativeWithRecovery(1, 0, 1)
    buildWaterwayBlocks()

    manager.mineAround(Memoried.Up)

    fillWaterway()

    if findItemSlotByName(Names.Reeds) then
        manager.goToOrRecovery(ix, iy, iz)
        manager.mineAround(Memoried.Up)
        manager.mineAround(initialForward)

        placeReeds(initialForward)
        for _ = 1, 2 do manager.mineAround(initialRight) end
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
    print "  sugar-cane-farm init <forward> <right>"
    print "  sugar-cane-farm"
    print ""
    print "Options:"
    print "  <forward>  The number of sugar cane per row."
    print "  <right>    Number of row."
end

local function initCommand(args)
    if #args < 2 then return showHelp() end

    local forwardCount = tonumber(args[1])
    local lineCount = tonumber(args[2])
    return init(forwardCount, lineCount)
end

local function isChest(direction)
    local ok, block = Memoried.getOperationAt(direction).inspect()
    return ok and block.name == Names.Chest
end

local function findAroundChestInfo()
    local directions = {
        Memoried.Forward,
        Memoried.Left,
        Memoried.Right,
        Memoried.Back,
        Memoried.Down,
        Memoried.Up,
    }
    for _, d in ipairs(directions) do
        if isChest(d) then
            local x, y, z = Memoried.currentPosition()
            return { x = x, y = y, z = z, direction = d }
        end
    end
    return nil
end

local function turnToSugarCane()
    local directions = {
        Memoried.Forward,
        Memoried.Left,
        Memoried.Right,
        Memoried.Back,
    }
    for _, d in ipairs(directions) do
        local ok, block = Memoried.getOperationAt(d).inspect()
        if ok and block.name == Names.Reeds then return d end
    end
    return nil
end

local function onSugarCane()
    local ok, block = Memoried.getOperationAt(Memoried.Down).inspect()
    return ok and block.name == Names.Reeds
end

local function reverseDirection(direction)
    if direction == Memoried.Forward then return Memoried.Back end
    if direction == Memoried.Back then return Memoried.Forward end
    if direction == Memoried.Left then return Memoried.Right end
    if direction == Memoried.Right then return Memoried.Left end
    if direction == Memoried.Up then return Memoried.Down end
    if direction == Memoried.Down then return Memoried.Up end
    return direction
end

local function turnRightDirection(direction)
    if direction == Memoried.Forward then return Memoried.Right end
    if direction == Memoried.Right then return Memoried.Back end
    if direction == Memoried.Back then return Memoried.Left end
    if direction == Memoried.Left then return Memoried.Forward end
    return direction
end

local function turnLeftDirection(direction)
    if direction == Memoried.Forward then return Memoried.Left end
    if direction == Memoried.Left then return Memoried.Back end
    if direction == Memoried.Back then return Memoried.Right end
    if direction == Memoried.Right then return Memoried.Forward end
    return direction
end

local function farm()
    local initialX, initialY, initialZ = Memoried.currentPosition()
    Logger.logInfo("Registered", initialX, initialY, initialZ, "as home.")

    local initialDirection = Memoried.toGlobalDirection(Memoried.Forward)
    local manager = managerWithInitialPosition(initialX, initialY, initialZ)
    local chestInfo = findAroundChestInfo()
    local function logChestInfo()
        if chestInfo then
            Logger.logInfo("I have registered a chest. location:", chestInfo.x, chestInfo.y, chestInfo.z, chestInfo.direction)
        else
            Logger.logInfo "The chest is unregistered."
        end
    end
    logChestInfo()

    local function transferSugarCaneToAroundChest(chestDirection)
        while
            Tex.selectItem(function (item) return item.name == Names.Reeds end) and
            Memoried.getOperationAt(chestDirection).drop()
            do
            Logger.logInfo("Transferred ..'"..Names.Reeds.."' to chest.")
        end
    end

    --- チェストが満杯なら、インベントリに空きができるまでメッセージを表示しつつ待機する
    local function waitUntilFindEmptySlot(chestDirectionOrNil)
        Logger.log "Harvesting was interrupted because there were no empty slots."
        Logger.log "Please make space in inventory."

        repeat
            Tex.compactItems()
            if chestDirectionOrNil then
                transferSugarCaneToAroundChest(chestDirectionOrNil)
            end
            os.sleep(5)
        until Tex.findLastEmptySlot()

        Logger.log "Thank you."
    end

    local function makeInventorySpaceWhenChestIsRegistered()
        Logger.logDebug "Start processing when the chest is registered."

        -- 作物を預ける
        transferSugarCaneToAroundChest(chestInfo.direction)

        if not Tex.findLastEmptySlot() then
            waitUntilFindEmptySlot(chestInfo.direction)
        end

        -- TODO: 燃料をついでに補給する
    end

    --- チェストが登録されていない場合の処理
    --- 現在の場所は限定されない
    local function makeInventorySpaceWhenChestIsNotRegistered()
        Logger.logDebug "Start processing when the chest is not registered."

        -- ホームまで移動する
        Logger.logDebug("Move to", initialX, initialY, initialZ)
        manager.goToOrRecovery(initialX, initialY, initialZ)

        -- チェストを検索する
        chestInfo = findAroundChestInfo()
        logChestInfo()

        if chestInfo then

            -- チェストを発見した
            return makeInventorySpaceWhenChestIsRegistered()
        end

        -- チェストが発見できなかったなら
        Logger.logDebug "Chest is not found."

        -- インベントリに空きができるまでメッセージを表示しつつ待機する
        waitUntilFindEmptySlot(nil)
    end

    --- インベントリに空きスロットがないとき、以下の方法で空きを作る
    --- - 登録してあるチェストに移動して作物を預ける
    --- - ホームに移動してアイテムをプレイヤーに引き取ってもらう
    local function makeInventorySpace()

        -- アイテムに空きがあるなら終わり
        Tex.compactItems()
        if Tex.findLastEmptySlot() then return end

        local returnX, returnY, returnZ = Memoried.currentPosition()

        -- チェストが登録されていない場合
        if not chestInfo then return makeInventorySpaceWhenChestIsNotRegistered() end

        -- チェストが登録されている場合
        -- チェストまで移動する
        Logger.logDebug("Chest is registered. Move to", chestInfo.x, chestInfo.y, chestInfo.z)
        manager.goToOrRecovery(chestInfo.x, chestInfo.y, chestInfo.z)

        local ok, block = Memoried.getOperationAt(chestInfo.direction).inspect()
        if ok and block.name == Names.Chest then
            makeInventorySpaceWhenChestIsRegistered()
        else

            -- チェストがなかった
            Logger.logDebug("Chest is missing.", ok, Json.stringify(block))
            chestInfo = nil
            logChestInfo()

            makeInventorySpaceWhenChestIsNotRegistered()
        end

        -- 元の場所に帰る
        Logger.logDebug("Return to", chestInfo.x, chestInfo.y, chestInfo.z)
        manager.goToOrRecovery(returnX, returnY, returnZ)
        Logger.logDebug "Returned"
    end

    local function farmLine(lineDirection)
        local count = 0
        while true do

            -- TODO: 燃料が足りないときはチェストから補給して元の位置に戻る

            makeInventorySpace()

            manager.mineAround(lineDirection)

            -- 農場の上でないなら農場の上に戻って終わり
            if not onSugarCane() then
                manager.mineAround(reverseDirection(lineDirection))
                return
            end

            count = count + 1
        end
    end

    local function checkAndMoveToNextLine(farmDirection, isRight)
        local turnDirection = isRight and turnRightDirection(farmDirection) or turnLeftDirection(farmDirection)

        -- 横に 1 マス移動
        manager.mineAround(turnDirection)

        -- 農場なら次の方向を返して終わり
        if onSugarCane() then return reverseDirection(farmDirection) end

        -- さらに横に 1 マス移動
        manager.mineAround(turnDirection)

        -- 農場なら次の方向を返して終わり
        if onSugarCane() then return reverseDirection(farmDirection) end

        -- 農場でなかったので元の位置に戻る
        local turnReverseDirection = reverseDirection(turnDirection)
        manager.mineAround(turnReverseDirection)
        manager.mineAround(turnReverseDirection)
        return nil
    end

    local function farmPlane(farmDirection)
        local x, y, z = Memoried.currentPosition()

        farmLine(farmDirection)

        local isRight = true
        while true do
            farmDirection = checkAndMoveToNextLine(farmDirection, isRight)
            if not farmDirection then break end
            isRight = not isRight
            farmLine(farmDirection)
        end

        manager.goToOrRecovery(x, y, z)
    end

    local function checkAndMoveToNextPlane(initialFarmDirection)

        -- 上の階に移動
        manager.mineAround(reverseDirection(initialFarmDirection))
        manager.mineToRelative(0, 4, 0)
        manager.mineAround(initialDirection)

        -- 農場かどうか
        if onSugarCane() then return true end

        -- 農場でなかったので戻る
        manager.mineAround(reverseDirection(initialDirection))
        manager.mineToRelative(0, -4, 0)
        return false
    end

    -- 周りの作物の上に移動して、列の向きを推測する
    local initialFarmDirection = initialDirection
    if not onSugarCane() then
        initialFarmDirection = turnToSugarCane()
        if not initialFarmDirection then
            manager.mineAround(initialDirection)
            if not onSugarCane() then
                Logger.logError("'"..Names.Reeds.."' not found")
                return error()
            else
                initialFarmDirection = initialDirection
            end
        end
        manager.mineAround(initialFarmDirection)
    end

    while true do
        local farmOriginX, farmOriginY, farmOriginZ = Memoried.currentPosition()
        farmPlane(initialFarmDirection)
        while checkAndMoveToNextPlane(initialFarmDirection) do
            farmPlane(initialFarmDirection)
        end
        manager.goToOrRecovery(farmOriginX, farmOriginY, farmOriginZ)
    end
end

local function farmCommand(args)
    if 0 < #args then
        Logger.logError("unrecognized command", args[1])
        showHelp()
        return
    end
    return farm()
end

local function main(args)
    Logger.addListener(Logger.printListener(Logger.Debug))
    Logger.addListener(Logger.fileWriterListener "logs/sugar-cane-farm.log")

    if 1 <= #args and args[1] == "init" then
        local args = {unpack(args)}
        table.remove(args, 1)
        return initCommand(args)
    end

    return farmCommand(args)
end

main {...}
