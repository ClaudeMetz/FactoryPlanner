require("util")  -- core.lualib
require("lualib.cutil")
require("data.init")
require("ui.listeners")

margin_of_error = 1e-8  -- Margin of error for floating point calculations
devmode = true  -- Enables certain conveniences for development
cached_dialogs = {"fp_frame_modal_dialog_product"}  -- Global variable to write down the dialogs that should not be deleted when closed

if devmode then
    Profiler = require("lualib.profiler")
    require("lualib.llog")
end