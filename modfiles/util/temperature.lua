local _temperature = {}

---@class TemperatureData
---@field annotation LocalisedString?
---@field applicable_values float[]

---@param ingredient Ingredient.fluid
---@return TemperatureData data
function _temperature.generate_data(ingredient)
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
    for _, fluid_proto in pairs(TEMPERATURE_MAP[ingredient.name]) do
        if (not min_temp or min_temp <= fluid_proto.temperature) and
                (not max_temp or max_temp >= fluid_proto.temperature) then
            table.insert(applicable_values, fluid_proto.temperature)
        end
    end

    return {
        annotation = {"", " ", annotation},
        applicable_values = applicable_values
    }
end


---@param ingredient Ingredient.fluid
---@return number default
function _temperature.determine_applicable_default(player, ingredient, applicable_values)
    local preferences = util.globals.preferences(player)
    local defaults = preferences.default_temperatures[ingredient.name]

    if #applicable_values == 1 then
        return applicable_values[1]
    end

    for _, default in pairs(defaults) do
        for _, value in pairs(applicable_values) do
            if default == value then return default end
        end
    end

    return nil
end


---@alias TemperatureDefaultMap { string: TemperatureDefault }
---@alias TemperatureDefault number[]

---@return TemperatureDefaultMap
function _temperature.get_fallback()
    local fallback = {}
    for name, prototypes in pairs(TEMPERATURE_MAP) do
        fallback[name] = {}
    end
    return fallback
end

---@param player_table PlayerTable
function _temperature.migrate(player_table)
    local defaults = player_table.preferences.default_temperatures

    for name, prototypes in pairs(TEMPERATURE_MAP) do
        if defaults[name] == nil then
            defaults[name] = {}
        else
            local available_temperatures = {}
            for _, proto in pairs(prototypes) do
                available_temperatures[proto.temperature] = true
            end

            local default = defaults[name]
            for i = #default, 1, -1 do
                if not available_temperatures[default[i]] then
                    table.remove(default, i)
                end
            end
        end
    end
end


return _temperature
