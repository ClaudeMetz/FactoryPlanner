-- As functions can't be stored in global, references to them can't be stored in modal_data
-- for some of the mod's generic interfaces. Instead, a name needs to be passed, and the
-- function needs to be stored (on file parse) in one of these tables.
NTH_TICK_HANDLERS = {}
GENERIC_HANDLERS = {}
SEARCH_HANDLERS = {}
TUTORIAL_TOOLTIPS = {}

DEVMODE = true  -- enables certain conveniences for development
MARGIN_OF_ERROR = 1e-6  -- the margin of error for floating point calculations
EFFECTS_LOWER_BOUND, EFFECTS_UPPER_BOUND = -0.8, 327.67  -- no magic numbers
TIMESCALE_MAP = {[1] = "second", [60] = "minute", [3600] = "hour"}
SUBFACTORY_DELETION_DELAY = 15 * 60 * 60 -- ticks to deletion after subfactory trashing
MODAL_SEARCH_LIMITING = 10  -- ticks between modal search runs
RECIPEBOOK_API_VERSION = 4  -- the API version of Recipe Book this mod works with
NEW = nil  -- global variable used to store new prototype data temporarily for migration

local active_mods = script.active_mods
RECIPEBOOK_ACTIVE = (active_mods["RecipeBook"] ~= nil)
BEACON_OVERLOAD_ACTIVE = (
    active_mods["space-exploration"]
    or active_mods["wret-beacon-rebalance-mod"]
    or active_mods["beacon-overhaul"]
) and true


require("util")  -- core.lualib
fancytable = require('__flib__.table')  -- has more functionality than built-in table
translator = require("__flib__.dictionary-lite")  -- translation module for localised search

require("data.init")
require("data.data_util")

require("ui.ui_util")
require("ui.base.main_dialog")
require("ui.base.compact_dialog")
require("ui.base.modal_dialog")
require("ui.event_handler")


-- Some magic numbers to determine and calculate the dimensions of the main dialog
FRAME_SPACING = 12

TITLE_BAR_HEIGHT = 28
SUBFACTORY_SUBHEADER_HEIGHT = 36
SUBFACTORY_LIST_ELEMENT_HEIGHT = 28
SUBFACTORY_INFO_HEIGHT = 138

SUBFACTORY_LIST_WIDTH = 300
ITEM_BOX_BUTTON_SIZE = 40
ITEM_BOX_MAX_ROWS = 5
-- The following must remain 12, otherwise the scrollbar will not fit
-- The scroll pane style used for the item boxes is hardcoded at 12 for this reason
ITEM_BOX_PADDING = 12

PICKER_ITEM_COLUMN_COUNT = 10
PICKER_GROUP_COUNT = 6
UTILITY_BLUEPRINT_LIMIT = 12
MODULE_DIALOG_WIDTH = 460

TUTORIAL_EXPORT_STRING = "eNrtGdtq2zD0V4ae4y7OutEF9rKxwmCDsT6WYmT5ONUmWZokh4bgf9+RLScmSUncpk3LDHmwj879LmdJpMqSORjLVUGmJD6Lz84nZETgTivjEjy14Mh0SVJqISC8/4gIueApvo/PYvz5d8qcMgstaFGAWbOqRsSWaXPKwZLp9ZIUVHpe11zOPnEH8q02KiuZQx0iyzgUDCJN2Z+bN1/vqNQCkL/jEiyj+Dz9MB6RQjnPjODJz4bYK6nS38BcIwR5OuWBQdo9MpCB5SiD5xwyMnWmBBS20J7E6+YNoFKVBQqIL1Cygb8lN5AlLXRJMsh5gZB0gUQBvEGVgnBJUCmnwgKydUonAuYgWrFMUOuNai2qbkbBpKQ9+uZVWmN+UUJAbRQJDHOhlPFKfUeVNn3SktVnTWB6oBtgXNdIj/Etow5mmClIxgzNHS9mXvc1iyR4v4FAx9pfjQI+Iog5h5ZlprzutVuRERgGhaMzBMVjdL2k7DYYt6k3sgWZClQhCljRuz5K5wplJYJL7lbysWRKAUkom+bNHpqcc+4WUUOzX5MuUTdNz9ce+1Gz2pVI4eS+VApWsBVHkNotEiuUt2C8KeEKra06wODyyic+Zb61bNscTvYYmeskIHYsvHigm60GyA72b43dFTs5umMnPR37ObiiGvWoTkO5eI2lOHn6UlxWj4vfeCN+k0MLo1cAufGN1fHn7qjN8xDF40QRvHzDWZSXpqB1GIaSfK3B3DGwh3g+aAxPXuEYXufMtuCQOrvFhnW/Y8FlvYD3Sz6azSnu2FnEuGEld8OePezZw5598j27GfCqwBF/ksIc1rVjTnimNLoyYjR97tE+xPGYcbQOQERaoOV7G5EEcdI52feK0FX4Zc7IF7SrDTPyBcxI67A2otQc8C3juNXYv6k2jeNIlZiXfu/fIUQJnkX16b5+fQuSMyq6Ibj0dNUpevX4aT50Sa0wQ0xUp8k+j6TUYqusPXiqHFk1bMkLP30zw4Xoqff/c62On/haHW9dq9eAq/ZPSBxPN9U/38n8Xw=="


if DEVMODE then
    llog = require("llog")
    LLOG_EXCLUDES = {}

    DEV_EXPORT_STRING = "eNrtWV9v2jAQ/ypTngkjaZk6pL1saqVJmzStjxWKHOdCvdlxZjuoCPHdd05MSYEWQtNCt0g8EPvu/Lv/52TuCZlEU1CaycwbeUE/6J+HXs+Du1wqE+GuBuON5l5MNDiC4UckSDmL8XnQD/Bnnwk1Us1yTrIM1ErUoufpIq52GWhvdDP3MiKsrBsmJp+YAfGeKZn5yGpg/A5lGSZAU8KR6MOg52XSWEYPd34omRS0BCTjX0BNJTBX0ki76CQDxy2UyahPmaIFM8irmcg5Sxkk3sioAvCcWW6pLQSLkwhZZCj7fICHKvhTMAVJtFydewmkLMOVeIZMbnmNKwZuIocmJVwDijUyjzhMgS+PpZxoq89SmUVvU4NCkYwVwg/Phk2gHwI8aBN36UmpoGXQFp+uYR70hw9B3wMwaDhtY9e321tgLA5VjbPJrfEl40/plvKCJc/1SDhs0yXaABEvjjkYHB7/457L5mi59dWGyIryi+Q2o22NcgJTLqWyqL4hpvVysGQr96wulOUl0YF1gmJhmmBxQw6qSGpYNrE48go/ooqcJasVqCH/WZ1tjYuUU1iKTKSFXZoIBYGikBkygdKOPU8Qeuv0WoeMYkHEHCH4jsoPm4BOJZ4VcSZQ1+X5WOULDpGr9NWTfmDU+WLDRd9Lsked5GTS+4gCkZtZpLm08sIVWyXnGmzwrhadARZbYsN5dfuxLtCC1f5VGSk12dfLdjQr02WjGa3c6mvKIKPg54T+Hr+7vCNoZGijQT1yRpOqGVwclKYXp5qldkpoJamb2PbEM/vs5TP7ieCcMjPzK57dSOpMD4ap9UzfFkiNasn5Wi0Z7FtLbOATaufcTZ3dzg4l0zxyhDUNLw40s84Bkr3tW1LXjw1bN2zY0LCfnSlsFd07OxV5ZIDqmuzxmmwTB5YTvjbstStq9b/zYjterCZfnHvTQmWEQpeSb9iZWxp258+D2nD4Btvwc+9K4cZdqVHwkWRKcMZO3vINupuzuzn7H5uzj/1qqxvX2uzwVOZoSp+S+LVbe+fHNv2oDQCvvnTtLEQC+FH7ZNMrQh3wafbIE5rVuh55Aj1SG8wNP1Z7vMtoNxubF9WqcLSUiWlh5/4th0jOEr/c3VWvb0EwSnjdBVeWb3GMWj14mRddIpcYIcovw2SXRWKisVSWFjxWjNwXbMEy230TxThviPv/uVYHJ/cJ8tLCa/x1cUsyPeO73BZpbSo7XvwFHm6Nsw=="
end


---@class Event
---@field name defines.events
---@field tick uint

---@class GuiEvent : Event
---@field player_index uint

---@alias Timescale 1 | 60 | 3600
