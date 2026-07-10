local table = {}


--- Inserts a `value` at the end of the `table` with a given `key`.
--- If `key` already contains a value, the two are added together.
---@param table table<any, number>
---@param key any
---@param value number
---@return number value  The new `value` stored at `key`
function table.add(table, key, value)
    table[key] = table[key] ~= nil and table[key] + value or value
    return table[key]
end


--- Joins 2 tables together.
--- The contents of the `right_table` are inserted at the end of the `left_table`.
--- If the `right_table` contains a key that is already in the `left_table`,
--- then the value in the `right_table` will be present in the result.
---@param left_table table<any, any>
---@param right_table table<any, any>
---@return table<any, any> result_table
function table.join(left_table, right_table)
    local result_table = {}
    for k, v in pairs(left_table) do result_table[k] = v end
    for k, v in pairs(right_table) do result_table[k] = v end
    return result_table
end

return table