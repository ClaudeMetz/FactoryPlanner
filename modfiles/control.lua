require("util")  -- core.lualib
table = require('__flib__.table')  -- replaces the lua table module

require("data.init")
require("ui.listeners")

MARGIN_OF_ERROR = 1e-8  -- Margin of error for floating point calculations
DEVMODE = false  -- Enables certain conveniences for development

TUTORIAL_EXPORT_STRING = "eNrtWU2P0zAQ/S8+J6u2u0JVjyCQkEBCcFytIseZdAfsODhORVX1vzNOHBraojQ0C9lVbu14Pp5nnj3jdseUTqINmAJ1xlZsdjNf3twtWMCKMk65sNogFGx1v2MZV0Aab39wlUsgDRTOZMfsNncLaEGR1KvlRielsOQ1LARCJiDMufjG9gGzqKAQnHysXs3IQFsXgZHtp9rIOdXxVxC2jky+rHbCDt8EGgkbpggJW1lTQvAbOIpt4HuJBpKIK11mVaQEUsxIEm9Jz4uD5sNqvpw5yDqPJGxANm6F5IUD3SDePwQectQsva/z0Xx9o6WECjTzDlOptXEIPlD84z03ZtVaXY0e6gYE5pXSNbkT3MJaG5cXYXhqMVs77AcXkc9uLYHWbj/XAEhbcfHoAR9jIVVQsSS3odcKb/sAeeQmiSQqpDqlXBak+ZGASLiUQBu021BVJt2R20YuesOQu8OuffQzZPArf6JDjSESpx599kgnBu4P3PF2/EoH/jSPvGIL/LKJfc5vkQMkF+en0m77Xpwm5iB5/QtKDkZAZvmaQs5nM8cvpFvHbiOf8cjjqkq8D3qQ3XCUY2H2Ynhm7/bX8Wx2lmdPWA807tqxOJ77ZqrKioGDYlCEaWkyXqV1qs1IanOmU73g8tx39KDFED3oyua8GIICpxg8E84j8KNnK/S7ahjc9+ISTzac5r0kFGhEiXaa+aaZ7+XNfHU30xn1s5HxfOpntEWdk/dQ8FhOc8aI6lJYABnmkjbdeeYVyMHL0ncGbYMYR0v4V5PG1BL+gtyajnlsLnh3PlNyP79fAlSuqSwmrGrTlZCYF5S9QktMnqYwCjPXERKDUvYEM+jtsxjw9gkGf0zNB7/ibv/fY2p+8pg6CL40/31Qjh/2PwF6R7b4"

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
local function _llog(table)
    local excludes = LLOG_EXCLUDES or {}  -- Optional custom excludes defined by the parent mod

    if type(table) ~= "table" then return (tostring(table)) end

    local tab_width, super_space = 2, ""
    for _=0, tab_width-1, 1 do super_space = super_space .. " " end

    local function format(table, depth)
        if table_size(table) == 0 then return "{}" end

        local spacing = ""
        for _=0, depth-1, 1 do spacing = spacing .. " " end
        local super_spacing = spacing .. super_space

        local out, first_element = "{", true
        local preceding_name = 0

        for name, value in pairs(table) do
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

    return format(table, 0)
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
        for index, table in ipairs{...} do
            out = out .. "\n" .. index .. ": " ..  _llog(table)
        end
    end

    log(out)
end