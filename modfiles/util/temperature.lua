local _temperature = {}

---@class TemperatureData
---@field annotation LocalisedString?
---@field applicable_values float[]

--- An exclusive minimum rejects the minimum itself, which fuels burned for their heat need, as a
--- fluid at its default temperature carries no usable heat
---@param ingredient Ingredient.fluid
---@param exclusive_minimum boolean?
---@return TemperatureData data
function _temperature.generate_data(ingredient, exclusive_minimum)
    local min_temp = ingredient.minimum_temperature
    local max_temp = ingredient.maximum_temperature

    -- An exclusive minimum is the fluid's default temperature, which isn't a restriction worth
    -- showing - it's simply not selectable, as a fluid at it carries no heat to extract
    local shown_min = (not exclusive_minimum) and min_temp or nil

    local annotation = nil
    if shown_min and not max_temp then
        annotation = {"fp.min_temperature", shown_min}
    elseif not shown_min and max_temp then
        annotation = {"fp.max_temperature", max_temp}
    elseif shown_min and max_temp then
        annotation = {"fp.min_max_temperature", shown_min, max_temp}
    end

    local applicable_values = {}
    for _, fluid_proto in pairs(TEMPERATURE_MAP[ingredient.name]) do
        local temperature = fluid_proto.temperature
        local above_min = (min_temp == nil) or (temperature > min_temp)
            or (temperature == min_temp and not exclusive_minimum)
        if above_min and (not max_temp or max_temp >= temperature) then
            table.insert(applicable_values, fluid_proto.temperature)
        end
    end

    return {
        annotation = {"", " ", annotation},
        applicable_values = applicable_values
    }
end


---@param player LuaPlayer
---@param ingredient Ingredient.fluid
---@param applicable_values float[]
---@return number? default
function _temperature.determine_applicable_default(player, ingredient, applicable_values)
    local preferences = lib.globals.preferences(player)
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


---@alias TemperatureDefaultMap table<string, TemperatureDefault>
---@alias TemperatureDefault number[]

---@return TemperatureDefaultMap
function _temperature.get_fallback()
    local fallback = {}
    for name, _ in pairs(TEMPERATURE_MAP) do
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
