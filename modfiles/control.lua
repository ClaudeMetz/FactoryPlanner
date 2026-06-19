SPACE_TRAVEL = script.feature_flags["space_travel"]
DEVELOPER_MODE = (debugadapter and debugadapter.tags) and (debugadapter.tags["FP_DEBUG"] == true) or false
llog = require("util.llog")

MAGIC_NUMBERS = {
    margin_of_error = 1e-6,  -- the margin of error for floating point calculations
    factory_deletion_delay = 15 * 60 * 60,  -- ticks to deletion after factory trashing
    factory_solver_update_delay = 10,  -- ticks between factories being re-solved in the background
    modal_search_rate_limit = 10,  -- ticks between modal search runs
    effect_precision = 10000,  -- The multiplier to turn module effects into integers (and back)
    formatting_precision = 4,  -- precision of decimal formatting in tooltips

    -- Some magic numbers to determine and calculate the dimensions of the main dialog
    frame_spacing = 12,  -- Spacing between the base frames in the main dialog
    title_bar_height = 28,  -- Height of the main dialog title bar
    district_info_height = 36,
    subheader_height = 36,  -- Height of the factory list subheader
    search_footer_height = 36,  -- Height of the factory list search footer
    list_width = 300,  -- Width of the factory list
    list_element_height = 28,  -- Height of an individual factory list element
    item_button_size = 40,  -- Size of item box buttons
    item_box_max_rows = 4,  -- Maximum number of rows in an item box

    -- Various other UI-related magic numbers
    recipes_per_row = 6,  -- Number of recipes per row in the recipe picker
    items_per_row = 10,  -- Number of items per row in the item picker
    groups_per_row = 6,  -- Number of groups in a row in the item picker
    blueprint_limit = 12,  -- Maxmimum number of blueprints allowed per factory
    module_dialog_element_width = 440,  -- Width of machine and beacon dialog elements
    titlebar_label_width = 124,  -- Width of the 'Factory Planner' titlebar label
    context_menu_width = 310  -- total width of the context menu
}

-- Handlers saved in a central location for access via name
MODIFIER_ACTIONS = {}  ---@type ActionTable
GLOBAL_HANDLERS = {}  ---@type { [string]: function }

util = require("util.util")

require("ui.event_handler")


---@class Event
---@field name defines.events
---@field tick Tick

---@class GuiEvent : Event
---@field player_index PlayerIndex

---@alias PlayerIndex uint
---@alias Tick uint
---@alias VersionString string
---@alias ModToVersion { [string]: VersionString }
---@alias AllowedEffects { [string]: boolean }
---@alias ItemType string
---@alias ItemName string
---@alias ExportString string


-- Import test code to run within the mod's context
local test_mods = {"tests-generator", "tests-runtime"}

for _, mod in pairs(test_mods) do
    if script.active_mods[mod] then
        test_runner = require("__" .. mod .. "__.runner")
        break  -- failsafe, one at a time
    end
end

-- Import screenshotter code if its scenario is active
if remote.interfaces["fp_screenshotter"] then
    DEVELOPER_MODE = false
    require("scenarios.screenshotter.script")
end
