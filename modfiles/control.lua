require("util")  -- core.lualib
require("lualib.cutil")
require("data.init")
require("ui.listeners")

margin_of_error = 1e-8  -- Margin of error for floating point calculations
--devmode = true  -- Enables certain conveniences for development

-- This is no longer in use, as it can't be done well at the moment
--cached_dialogs = {}  -- Dialogs that should be cached when closed

if devmode then
    require("lualib.llog")
    llog_excludes = {parent=true, type=true, category=true, subfloor=true, origin_line=true, tooltip=true,
      localised_name=true}
end