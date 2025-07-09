local active_mods = script.active_mods

SPACE_TRAVEL = script.feature_flags["space_travel"]
DEBUGGER_ACTIVE = (active_mods["debugadapter"] ~= nil)
DEV_ACTIVE = true  -- enables certain conveniences for development
llog = require("util.llog")

MAGIC_NUMBERS = {
    margin_of_error = 1e-6,  -- the margin of error for floating point calculations
    factory_deletion_delay = 15 * 60 * 60,  -- ticks to deletion after factory trashing
    modal_search_rate_limit = 10,  -- ticks between modal search runs

    -- Some magic numbers to determine and calculate the dimensions of the main dialog
    frame_spacing = 12,  -- Spacing between the base frames in the main dialog
    title_bar_height = 28,  -- Height of the main dialog title bar
    district_info_height = 36,
    subheader_height = 36,  -- Height of the factory list subheader
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
    context_menu_width = 270  -- total width of the context menu
}

CUSTOM_EVENTS = {
    open_modal_dialog = script.generate_event_name(),
    close_modal_dialog = script.generate_event_name(),
    build_gui_element = script.generate_event_name(),
    refresh_gui_element = script.generate_event_name()
}

-- Handlers saved in a central location for access via name
MODIFIER_ACTIONS = {}  ---@type ActionTable
GLOBAL_HANDLERS = {}  ---@type { [string]: function }

PRODUCTS_PER_ROW_OPTIONS = {5, 6, 7, 8, 9, 10}
FACTORY_LIST_ROWS_OPTIONS = {20, 22, 24, 26, 28, 30, 32}
COMPACT_WIDTH_PERCENTAGE = {20, 22, 24, 26, 28, 30, 32, 34, 36}

TIMESCALE_MAP = {[1] = "second", [60] = "minute"}
BLANK_EFFECTS = {speed = 0, productivity = 0, quality = 0, consumption = 0, pollution = 0}


ftable = require("__flib__.table")  -- has more functionality than built-in table
translator = require("__flib__.dictionary")  -- translation module for localised search

util = require("util.util")

require("ui.base.main_dialog")
require("ui.base.compact_dialog")
require("ui.base.modal_dialog")

require("backend.init")
require("ui.event_handler")

DEV_EXPORT_STRING = "eNrdVkuPnDAM/i85DyMew/PYQ0+tVKnHaoRCMLNRE8KGsO1oxH+vA8wUmJ3VrratdssJG3+2P9sxORH42ShtcqnKFgzJTqSgLZCM+Ft368VkQ0oougMtaWNAT/oA1SDggRooHU25aOeASvACZZSirYvyfUcFN8eFCWVG6WMjaF1fvHrWuG0oA4ceZin0Z3sOGOfbiTBBWxvx4+gFUTWVFvCBtpyhWIgOGs1rg1YnhNfKWCjBT41WZccMf8CM8kLVfLSY1Ev/X0bliDLKFmcKhOSZ0YhmDuOaddwaMSzHweaTEW5A2tJRQ3NzbGBStZYgl43gFYeSZEZ30NsKV7yGMi8slErV1dadhvuOa1RPmszbRssnTkI3dXdhmEau60VRGke70EviII5TP42SOOw3z2HDkYlzAKqdH3cA4h9QcbdJsHxSP9yFvh+nieu6SbBLEt8P0yBKkjTaJbsAuew3xKgmr4RS2mZ/GYNBsSE4kJh85uEb5rBs5SfUDIkw3kD+rHbOGY+4G5zPI6Xqs/mosQFLhXGziooWNoTauYMRhzDQDGozjLrnuhsiKbuzac6ofZ5U1z3D7yALJHpwJpwTLBv3m1S7YjMBbtCZjutVkWqlJRUrV6Mxv+WrUsgxF1xiRSfauGg6Afm0bC5EB+1XsIUfLZb9G78/dhKrijMONTs6I87xV2W4GKyrMIX560U4D73f73sUmZISrEzI/Hg+PaHDEcV1aeDNT2Zr0LNTdbqmQ6BZL1oJwuDIvqV5rDq7NGbbpBs24DoaU3S1GNkdSM6uMrD+Ho3ev2j2T/0Ts7LaeP7LN971yn93685btUPT6q3N1p/q93+zG8Z/Ev5m3816eFUL98PGf+rCihfg76+8sFrpZfcim+i+/wV3PxDb"


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
