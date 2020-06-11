local Arg = require "arg-parser"
local Box3 = require "box3"
local Mex = require "memoried_extensions"
local Tex = require "turtle_extensions"

local DisableDig = true
local DisableAttack = true

local function parseArguments(arguments, options)
    while 0 < #arguments do
        if
            Arg.parseNamedOption(arguments, "left", "l", options, tonumber) or
            Arg.parseNamedOption(arguments, "right", "r", options, tonumber) or
            Arg.parseNamedOption(arguments, "forward", "f", options, tonumber) or
            Arg.parseNamedOption(arguments, "back", "b", options, tonumber) or
            Arg.parseNamedOption(arguments, "up", "u", options, tonumber) or
            Arg.parseNamedOption(arguments, "down", "d", options, tonumber)
            then
        else
            return error("unrecognized argument: "..tostring(arguments[1]))
        end
    end
    return true
end

local args = {...}
local options = {}
if #args == 0 then options = { right = 2, forward = 3 } end
if not parseArguments(args, options) then return end

local range = Box3.newFromPoint(0, -1, 0)
if options.left then Box3.expandByPoint(range, -(options.left - 1), -1, 0) end
if options.right then Box3.expandByPoint(range, options.right - 1, -1, 0) end
if options.forward then Box3.expandByPoint(range, 0, -1, options.forward - 1) end
if options.back then Box3.expandByPoint(range, 0, -1, -(options.back - 1)) end
if options.up then Box3.expandByPoint(range, 0, -1 + (options.up - 1), 0) end
if options.down then Box3.expandByPoint(range, 0, -1 - (options.down - 1), 0) end

local function getPlaceItemSlot()

    -- 現在選んでいるのが置くブロック
    local placeItem = turtle.getItemDetail()
    if placeItem then return turtle.getSelectedSlot() end

    -- アイテムがあるスロットが1つしかないならそれが置くブロック
    local slots = {}
    Tex.eachItem(function(_, slot) slots[#slots+1] = slot end)
    if 1 == #slots then return slots[1] end

    -- 選択してもらう
    local slot = nil
    repeat
        print("slot number (empty is quit):")
        local slotNumbers = {}
        for slot = 16, 1, -1 do slotNumbers[#slotNumbers+1] = tostring(slot) end
        local input = read(nil, slotNumbers)
        if input == "" then return false end

        local s = tonumber(input)
        if not s then
            print("input is not number")
        elseif not (1 <= s and s <= 16) then
            print("out of range")
        elseif not (0 < turtle.getItemCount(s)) then
            print("slot is empty")
        else
            slot = s
        end
    until slot

    return slot
end

local placeItemSlot = getPlaceItemSlot()
if not placeItemSlot then return end

turtle.select(placeItemSlot)
local placeItem = turtle.getItemDetail(placeItemSlot)

while true do
    print("# range")
    print("- min", range.minX, range.minY, range.minZ)
    print("- max", range.maxX, range.maxY, range.maxZ)
    print("# block")
    print(placeItem.name)
    print("ok? (yes/no)")

    local input = read()
    if input:sub(1,1):lower() == "y" then break end
    if input:sub(1,1):lower() == "n" then return error "canceled" end
end

-- 開始地点の左手前下まで移動
local ok, reason = Mex.mineTo(1, range.minX, range.minY + 1, range.minZ, DisableDig, DisableAttack)
if not ok then return error(reason) end

local function selectPlaceItem()
    return Tex.selectItem(function (item) return item.name == placeItem.name and item.damage == placeItem.damage end)
end

local function moveAndPlace(bx, by, bz)
    local ok, reason = Mex.mineTo(1, bx, by + 1, bz, DisableDig, DisableAttack)
    if not ok then return error(reason) end
    if not selectPlaceItem() then
        print("please put "..placeItem.name.." in inventory")
        while not selectPlaceItem() do os.sleep(0) end
    end
    turtle.placeDown()
end

for y = range.minY, range.maxY do
    for x = range.minX, range.maxX, 2 do
        for z = range.minZ, range.maxZ do
            moveAndPlace(x, y, z)
        end
        for z = range.maxZ, range.minZ, -1 do
            moveAndPlace(x + 1, y, z)
        end
    end
end

print("finished")
