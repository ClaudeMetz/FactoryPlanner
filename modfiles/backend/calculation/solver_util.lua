local structures = require("backend.calculation.structures")

local _util = {
    set = {},
    matrix = {},
}

_util.pack_item = structures.pack_item
_util.unpack_item = structures.unpack_item


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

---@alias QualityDistribution table<string, number>

---@param total_effects IntegerModuleEffects
---@param base_quality FPQualityPrototype?
---@return QualityDistribution
function _util.determine_quality_ditribuiton(total_effects, base_quality)
    if not QUALITY_ENABLED then return { normal = 1 } end

    local proto = base_quality or defaults.get_fallback("qualities").proto  ---@as FPQualityPrototype
    if total_effects.quality == 0 then return { [proto.name] = 1 } end

    local result = {}  ---@type QualityDistribution
    local quality_effect = total_effects.quality / MAGIC_NUMBERS.effect_precision
    local probability_sum = 0.0

    ---@param probability number
    local function quality_step(probability)
        if probability == 0 then return end
        result[proto.name] = probability
        probability_sum = probability_sum + probability
    end

    if quality_effect > 0 then
        quality_step(1 - quality_effect * proto.next_probability)

        local next_proto = proto.next_quality and prototyper.util.find("qualities", proto.next_quality)  ---@as FPQualityPrototype?
        while next_proto do
            proto = next_proto
            next_proto = proto.next_quality and prototyper.util.find("qualities", proto.next_quality)  ---@as FPQualityPrototype?
            local probability = 1 - probability_sum

            if next_proto and proto.next_chain_probability > 0 then
                probability = probability * (1 - proto.next_chain_probability)
            else
                next_proto = nil  -- upgrade probability is 0, no need to continue
            end

            quality_step(probability)
        end
    end

    return result
end

---@param recipe_quality FPQualityPrototype?
---@param item Ingredient | FormattedProduct | FPItemPrototype
---@return FPQualityPrototype?
function _util.determine_item_quality(recipe_quality, item)
    if not QUALITY_ENABLED or item.type ~= "item" then return end

    local base_quality = recipe_quality or
            defaults.get_fallback("qualities").proto  ---@as FPQualityPrototype

    -- Quality IDs are sorted by level, so a shift in quality is a shift in ID
    local quality_id = base_quality.id + (item.quality_change or 0)  ---@as integer

    local min_proto = item.quality_min and prototyper.util.find("qualities", item.quality_min--[[@as string]])  ---@as FPQualityPrototype?
    quality_id = math.max(quality_id, min_proto and min_proto.id or 1)

    local max_proto = item.quality_max and prototyper.util.find("qualities", item.quality_max--[[@as string]])  ---@as FPQualityPrototype?
    quality_id = math.min(quality_id, max_proto and max_proto.id or #storage.prototypes.qualities)

    return prototyper.util.find("qualities", quality_id)  ---@as FPQualityPrototype
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
