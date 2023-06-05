data_util = {
}


-- ** MISC **
-- Still can't believe this is not a thing in Lua
-- This has the added feature of turning any number strings into actual numbers
function data_util.split_string(s, separator)
    local result = {}
    for token in string.gmatch(s, "[^" .. separator .. "]+") do
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
function data_util.build_localised_string(strings_to_insert, current_table, next_index)
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
