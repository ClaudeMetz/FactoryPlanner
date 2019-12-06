require("util")  -- core.lualib
require("lualib.cutil")
require("data.init")
require("ui.listeners")

if devmode then
    Profiler = require("lualib.profiler")
    require("lualib.llog")
end