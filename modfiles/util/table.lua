local _table = {}


--- Inserts a `value` at the end of the `table` with a given `key`.
--- If `key` already contains a value, the two are added together.
---@generic T
---@param table table<T, number>
---@param key T
---@param value number
---@return number value The new `value` stored at `key`
function _table.add(table, key, value)
    table[key] = table[key] ~= nil and table[key] + value or value
    return table[key]
end


--- Joins two tables together in a new result table (`L ∪ R`).
--- The contents of `left_table` are inserted first.
--- If the `right_table` contains a key that is already in the `left_table`,
--- then the value in the `right_table` will be present in the result.
---@generic T
---@param left_table T
---@param right_table T
---@return T result
function _table.union(left_table, right_table)
    local result = {}
    for k, v in pairs(left_table) do result[k] = v end
    for k, v in pairs(right_table) do result[k] = v end
    return result
end


--- Returns the intersection of two tables (`L ∩ R`).
--- The result will contain the contents of the `left_table`,
--- whose keys are also present in the `right_table`.
---@generic T
---@param left_table T
---@param right_table T
---@return T result_table
function _table.intersection(left_table, right_table)
    local result = {}
    for k, v in pairs(left_table) do
        -- Intentionally exclude both `nil` and `false` (preserve operation truthyness)
        if right_table[k] then result[k] = v end
    end

    return result
end


--- Subtracts the `right_table` from the `left_table` table in a new result table (`L ∖ R`).
--- The result will contain the contents of the `left_table`,
--- excluding the keys that are also present in the `right_table`.
---@param left_table table
---@param right_table table
---@return table result_table
function _table.difference(left_table, right_table)
    local result = {}
    for k, v in pairs(left_table) do
        -- Intentionally exclude both `nil` and `false` (preserve operation truthyness)
        if not right_table[k] then result[k] = v end
    end

    return result
end


return _table
