--- Only available to the fabled [Command Computer](http://www.computercraft.info/wiki/Command_Computer "Command Computer") (itself only available to ops in creative mode, running CC 1.7 or later), the commands API allows your system to directly execute Minecraft commands and gather data from the results.
commands = {}

--- [■](http://www.computercraft.info/wiki/Commands.exec)
--- Executes the specified command, yields until the result is determined, then returns it.
---@return boolean success
---@return table output
---@param command string
function commands.exec(command) end

--- [■](http://www.computercraft.info/wiki/Commands.execAsync)
--- Executes the specified command, but doesn't yield. Queues a "task_complete" event after the command is executed.
---@return number taskID
---@param command string
function commands.execAsync(command) end

--- [■](http://www.computercraft.info/wiki/Commands.list)
--- Returns a numerically indexed table filled with strings representing acceptable commands for commands.exec() / commands.execAsync().
---@return table commands
function commands.list() end

--- [■](http://www.computercraft.info/wiki/Commands.getBlockPosition)
--- Returns the Minecraft world coordinates of the computer running the command.
---@return number x
---@return number y
---@return number z
function commands.getBlockPosition() end

--- [■](http://www.computercraft.info/wiki/Commands.getBlockInfo)
--- Returns a table containing info about the block at the specified world location. Keys are "name" (a string) and "metadata" (a number).
---@return table block info
---@param x number
---@param y number
---@param z number
function commands.getBlockInfo(x, y, z) end

--- [■](http://www.computercraft.info/wiki/Commands.getBlockInfos)
--- Returns a table containing sub-tables with info about the blocks within the specified world locations. Added by CC 1.76
---@return table blocks info
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
function commands.getBlockInfos(x1, y1, z1, x2, y2, z2) end