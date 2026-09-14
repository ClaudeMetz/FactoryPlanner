local _util = {
    set = {},
    matrix = {},
}


---Performs `a - b` while correcting floating point errors
---@param a number
---@param b number
---@return number
function _util.safe_sub(a, b)
    local c = a - b
    if c < MAGIC_NUMBERS.margin_of_error and c > -MAGIC_NUMBERS.margin_of_error then return 0 end
    return c
end
--- Calculates the product amount after applying productivity bonuses
---@param item FormattedProduct
---@param total_effects IntegerModuleEffects
---@return number
function _util.determine_prodded_amount(item, total_effects)
    if total_effects.productivity <= 0 then return item.amount end  -- no negative productivity

    -- Return formula is a simplification of the following formula:
    -- item.amount - item.proddable_amount + (item.proddable_amount *
    --   (1 + (productivity / MAGIC_NUMBERS.effect_precision)))
    return item.amount + (item.proddable_amount * (total_effects.productivity / MAGIC_NUMBERS.effect_precision))
end

--- Joins two or more sets together in a new result set (`L ∪ R`).
---@generic T
---@param t table<T, true>
---@param ... table<T, true>
---@return table<T, true>
function _util.set.union(t, ...)
    local result = {}
    for k, v in pairs(t) do result[k] = v end
    for _, table in pairs({...}) do
        for k, v in pairs(table) do
            -- Preserve truthiness
            result[k] = v or result[k]
        end
    end
    return result
end

--- Returns the intersection of two or more sets (`L ∩ R`).
---@generic T
---@param t table<T, true>
---@param ... table<T, true>
---@return table<T, true>
function _util.set.intersection(t, ...)
    local result = {}
    for k, v in pairs(t) do result[k] = v end
    for _, table in pairs({...}) do
        for k, v in pairs(result) do
            -- Preserve truthiness
            result[k] = v and table[k]
        end
    end

    return result
end

--- Returns the total item count of one or more sets
---@return integer
function _util.set.count(...)
    local count = 0
    for _, set in pairs({...}) do
        for _, _ in pairs(set) do count = count + 1 end
    end
    return count
end

--- Subtracts the sets on the right from the first input set in a new result set (`L ∖ R`).
---@generic T
---@param t table<T, true>
---@param ... table<T, true>
---@return table<T, true>
function _util.set.difference(t, ...)
    local result = {}
    for k, v in pairs(t) do result[k] = v end
    for _, table in pairs({...}) do
        for k, _ in pairs(table) do
            -- Preserve truthyness
            if table[k] then result[k] = nil end
        end
    end

    return result
end

--- Performs `M * v`
---@param matrix number[][] column-major order
---@param vector number[]
---@return number[]
function _util.matrix.right_mult_cmo(matrix, vector)
    local result = {}  ---@type number[]
    for i = 1, #matrix[1] do
        result[i] = 0.0
    end
    for j = 1, #matrix do
        if vector[j] ~= 0 then
            for i = 1, #matrix[j] do
                if matrix[j][i] ~= 0 then
                    ---@diagnostic disable: need-check-nil
                    result[i] = result[i] + vector[j] * matrix[j][i]
                end
            end
        end
    end

    return result
end

--- Performs `v^T * M`
---@param vector number[]
---@param matrix number[][] column-major order
---@return number[]
function _util.matrix.left_mult_cmo(vector, matrix)
    local result = {}  ---@type number[]
    for j = 1, #matrix do
        result[j] = 0.0
    end
    for i = 1, #matrix[1] do
        if vector[i] ~= 0 then
            for j = 1, #matrix do
                if matrix[j][i] ~= 0 then
                    ---@diagnostic disable: need-check-nil
                    result[j] = result[j] + vector[i] * matrix[j][i]
                end
            end
        end
    end

    return result
end

return _util
