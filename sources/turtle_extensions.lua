
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

return {
    findItemSlot = findItemSlot,
    selectItem = selectItem,
}
