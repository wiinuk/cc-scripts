local Cex = require "commands-extensions"

for _ = 1, 3 do
    Cex.exec("kill", "@e[type=!player]")
end
