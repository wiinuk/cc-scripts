local Json = require("json")

--- アイテムを空中に捨てる
---@param amount number
---@return boolean success
local function dropToAir(amount)
    if not turtle.detect() then return turtle.drop(amount) end
    if not turtle.detectDown() then return turtle.dropDown(amount) end
    if not turtle.detectUp() then return turtle.dropDown(amount) end
    return false
end

--- 空のスロットを選択する。
---@return boolean success
local function selectEmptySlot()

    -- 現在のスロットが空なら終わり
    if turtle.getItemCount() == 0 then return true end

    -- 空きスロットを検索
    for i = 16, 1, -1 do
        if turtle.getItemCount(i) == 0 then
            if turtle.select(i) then return true end
        end
    end
    return false
end

-- 80

---@param count number
local function turnRightN(count)
    for i = 1, count do if turtle.turnRight() then return false end end
    return true
end

local function refuelFromTouchingChest(quantity)
    ---@param suck function
    ---@param quantity number
    local function refuelOrReturn(suck, quantity)
        local ok, error = suck(quantity)

        -- 取れたか
        if not ok then return false end

        -- 食べれた
        if turtle.refuel(quantity) then return true end

        -- 食べれなかったので元の場所に戻す
        turtle.drop(turtle.getItemCount())
        return false
    end

    if turtle.getFuelLimit() <= turtle.getFuelLevel() then return true end

    -- 空きスロットを選ぶ
    if not selectEmptySlot() then
        -- 空きスロットがなかったので、アイテムを捨てる
        if not (turtle.select(16) and dropToAir()) then return false end
    end

    -- 回転しないで検索するのを優先する
    if refuelOrReturn(turtle.suck, quantity) then return true end
    if refuelOrReturn(turtle.suckUp, quantity) then return true end
    if refuelOrReturn(turtle.suckDown, quantity) then return true end

    -- 残り3方向から検索
    for i = 0, 2 do
        if not turtle.turnLeft() then return false end
        if refuelOrReturn(turtle.suck, quantity) then return true end
    end
    return false
end

for i = 1, 100 do
    print("nenryou... (", i, ")")
    print(refuelFromTouchingChest(1))
    os.sleep(1)
end
