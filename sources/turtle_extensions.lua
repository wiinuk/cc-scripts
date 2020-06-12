local refuel = require "refuel"

local function findItemSlot(predicate)
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and predicate(item, slot) then return slot end
    end
    return false, "item not found"
end

local function selectItem(predicate)
    local slot = findItemSlot(predicate)
    if slot then
        local ok, reason = turtle.select(slot)
        if not ok then return false, reason end
        return true
    end
    return false, "item not found"
end

local function eachItem(action)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then action(item, i) end
    end
end

local function move()
    refuel()
    return turtle.forward()
end

local function moveBack()
    refuel()
    return turtle.back()
end

local function moveUp()
    refuel()
    return turtle.up()
end

local function moveDown()
    refuel()
    return turtle.down()
end

return {
    findItemSlot = findItemSlot,
    selectItem = selectItem,
    eachItem = eachItem,
    move = move,
    moveBack = moveBack,
    moveUp = moveUp,
    moveDown = moveDown,
}
