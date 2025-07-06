local _temperature = {}

---@class TemperatureData
---@field annotation LocalisedString?
---@field applicable_values float[]

-- Assumes the given ingredient is a fluid
---@param ingredient Ingredient
---@return float? temperature
---@return TemperatureData data
function _temperature.generate_data(ingredient, previous_temperature)
    local min_temp = ingredient.minimum_temperature
    local max_temp = ingredient.maximum_temperature

    local annotation = nil
    if min_temp and not max_temp then
        annotation = {"fp.min_temperature", min_temp}
    elseif not min_temp and max_temp then
        annotation = {"fp.max_temperature", max_temp}
    elseif min_temp and max_temp then
        annotation = {"fp.min_max_temperature", min_temp, max_temp}
    end

    local applicable_values = {}
    local previous_still_valid = false

    for _, fluid_proto in pairs(TEMPERATURE_MAP[ingredient.name]) do
        if (not min_temp or min_temp <= fluid_proto.temperature) and
                (not max_temp or max_temp >= fluid_proto.temperature) then
            table.insert(applicable_values, fluid_proto.temperature)

            if previous_temperature == fluid_proto.temperature then
                previous_still_valid = true
            end
        end
    end

    local default_temperature = (#applicable_values == 1) and applicable_values[1] or nil
    local temperature = (previous_still_valid) and previous_temperature or default_temperature

    local data = {
        annotation = {"", " ", annotation},
        applicable_values = applicable_values
    }

    return temperature, data
end

return _temperature
