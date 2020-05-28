--- The FS API allows you to manipulate files and the filesystem.
fs = {}

--- [■](http://www.computercraft.info/wiki/Fs.list)
--- Returns a list of all the files (including subdirectories but not their contents) contained in a directory, as a numerically indexed table.
---@return table files
---@param path string
function fs.list(path) end

--- [■](http://www.computercraft.info/wiki/Fs.exists)
--- Checks if a path refers to an existing file or directory.
---@return boolean exists
---@param path string
function fs.exists(path) local _ = { path } end

--- [■](http://www.computercraft.info/wiki/Fs.isDir)
--- Checks if a path refers to an existing directory.
---@return boolean isDirectory
---@param path string
function fs.isDir(path) end

--- [■](http://www.computercraft.info/wiki/Fs.isReadOnly)
--- Checks if a path is read-only (i.e. cannot be modified).
---@return boolean readonly
---@param path string
function fs.isReadOnly(path) end

--- [■](http://www.computercraft.info/wiki/Fs.getName)
--- Gets the final component of a pathname.
---@return string name
---@param path string
function fs.getName(path) end

--- [■](http://www.computercraft.info/wiki/Fs.getDrive)
--- Gets the storage medium holding a path, or nil if the path does not exist.
---@return string|nil drive
---@param path string
function fs.getDrive(path) end

--- [■](http://www.computercraft.info/wiki/Fs.getSize)
--- Gets the size of a file in bytes.
---@return number size
---@param path string
function fs.getSize(path) end

--- [■](http://www.computercraft.info/wiki/Fs.getFreeSpace)
--- Gets the remaining space on the drive containing the given directory.
---@return number space
---@param path string
function fs.getFreeSpace(path) end

--- [■](http://www.computercraft.info/wiki/Fs.makeDir)
--- Makes a directory.
---@return nil
---@param path string
function fs.makeDir(path) end

--- [■](http://www.computercraft.info/wiki/Fs.move)
--- Moves a file or directory to a new location.
---@return nil
---@param fromPath string
---@param toPath string
function fs.move(fromPath, toPath) end

--- [■](http://www.computercraft.info/wiki/Fs.copy)
--- Copies a file or directory to a new location.
---@return nil
---@param fromPath string
---@param toPath string
function fs.copy(fromPath, toPath) end

--- [■](http://www.computercraft.info/wiki/Fs.delete)
--- Deletes a file or directory.
---@return nil
---@param path string
function fs.delete(path) end

--- [■](http://www.computercraft.info/wiki/Fs.combine)
--- Combines two path components, returning a path consisting of the local path nested inside the base path.
---@return string path
---@param basePath string
---@param localPath string
function fs.combine(basePath, localPath) end

--- [■](http://www.computercraft.info/wiki/Fs.open)
--- Opens a file so it can be read or written.
---@return table handle
---@param path string
---@param mode string
function fs.open(path, mode) end

--- [■](http://www.computercraft.info/wiki/Fs.find)
--- Searches the computer's files using wildcards. Requires version 1.6 or later.
---@return table files
---@param wildcard string
function fs.find(wildcard) end

--- [■](http://www.computercraft.info/wiki/Fs.getDir)
--- Returns the parent directory of path. Requires version 1.63 or later.
---@return string parentDirectory
---@param path string
function fs.getDir(path) end

--- [■](http://www.computercraft.info/wiki/Fs.complete)
--- Returns a list of strings that could be combined with the provided name to produce valid entries in the specified folder. Requires version 1.74 or later.
---@return table matches
---@param partial_name string
---@param path string
---@param include_files boolean
---@param include_slashes boolean
---@overload fun(partial_name: string, path: string, include_files: boolean, include_slashes: boolean): table
function fs.complete(partial_name, path, include_files, include_slashes) end
