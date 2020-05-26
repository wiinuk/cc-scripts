
--- The Turtle API is used to work with your [Turtles](http://www.computercraft.info/wiki/Turtle).
turtle = {}

--- [■](http://www.computercraft.info/wiki/Turtle.craft)
--- Craft items using ingredients anywhere in the turtle's inventory and place results in the active slot. If a quantity is specified, it will craft only up to that many items, otherwise, it will craft as many of the items as possible.
--- (Min version: 1.4)
--- (Only: Crafty)
---@return boolean success
---@param quantity number
function turtle.craft(quantity) end

--- [■](http://www.computercraft.info/wiki/Turtle.forward)
--- Try to move the turtle forward
---@return boolean success
function turtle.forward() end

--- [■](http://www.computercraft.info/wiki/Turtle.back)
--- Try to move the turtle backward
---@return boolean success
function turtle.back() end

--- [■](http://www.computercraft.info/wiki/Turtle.up)
--- Try to move the turtle up
---@return boolean success
function turtle.up() end

--- [■](http://www.computercraft.info/wiki/Turtle.down)
--- Try to move the turtle down
---@return boolean success
function turtle.down() end

--- [■](http://www.computercraft.info/wiki/Turtle.turnLeft)
--- Turn the turtle left
---@return boolean success
function turtle.turnLeft() end

--- [■](http://www.computercraft.info/wiki/Turtle.turnRight)
--- Turn the turtle right
---@return boolean success
function turtle.turnRight() end

--- [■](http://www.computercraft.info/wiki/Turtle.select)
--- Make the turtle select slot slotNum (1 is top left, 16 (9 in 1.33 and earlier) is bottom right)
---@return boolean success
---@param slotNum number
function turtle.select(slotNum) end

--- [■](http://www.computercraft.info/wiki/Turtle.getSelectedSlot)
--- Indicates the currently selected inventory slot
--- (Min version: 1.6)
---@return number slot
function turtle.getSelectedSlot() end

--- [■](http://www.computercraft.info/wiki/Turtle.getItemCount)
--- Counts how many items are in the currently selected slot or, if specified, slotNum slot
---@return number count
---@param slotNum number
function turtle.getItemCount(slotNum) end

--- [■](http://www.computercraft.info/wiki/Turtle.getItemSpace)
--- Counts how many remaining items you need to fill the stack in the currently selected slot or, if specified, slotNum slot
---@return number count
---@param slotNum number
function turtle.getItemSpace(slotNum) end

--- [■](http://www.computercraft.info/wiki/Turtle.getItemDetail)
--- Returns the ID string, count and damage values of currently selected slot or, if specified, slotNum slot
--- (Min version: 1.64)
---@return table data
---@param slotNum number
function turtle.getItemDetail(slotNum) end

--- [■](http://www.computercraft.info/wiki/Turtle.equipLeft)
--- Attempts to equip an item in the current slot to the turtle's left side, switching the previously equipped item back into the inventory
--- (Min version: 1.6)
---@return boolean success
function turtle.equipLeft() end

--- [■](http://www.computercraft.info/wiki/Turtle.equipRight)
--- Attempts to equip an item in the current slot to the turtle's right side, switching the previously equipped item back into the inventory
--- (Min version: 1.6)
---@return boolean success
function turtle.equipRight() end

--- [■](http://www.computercraft.info/wiki/Turtle.attack)
--- Attacks in front of the turtle.
--- (Min version: 1.4)
--- (Only: AnyTool)
---@return boolean success
---@param toolSide string
function turtle.attack(toolSide) end

--- [■](http://www.computercraft.info/wiki/Turtle.attackUp)
--- Attacks above the turtle.
--- (Min version: 1.4)
--- (Only: AnyTool)
---@return boolean success
---@param toolSide string
function turtle.attackUp(toolSide) end

--- [■](http://www.computercraft.info/wiki/Turtle.attackDown)
--- Attacks under the turtle.
--- (Min version: 1.4)
--- (Only: AnyTool)
---@return boolean success
---@param toolSide string
function turtle.attackDown(toolSide) end

--- [■](http://www.computercraft.info/wiki/Turtle.dig)
--- Breaks the block in front. With hoe: tills the dirt in front of it.
--- (Only: Digging)
---@return boolean success
---@param toolSide string
function turtle.dig(toolSide) end

--- [■](http://www.computercraft.info/wiki/Turtle.digUp)
--- Breaks the block above.
--- (Only: Digging)
---@return boolean success
---@param toolSide string
function turtle.digUp(toolSide) end

--- [■](http://www.computercraft.info/wiki/Turtle.digDown)
--- Breaks the block below. With hoe: tills the dirt beneath the space below it.
--- (Only: Digging)
---@return boolean success
---@param toolSide string
function turtle.digDown(toolSide) end

--- [■](http://www.computercraft.info/wiki/Turtle.place)
--- Places a block of the selected slot in front. Engrave signText on signs if provided. Collects water or lava if the currently selected slot is an empty bucket.
--- (Min version: 1.4)
---@return boolean success
---@param signText string
function turtle.place(signText) end

--- [■](http://www.computercraft.info/wiki/Turtle.placeUp)
--- Places a block of the selected slot above. Collects water or lava if the currently selected slot is an empty bucket.
---@return boolean success
function turtle.placeUp() end

--- [■](http://www.computercraft.info/wiki/Turtle.placeDown)
--- Places a block of the selected slot below. Collects water or lava if the currently selected slot is an empty bucket.
---@return boolean success
function turtle.placeDown() end

--- [■](http://www.computercraft.info/wiki/Turtle.detect)
--- Detects if there is a block in front. Does not detect mobs.
---@return boolean result
function turtle.detect() end

--- [■](http://www.computercraft.info/wiki/Turtle.detectUp)
--- Detects if there is a block above
---@return boolean result
function turtle.detectUp() end

--- [■](http://www.computercraft.info/wiki/Turtle.detectDown)
--- Detects if there is a block below
---@return boolean result
function turtle.detectDown() end

--- [■](http://www.computercraft.info/wiki/Turtle.inspect)
--- Returns the ID string and metadata of the block in front of the Turtle
--- (Min version: 1.64)
---@return boolean success
---@return table data|string error message
function turtle.inspect() end

--- [■](http://www.computercraft.info/wiki/Turtle.inspectUp)
--- Returns the ID string and metadata of the block above the Turtle
--- (Min version: 1.64)
---@return boolean success
---@return table data|string error message
function turtle.inspectUp() end

--- [■](http://www.computercraft.info/wiki/Turtle.inspectDown)
--- Returns the ID string and metadata of the block below the Turtle
--- (Min version: 1.64)
---@return boolean success
---@return table data|string error message
function turtle.inspectDown() end

--- [■](http://www.computercraft.info/wiki/Turtle.compare)
--- Detects if the block in front is the same as the one in the currently selected slot
--- (Min version: 1.31)
---@return boolean result
function turtle.compare() end

--- [■](http://www.computercraft.info/wiki/Turtle.compareUp)
--- Detects if the block above is the same as the one in the currently selected slot
---@return boolean result
function turtle.compareUp() end

--- [■](http://www.computercraft.info/wiki/Turtle.compareDown)
--- Detects if the block below is the same as the one in the currently selected slot
---@return boolean result
function turtle.compareDown() end

--- [■](http://www.computercraft.info/wiki/Turtle.compareTo)
--- Compare the current selected slot and the given slot to see if the items are the same. Returns true if they are the same, false if not.
--- (Min version: 1.4)
---@return boolean result
---@param slot number
function turtle.compareTo(slot) end

--- [■](http://www.computercraft.info/wiki/Turtle.drop)
--- Drops all items in the selected slot, or specified, drops count items.[>= 1.4 only:] If there is a inventory on the side (i.e in front of the turtle) it will try to place into the inventory, returning false if the inventory is full.
---@return boolean success
---@param count number
function turtle.drop(count) end

--- [■](http://www.computercraft.info/wiki/Turtle.dropUp)
--- Drops all items in the selected slot, or specified, drops count items.[>= 1.4 only:] If there is a inventory on the side (i.e above the turtle) it will try to place into the inventory, returning false if the inventory is full.
--- (Min version: 1.4)
---@return boolean success
---@param count number
function turtle.dropUp(count) end

--- [■](http://www.computercraft.info/wiki/Turtle.dropDown)
--- Drops all items in the selected slot, or specified, drops count items.[>= 1.4 only:] If there is a inventory on the side (i.e below the turtle) it will try to place into the inventory, returning false if the inventory is full. If above a furnace, will place item in the top slot.
--- (Min version: 1.4)
---@return boolean success
---@param count number
function turtle.dropDown(count) end

--- [■](http://www.computercraft.info/wiki/Turtle.suck)
--- Picks up an item stack of any number, from the ground or an inventory in front of the turtle, then places it in the selected slot. If the turtle can't pick up the item, the function returns false. amount parameter requires ComputerCraft 1.6 or later.
--- (Min version: 1.4)
---@return boolean success
---@param amount number
function turtle.suck(amount) end

--- [■](http://www.computercraft.info/wiki/Turtle.suckUp)
--- Picks up an item stack of any number, from the ground or an inventory above the turtle, then places it in the selected slot. If the turtle can't pick up the item, the function returns false. amount parameter requires ComputerCraft 1.6 or later.
--- (Min version: 1.4)
---@return boolean success
---@param amount number
function turtle.suckUp(amount) end

--- [■](http://www.computercraft.info/wiki/Turtle.suckDown)
--- Picks up an item stack of any number, from the ground or an inventory below the turtle, then places it in the selected slot. If the turtle can't pick up the item, the function returns false. amount parameter requires ComputerCraft 1.6 or later.
--- (Min version: 1.4)
---@return boolean success
---@param amount number
function turtle.suckDown(amount) end

--- [■](http://www.computercraft.info/wiki/Turtle.refuel)
--- If the current selected slot contains a fuel item, it will consume it to give the turtle the ability to move.Added in 1.4 and is only needed in needfuel mode. If the current slot doesn't contain a fuel item, it returns false. Fuel values for different items can be found at Turtle.refuel#Fuel_Values. If a quantity is specified, it will refuel only up to that many items, otherwise, it will consume all the items in the slot.
--- (Min version: 1.4)
---@return boolean success
---@param quantity number
function turtle.refuel(quantity) end

--- [■](http://www.computercraft.info/wiki/Turtle.getFuelLevel)
--- Returns the current fuel level of the turtle, this is the number of blocks the turtle can move.If turtleNeedFuel = 0 then it returns "unlimited".
--- (Min version: 1.4)
---@return number fuel
function turtle.getFuelLevel() end

--- [■](http://www.computercraft.info/wiki/Turtle.getFuelLimit)
--- Returns the maximum amount of fuel a turtle can store - by default, 20,000 for regular turtles, 100,000 for advanced.If turtleNeedFuel = 0 then it returns "unlimited".
--- (Min version: 1.6)
---@return number|string fuel
function turtle.getFuelLimit() end

--- [■](http://www.computercraft.info/wiki/Turtle.transferTo)
--- Transfers quantity items from the selected slot to slot. If quantity isn't specified, will attempt to transfer everything in the selected slot to slot.
--- (Min version: 1.45)
---@return boolean success
---@param slot number
---@param quantity number
function turtle.transferTo(slot, quantity) end
