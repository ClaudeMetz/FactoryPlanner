DEVELOPER_MODE = (debugadapter and debugadapter.tags) and (debugadapter.tags["FP_DEBUG"] == true) or false

MAGIC_NUMBERS = {
    margin_of_error = 1e-6,  -- the margin of error for floating point calculations
    factory_solver_update_delay = 10,  -- ticks between factories being re-solved in the background
    effect_precision = 10000,  -- The multiplier to turn module effects into integers (and back)
    formatting_precision = 4,  -- precision of decimal formatting in tooltips

    -- Shared main interface layout dimensions
    frame_spacing = 12,  -- Spacing between the base frames in the main dialog
    subheader_height = 36,  -- Height of the factory list and production subheaders
    list_width = 300,  -- Width of the factory list
    item_button_size = 40,  -- Size of item box buttons

    -- Shared dialog settings
    blueprint_limit = 8,  -- Maximum number of blueprints allowed per factory
    module_dialog_element_width = 460  -- Width of machine and beacon dialog elements
}

-- Handlers saved in a central location for access via name
GUI_HANDLERS = {}  ---@type table<string, RegisteredGUIHandler>
GLOBAL_HANDLERS = {}  ---@type table<string, function>

lib = require('util.lib')
llog = require("util.llog")

require("ui.event_handler")

---@alias PlayerIndex uint32
---@alias ForceIndex uint8
---@alias VersionString string
---@alias ModToVersion table<string, VersionString>
---@alias AllowedEffects table<string, boolean>
---@alias ItemType string
---@alias ItemName string
---@alias ExportString string


-- Import screenshotter code if its scenario is active
if remote.interfaces["fp_screenshotter"] then
    DEVELOPER_MODE = false
    ---@diagnostic disable-next-line: unresolved-require
    require("scenarios.screenshotter.script")
end
