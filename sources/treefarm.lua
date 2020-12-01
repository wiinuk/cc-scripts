package.path = package.path..";./libraries/?.lua"

local Tex = require "turtle_extensions"
local Tree = require "tree-core"
local Memoried = require "memoried"
local Mex = require "memoried_extensions"
local Logger = require "logger"

local Log = "minecraft:log"
local Leaves = "minecraft:leaves"
local Sapling = "minecraft:sapling"
local Dye = "minecraft:dye"


---@class WorkState
---@field public sleepSeconds number

---@param work fun(self: WorkState): boolean|"break"|nil, any, any
---@param initialSleepSeconds number
---@param maxSleepSeconds number
---@param minSleepSeconds number
local function sleepLoop(work, initialSleepSeconds, maxSleepSeconds, minSleepSeconds)
    local minSleepSeconds = minSleepSeconds or 0
    local maxSleepSeconds = maxSleepSeconds or 10
    local initialSleepSeconds = math.max(
        minSleepSeconds,
        math.min(
            maxSleepSeconds,
            initialSleepSeconds or 1
        )
    )

    ---@type WorkState
    local self = {
        sleepSeconds = initialSleepSeconds,
    }

    while true do
        local results = {work(self)}
        local changedTheWorld = results[1]
        if changedTheWorld == "break" then
            table.remove(results, 1)
            return unpack(results)
        end

        self.sleepSeconds = changedTheWorld
            and minSleepSeconds
            or (self.sleepSeconds == 0
                and initialSleepSeconds
                or (self.sleepSeconds * 2)
            )

        self.sleepSeconds = math.min(
            self.sleepSeconds,
            maxSleepSeconds
        )
        Logger.logInfo("Sleep for", self.sleepSeconds, "seconds.")
        os.sleep(self.sleepSeconds)
    end
end

local function growForwardTree()
    -- TODO: リトライ回数制限 ( 狭すぎて木が成長しないなど )
    while true do

        -- 目の前が原木か葉なら成功
        local ok, item = Memoried.getOperation(Memoried.Forward).inspect()
        if ok and (item.name == Log or item.name == Leaves) then return true end

        -- 目の前が苗でなければ失敗
        if not ok or item.name ~= Sapling then return false, "The '"..Sapling.."' wasn't in front of me. actual item is "..(ok and item.name or "???").."." end

        -- TODO: クラフトで骨粉を手に入れる
        -- 骨粉を持っていなければ失敗
        local ok = Tex.selectItem(function (item)
            return item.name == Dye and item.damage == 15 -- 骨粉
        end)
        if not ok then return false, "Please have bone meal." end

        -- 骨粉をまく
        Memoried.getOperation(Memoried.Forward).place()
    end
end

local function suckAroundItems()
    local success = false
    for _ = 1, 4 do
        success = success or Memoried.getOperation(Memoried.Right).suck()
    end
    success = success or Memoried.getOperation(Memoried.Up).suck()
    success = success or Memoried.getOperation(Memoried.Down).suck()
    return success
end

local gotoOptions = {
    disableDig = true,
    disableAttack = true,
    isMovable = function(x, y, z)
        if Mex.isMovableInMemory(x, y, z) then return true end

        local cx, cy, cz = Memoried.currentPosition()
        local dx, dy, dz = cx - x, cy - y, cz - z
        local distance = math.abs(dx) + math.abs(dy) + math.abs(dz)

        -- 自分の位置
        if distance == 0 then return true end

        -- 測定するには燃料が必要
        if distance ~= 1 then return true end

        local currentForwardDirection = Memoried.toGlobalDirection(Memoried.Forward)

        local targetGlobalDirection = 0
        if dx < 0 then targetGlobalDirection = Memoried.Right
        elseif 0 < dx then targetGlobalDirection = Memoried.Left
        elseif dy < 0 then targetGlobalDirection = Memoried.Up
        elseif 0 < dy then targetGlobalDirection = Memoried.Down
        elseif dz < 0 then targetGlobalDirection = Memoried.Forward
        elseif 0 < dz then targetGlobalDirection = Memoried.Back
        end
        local detect = Memoried.getOperationAt(targetGlobalDirection).detect()

        Logger.logDebug("check", x, y, z, "is", Memoried.getOperationAt(targetGlobalDirection).name)

        -- 元の方向に戻す
        Memoried.getOperationAt(currentForwardDirection).detect()

        return detect
    end
}

--- 伐採した後、苗が落ちるまで待つ時間
local digCoolDownSeconds = 3 * 60

Logger.addListener(Logger.printListener(Logger.Debug))
Logger.addListener(Logger.fileWriterListener("logs/tree-farm.log"))

local homeGlobalDirection = Memoried.toGlobalDirection(Memoried.Forward)
local cx, cy, cz = Memoried.currentPosition()

local nextDigTreeOsClock = 0
local loopCount = 0
sleepLoop(function ()
    loopCount = loopCount + 1
    Logger.logInfo("main loop", loopCount)

    local changedTheWorld = false

    -- クールダウン後、木が成長しているか確認する
    if nextDigTreeOsClock <= os.clock() then

        -- ホームまで移動
        Mex.goTo(cx, cy, cz, gotoOptions)
        Memoried.getOperationAt(homeGlobalDirection).detect()

        local ok, error = growForwardTree()
        if not ok then
            Logger.logWarning("growForwardTree failure:", error)
        else

            -- 伐採する
            local ok, reason = Tree.digTree()
            if not ok then Logger.logWarning("digTree failure:", ok, reason) end

            changedTheWorld = true
            nextDigTreeOsClock = os.clock() + digCoolDownSeconds

            Logger.logDebug("set next clock:", nextDigTreeOsClock)
            Logger.logInfo("The next felling is at least", digCoolDownSeconds, "seconds later.")
        end
    else
        Logger.logDebug("next clock:", nextDigTreeOsClock, ", current clock:", os.clock())
        Logger.logInfo("Logging will be skipped. The next felling is at least", nextDigTreeOsClock - os.clock(), "seconds later.")
    end

    -- 床まで下がる
    Mex.goTo(cx, cy - 5, cz, gotoOptions) -- 床にぶつかるまで下がるのでエラーハンドリング不要

    -- 周りのアイテムを回収
    local failureCount = 0
    local suckLoopCount = 0
    sleepLoop(function()
        suckLoopCount = suckLoopCount + 1
        Logger.logInfo("suck loop", suckLoopCount)

        if 3 <= failureCount then return "break" end

        local success = suckAroundItems()
        if success then
            changedTheWorld = true
            failureCount = 0
            return true
        end
        failureCount = failureCount + 1
    end)
    return changedTheWorld

end, 1, 30, 0)
