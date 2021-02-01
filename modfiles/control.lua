require("util")  -- core.lualib
table = require('__flib__.table')  -- replaces the lua table module

require("data.init")
require("data.data_util")

require("ui.dialogs.main_dialog")
require("ui.dialogs.modal_dialog")
require("ui.ui_util")
require("ui.event_handler")

DEVMODE = false  -- Enables certain conveniences for development
MARGIN_OF_ERROR = 1e-8  -- Margin of error for floating point calculations
TIMESCALE_MAP = {[1] = "second", [60] = "minute", [3600] = "hour"}
SUBFACTORY_DELETION_DELAY = 15 * 60 * 60 -- ticks to deletion after subfactory trashing
NEW = nil  -- global variable used to store new prototype data temporarily for migration

-- Some magic numbers to determine and calculate the dimensions of the main dialog
FRAME_SPACING = 12

TITLE_BAR_HEIGHT = 28
SUBFACTORY_SUBHEADER_HEIGHT = 36
SUBFACTORY_LIST_ELEMENT_HEIGHT = 28
SUBFACTORY_INFO_HEIGHT = 210

SUBFACTORY_LIST_WIDTH = 300
ITEM_BOX_BUTTON_SIZE = 40
ITEM_BOX_MAX_ROWS = 5
-- this must remain as twelve, otherwise the scrollbar will not fit
-- the scroll pane style used for the item boxes is hardcoded at twelve for this reason
ITEM_BOX_PADDING = 12

TUTORIAL_EXPORT_STRING = "eNrtWU2L2zAQ/S8620uSLWXJsaWFQgulPS6LkeVxdlrJUmU5NIT8945smbiJi2MSNps0t2Q0evPmQ5oRXjOls2QJtkRdsDmb3k3vJixiZZXmXDhtEUo2f1yzgiug9Q+/uTISSAOF37BmbmX8AjpQJA1qxuqsEo4w41IgFAJiw8VPtomYQwWl4IQxfzuhDdp5C4z2fm02eVCd/gDhGsuE5bQXDmATaSRumCNkbO5sBdFf5Mi2hV8VWsgSrnRV1JYyyLEgSboivSCO2h/z6cPEU9YmkbAE2cIKyUtPumW8eYoC5aRd+tTEo/37XksJNWkWAHOptfUMPpP9XZ/bbfVak40R6hYEmlrpmNgJ7mChrY+LsDx3WCw89y1EEqLbSKDj7beGAGlTDeESWkgDVkDh+IIk0wllX3HxHPzZpUpIoFJJVuOgFd+P4fnMbZZIVEhpzLksSfML8ZRwaH0t0a1iVW8ZttzdVPsdCujNNijBek+thJV/VUvDIRH7iCF6pJMCD+dx152wMsA/N0lQ7JB/aG334ZYGIDs4PrV2F3u2H5it5F2gsolG1LblKC+kkGenL+T15riymvSU1ajwo/WXisOLuU2uMQngoS2KOK9sweso3lJxnlT0tJH/NxuPA/1jdor+cWRjnfVlfB8zJL4fMUyJHaiP9dw2rnR4tuQ0mmWxQCsqdLfx7DaeXfx41rQmXVBzuqyyvsbmJLShqMSCp/I2I5wvDaUDkLGR5MTgCVUgXzoLY6fJLsfXcb+/zJRwu9/rWtZ0SlN7wAPwOmv5/C9wZTRlwcZ1KoYcTHlJ0Si1xOwseVBY+Os9syjlSK7nenNMew7NYRfY7PVcYPene+ZM9545W8H39gMCufO0+QMKUmaf"

if DEVMODE then
    LLOG_EXCLUDES = {parent=true, subfloor=true, origin_line=true, tooltip=true, localised_name=true}

    DEV_EXPORT_STRING = "eNq1lFFr2zAQx7+Lnu3gpE0Zfh0bFFYY22MpRpbPyRXJ8uRzwQR/951kmaypN1a3fYvv/rn76X86nYSxVfEErkPbiFxkm+2nzfVOJKLry1oqsg6hE/n9STTSACs4hcprT4KG1keQwHA05tHZJm21JBBjIggNdEpqztxkrLHkq/ki352tekW+ji0fQdHUpXWWrA/GcqA5xSVRpQqd6pE8G5pWY41QiZxcD8kzFG7r4FePDqpCGts3oUkFNTYcKQfWxXAy/8ivs8zT2rbQ8AR6Lqu07DzvDDsmLwl7JxvsTbq72n8I2nY1WRiFdfAeWCVontCZKtvskxAsLrsS+9G11lHq0wu9x7Xn0Xg4UmpR/+tAte6xWmX0br/a6Y5Amo+h2mb/eTUfkrhIxZy6nRZz/vxstV8mv+ixYK2tdR7hGwNcbuL8t5Dz4ArbIFq5ooqfhIN1/pDKyZqwOXiOduJnqiJ6NUXgD/IfU29WG6mOkfUSg6VgSs1l06hKd68BOUpXFRoN4+e11B0r7xhEPzfmNL6wOar+ZrQJ6ULFvTnL7uJZvAngFDQkDxAG7l1BfnlpKKI985YFsIVRxyEtE8R7sz3nv4bBj+fAz/m1H8L9jpZ+MS0N4rWv+IJFb7iJC9Xe87AP428/DGfh"
end


-- ** UTIL **
-- No better place for this too simple, yet too specific function anywhere else
function split_string(s, separator)
    local split_string = {}
    for token in string.gmatch(s, "[^" .. separator .. "]+") do
        table.insert(split_string, (tonumber(token) or token))
    end
    return split_string
end

-- ** LLOG **
-- Internally used logging function for a single table
local function _llog(table_to_print)
    local excludes = LLOG_EXCLUDES or {}  -- Optional custom excludes defined by the parent mod

    if type(table_to_print) ~= "table" then return (tostring(table_to_print)) end

    local tab_width, super_space = 2, ""
    for _=0, tab_width-1, 1 do super_space = super_space .. " " end

    local function format(table_part, depth)
        if table_size(table_part) == 0 then return "{}" end

        local spacing = ""
        for _=0, depth-1, 1 do spacing = spacing .. " " end
        local super_spacing = spacing .. super_space

        local out, first_element = "{", true
        local preceding_name = 0

        for name, value in pairs(table_part) do
            local element = tostring(value)
            if type(value) == "string" then
                element = "'" .. element .. "'"
            elseif type(value) == "table" then
                if excludes[name] ~= nil then
                    element = value.name or "EXCLUDE"
                else
                    element = format(value, depth+tab_width)
                end
            end

            local comma = (first_element) and "" or ","
            first_element = false

            -- Print string and continuous numerical keys only
            local key = (type(name) == "number" and preceding_name+1 ~= name) and "" or (name .. " = ")
            preceding_name = name

            out = out .. comma .. "\n" .. super_spacing .. key .. element
        end

        return (out .. "\n" .. spacing .. "}")
    end

    return format(table_to_print, 0)
end

-- User-facing function, handles multiple tables at being passed at once
function llog(...)
    local info = debug.getinfo(2, "Sl")
    local out = "\n" .. info.short_src .. ":" .. info.currentline .. ":"

    local arg_nr = table_size({...})
    if arg_nr == 0 then
        out = out .. " No arguments"
    elseif arg_nr == 1 then
        out = out .. " " .. _llog(select(1, ...))
    else
        for index, table_to_print in ipairs{...} do
            out = out .. "\n" .. index .. ": " ..  _llog(table_to_print)
        end
    end

    log(out)
end