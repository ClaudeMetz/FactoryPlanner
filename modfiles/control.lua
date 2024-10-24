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
    left_titlebar_width = 94,  -- Width of the left titlebar buttons
    right_titlebar_width = 154,  -- Width of the right titlebar buttons
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

DEV_EXPORT_STRING = "eNrtWV9v2jAQ/ypTngkjaZk6pL1saqVJmzStjxWKHOdCvdlxZjuoCPHdd05MSYEWQtNCt0g8EPvu/Lv/52TuCZlEU1CaycwbeUE/6J+HXs+Du1wqE+GuBuON5l5MNDiC4UckSDmL8XnQD/Bnnwk1Us1yTrIM1ErUoufpIq52GWhvdDP3MiKsrBsmJp+YAfGeKZn5yGpg/A5lGSZAU8KR6MOg52XSWEYPd34omRS0BCTjX0BNJTBX0ki76CQDxy2UyahPmaIFM8irmcg5Sxkk3sioAvCcWW6pLQSLkwhZZCj7fICHKvhTMAVJtFydewmkLMOVeIZMbnmNKwZuIocmJVwDijUyjzhMgS+PpZxoq89SmUVvU4NCkYwVwg/Phk2gHwI8aBN36UmpoGXQFp+uYR70hw9B3wMwaDhtY9e321tgLA5VjbPJrfEl40/plvKCJc/1SDhs0yXaABEvjjkYHB7/457L5mi59dWGyIryi+Q2o22NcgJTLqWyqL4hpvVysGQr96wulOUl0YF1gmJhmmBxQw6qSGpYNrE48go/ooqcJasVqCH/WZ1tjYuUU1iKTKSFXZoIBYGikBkygdKOPU8Qeuv0WoeMYkHEHCH4jsoPm4BOJZ4VcSZQ1+X5WOULDpGr9NWTfmDU+WLDRd9Lsked5GTS+4gCkZtZpLm08sIVWyXnGmzwrhadARZbYsN5dfuxLtCC1f5VGSk12dfLdjQr02WjGa3c6mvKIKPg54T+Hr+7vCNoZGijQT1yRpOqGVwclKYXp5qldkpoJamb2PbEM/vs5TP7ieCcMjPzK57dSOpMD4ap9UzfFkiNasn5Wi0Z7FtLbOATaufcTZ3dzg4l0zxyhDUNLw40s84Bkr3tW1LXjw1bN2zY0LCfnSlsFd07OxV5ZIDqmuzxmmwTB5YTvjbstStq9b/zYjterCZfnHvTQmWEQpeSb9iZWxp258+D2nD4Btvwc+9K4cZdqVHwkWRKcMZO3vINupuzuzn7H5uzj/1qqxvX2uzwVOZoSp+S+LVbe+fHNv2oDQCvvnTtLEQC+FH7ZNMrQh3wafbIE5rVuh55Aj1SG8wNP1Z7vMtoNxubF9WqcLSUiWlh5/4th0jOEr/c3VWvb0EwSnjdBVeWb3GMWj14mRddIpcYIcovw2SXRWKisVSWFjxWjNwXbMEy230TxThviPv/uVYHJ/cJ8tLCa/x1cUsyPeO73BZpbSo7XvwFHm6Nsw=="


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
