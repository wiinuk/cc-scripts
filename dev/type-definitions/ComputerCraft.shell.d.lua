--- The shell API allows you to interface with ComputerCraft's shell - [CraftOS](http://www.computercraft.info/wiki/CraftOS "CraftOS"). The shell API is only available when programs are ran from the shell or using [shell.run](http://www.computercraft.info/wiki/Shell.run "Shell.run")/[shell.openTab](http://www.computercraft.info/wiki/Shell.openTab "Shell.openTab").
shell = {}

--- [■](http://www.computercraft.info/wiki/Shell.exit)
--- Exits the current shell.
---@return nil
function shell.exit() end

--- [■](http://www.computercraft.info/wiki/Shell.dir)
--- Returns the path to the working directory.
---@return string directory
function shell.dir() end

--- [■](http://www.computercraft.info/wiki/Shell.setDir)
--- Sets the working directory.
---@return nil
---@param path string
function shell.setDir(path) end

--- [■](http://www.computercraft.info/wiki/Shell.path)
--- Returns the path.
---@return string path
function shell.path() end

--- [■](http://www.computercraft.info/wiki/Shell.setPath)
--- Sets the path.
---@return nil
---@param path string
function shell.setPath(path) end

--- [■](http://www.computercraft.info/wiki/Shell.resolve)
--- Resolves a local path to an absolute path.
---@return string absolutePath
---@param localPath string
function shell.resolve(localPath) end

--- [■](http://www.computercraft.info/wiki/Shell.resolveProgram)
--- Resolves the absolute path to the program whose name you provided.
---@return string absolutePath
---@param name string
function shell.resolveProgram(name) end

--- [■](http://www.computercraft.info/wiki/Shell.aliases)
--- Returns aliases.
---@return table aliases
function shell.aliases() end

--- [■](http://www.computercraft.info/wiki/Shell.setAlias)
--- Sets an alias for program.
---@return nil
---@param alias string
---@param program string
function shell.setAlias(alias, program) end

--- [■](http://www.computercraft.info/wiki/Shell.clearAlias)
--- Clears an alias.
---@return nil
---@param alias string
function shell.clearAlias(alias) end

--- [■](http://www.computercraft.info/wiki/Shell.programs)
--- Returns a table of files in the current directory and in all paths in shell.path.
---@return table programs
---@param showHidden boolean
function shell.programs(showHidden) end

--- [■](http://www.computercraft.info/wiki/Shell.getRunningProgram)
--- Returns the absolute path to the currently-executing program.
---@return string path
function shell.getRunningProgram() end

--- [■](http://www.computercraft.info/wiki/Shell.run)
--- Runs a command (program).
---@return boolean success
---@param command string
---@param args1 string
---@param args2 string
function shell.run(command, args1, args2, ...) end

--- [■](http://www.computercraft.info/wiki/Shell.openTab)
--- Runs a program in another multishell tab. Requires version 1.6 or newer and an advanced system.
---@return number tabID
---@param command string
---@param args1 string
---@param args2 string
function shell.openTab(command, args1, args2, ...) end

--- [■](http://www.computercraft.info/wiki/Shell.switchTab)
--- Switches the multishell tab to tab with the given ID. Requires version 1.6 or newer and an advanced system.
---@return nil
---@param tabID number
function shell.switchTab(tabID) end

--- [■](http://www.computercraft.info/wiki/Shell.complete)
--- Given a partial command line, returns a list of suffixes that could potentially be used to complete it. Requires version 1.74 or newer.
---@return table completionList
---@param prefix string
function shell.complete(prefix) end

--- [■](http://www.computercraft.info/wiki/Shell.completeProgram)
--- Given a partial script / directory path, returns a list of suffixes that could potentially be used to complete it, including alias and path matches. Requires version 1.74 or newer.
---@return table completionList
---@param prefix string
function shell.completeProgram(prefix) end

--- [■](http://www.computercraft.info/wiki/Shell.setCompletionFunction)
--- Registers a function that determines how shell.complete() handles completion behavior for a given script. Requires version 1.74 or newer.
---@return nil
---@param path string
---@param completionFunction function
function shell.setCompletionFunction(path, completionFunction) end

--- [■](http://www.computercraft.info/wiki/Shell.getCompletionInfo)
--- Returns a pointer to the table containing functions registered by shell.setCompletionFunction() for use with shell.complete(). Requires version 1.74 or newer.
---@return table completionFunctions
function shell.getCompletionInfo() end
