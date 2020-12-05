package.path = package.path..";./libraries/?.lua"
local core = require "refuel-core"
return core.waitUntilRefueled
