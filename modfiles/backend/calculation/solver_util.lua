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

--- Determines the amount of energy needed for a machine and the emissions that produces
---@param line_data LineData
---@param machine_amount number
---@param production_ratio number
---@return number, number
function _util.determine_power_and_emissions(line_data, machine_amount, production_ratio)
    local machine_proto = line_data.machine_proto
    local recipe_proto = line_data.recipe_proto
    local total_effects = line_data.total_effects
    local pollutant_type = line_data.pollutant_type

    local consumption_multiplier = 1 + (total_effects.consumption / MAGIC_NUMBERS.effect_precision)
    -- A fuel-starved machine only draws what it can get, and pollutes proportionally less
    local power = machine_amount * (line_data.energy_usage * 60) * consumption_multiplier * line_data.fuel_performance
    -- Drain follows the exact machine count rather than the whole machines that'd actually be
    -- built, so that power stays proportional to it. The matrix solver relies on that to balance
    -- power against the machines producing it, since it works in amounts for a single machine.
    local drain = machine_amount * (machine_proto.energy_drain * 60)
    local total_power = power + drain

    if pollutant_type == nil then return total_power, 0 end

    local fuel_multiplier = (line_data.fuel_proto ~= nil) and line_data.fuel_proto.emissions_multiplier or 1
    local pollution_multiplier = 1 + (total_effects.pollution / MAGIC_NUMBERS.effect_precision)
    local total_multiplier = fuel_multiplier * pollution_multiplier * recipe_proto.emissions_multiplier

    -- Pollution comes from the fuel that's burned, not the energy the machine puts to use: an
    -- effectivity below 1 burns extra, and a source that doesn't scale its usage burns its full
    -- amount even when the machine can't use all of it
    local burner, wasted_share = machine_proto.burner, line_data.wasted_share
    local burned_energy = power
    if burner then
        burned_energy = burned_energy / burner.effectivity
        if wasted_share > 0 and wasted_share < 1 then burned_energy = burned_energy / (1 - wasted_share) end
    end

    local emissions_per_joule = burned_energy * (machine_proto.emissions_per_joule[pollutant_type] or 0)
    local emissions_per_second = machine_amount * (machine_proto.emissions_per_second[pollutant_type] or 0)
    local emissions_per_craft = (recipe_proto.emissions_per_craft) and
        production_ratio * (recipe_proto.emissions_per_craft[pollutant_type] or 0) or 0
    local total_emissions = (emissions_per_joule + emissions_per_second + emissions_per_craft) * total_multiplier * 60

    return total_power, total_emissions
end

--- Determines the amount of fuel needed in the given context
---@param line_data LineData
---@param power number
---@param machine_amount number
---@return number
function _util.determine_fuel_amount(line_data, power, machine_amount)
    local burner = line_data.machine_proto.burner  ---@cast burner -nil
    local fluid_usage_per_tick = line_data.fluid_usage_per_tick

    if fluid_usage_per_tick and not burner.scale_fluid_usage then
        -- Without scaling, the source always moves its full usage, wasting any energy beyond demand
        return fluid_usage_per_tick * 60 * machine_amount
    end
    -- Power is already reduced by the fuel performance, so this collapses to the usage per tick
    -- when the source can't keep up, and to the demanded amount when it can
    return (power / burner.effectivity) / line_data.fuel_value--[[@as number]]
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
