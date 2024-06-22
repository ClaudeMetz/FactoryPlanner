local _util = {
    globals = require("util.globals"),
    context = require("util.context"),
    clipboard = require("util.clipboard"),
    messages = require("util.messages"),
    raise = require("util.raise"),
    cursor = require("util.cursor"),
    gui = require("util.gui"),
    format = require("util.format"),
    nth_tick = require("util.nth_tick"),
    porter = require("util.porter"),
    actions = require("util.actions")
}


-- Still can't believe this is not a thing in Lua
-- This has the added feature of turning any number strings into actual numbers
---@param str string
---@param separator string
---@return string[]
function _util.split_string(str, separator)
    local result = {}
    for token in string.gmatch(str, "[^" .. separator .. "]+") do
        table.insert(result, (tonumber(token) or token))
    end
    return result
end


-- Fills up the localised table in a smart way to avoid the limit of 20 strings per level
-- To make it stateless, it needs its return values passed back as arguments
-- Uses state to avoid needing to call table_size() because that function is slow
---@param strings_to_insert LocalisedString[]
---@param current_table LocalisedString
---@param next_index integer
---@return LocalisedString, integer
function _util.build_localised_string(strings_to_insert, current_table, next_index)
    current_table = current_table or {""}
    next_index = next_index or 2

    for _, string_to_insert in ipairs(strings_to_insert) do
        if next_index == 20 then  -- go a level deeper if this one is almost full
            local new_table = {""}
            current_table[next_index] = new_table
            current_table = new_table
            next_index = 2
        end
        current_table[next_index] = string_to_insert
        next_index = next_index + 1
    end

    return current_table, next_index
end

-- This function is only called when Recipe Book is active, so no need to check for the mod
---@param player LuaPlayer
---@param type string
---@param name string
function _util.open_in_recipebook(player, type, name)
    local message = nil  ---@type LocalisedString

    if remote.call("RecipeBook", "version") ~= RECIPEBOOK_API_VERSION then
        message = {"fp.error_recipebook_version_incompatible"}
    else
        ---@type boolean
        local was_opened = remote.call("RecipeBook", "open_page", player.index, type, name)
        if not was_opened then message = {"fp.error_recipebook_lookup_failed", {"fp.pl_" .. type, 1}} end
    end

    if message then util.messages.raise(player, "error", message, 1) end
end

-- This function is only called when Factory Search is active, so no need to check for the mod
---@param player LuaPlayer
---@param type string
---@param name string
function _util.open_in_factorysearch(player, type, name)
    remote.call("factory-search", "search", player, {type=type, name=name})
end

return _util
