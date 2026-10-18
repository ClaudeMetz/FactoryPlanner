DEVELOPER_MODE = (debugadapter and debugadapter.tags) and (debugadapter.tags["FP_DEBUG"] == true) or false

MAGIC_NUMBERS = {
    margin_of_error = 1e-6,  -- the margin of error for floating point calculations
    factory_deletion_delay = 15 * 60 * 60,  -- ticks to deletion after factory trashing
    factory_solver_update_delay = 10,  -- ticks between factories being re-solved in the background
    modal_search_rate_limit = 10,  -- ticks between modal search runs
    effect_precision = 10000,  -- The multiplier to turn module effects into integers (and back)
    formatting_precision = 4,  -- precision of decimal formatting in tooltips
    history_limit = 25,  -- maximum number of navigation history entries

    -- Solver-specific magic numbers
    minimum_energy = 0.001,  -- The lower-bound of the recipe energy property
    matrix_tolerance = 1e-12,  -- The tolerance value for the RREF pivot check
    simplex_tolerance = 1e-10,  -- The tolerance for the variable entering/exitting comparisons
    simplex_update_threshold = 1e5,  -- The infinite norm threshold under which a Forrest-Tomlin update is considered stable
    simplex_max_factorization_interval = 50,  -- The upper bound for the amount of iterations between refactorizations

    -- Shared main interface layout dimensions
    frame_spacing = 12,  -- Spacing between the base frames in the main dialog
    subheader_height = 36,  -- Height of the factory list and production subheaders
    list_width = 300,  -- Width of the factory list
    item_button_size = 40,  -- Size of item box buttons

    -- Various other UI-related magic numbers
    recipes_per_row = 6,  -- Number of recipes per row in the recipe picker
    items_per_row = 10,  -- Number of items per row in the item picker
    groups_per_row = 6,  -- Number of groups in a row in the item picker
    group_max_rows = 3,  -- Maximum number of group rows shown in the item picker before scrolling
    blueprint_limit = 8,  -- Maximum number of blueprints allowed per factory
    module_dialog_element_width = 460,  -- Width of machine and beacon dialog elements
    titlebar_label_width = 130,  -- Width of the 'Factory Planner' titlebar label
    context_menu_width = 310  -- total width of the context menu
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


-- Import test code to run within the mod's context
if script.active_mods["factoryplanner-test"] then
    ---@diagnostic disable-next-line: unresolved-require
    test_runner = require("__factoryplanner-test__.runner")
end

-- Import screenshotter code if its scenario is active
if remote.interfaces["fp_screenshotter"] then
    DEVELOPER_MODE = false
    ---@diagnostic disable-next-line: unresolved-require
    require("scenarios.screenshotter.script")
end
