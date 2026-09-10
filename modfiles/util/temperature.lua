local _temperature = {}

---@class TemperatureData
---@field annotation LocalisedString?
---@field applicable_values float[]

---@param name string
---@param temperature float?
---@return string
function _temperature.name_with(name, temperature)
    if temperature == nil then return name end
    return name .. "|" .. temperature
end

---@param name string with temperature
---@return string
---@return float
function _temperature.name_split(name)
    local chunks = lib.split_string(name, "|")
    return chunks[1]--[[@as string]], chunks[2]  ---@as float
end

--- An exclusive bound rejects the bound itself. Fuels burned for their heat need this on their
--- minimum, as a fluid at its default temperature carries no usable heat, and recipes reheating
--- a fluid need it on their maximum, as one going in that hot would only cancel the product out
---@param ingredient Ingredient.fluid
---@param exclusive_minimum boolean?
---@param exclusive_maximum boolean?
---@return TemperatureData data
function _temperature.generate_data(ingredient, exclusive_minimum, exclusive_maximum)
    local min_temp = ingredient.minimum_temperature
    local max_temp = ingredient.maximum_temperature

    -- An exclusive bound isn't a restriction worth showing, as it's simply not selectable
    local shown_min = (not exclusive_minimum) and min_temp or nil
    local shown_max = (not exclusive_maximum) and max_temp or nil

    local annotation = nil
    if shown_min and not shown_max then
        annotation = {"fp.min_temperature", shown_min}
    elseif not shown_min and shown_max then
        annotation = {"fp.max_temperature", shown_max}
    elseif shown_min and shown_max then
        annotation = {"fp.min_max_temperature", shown_min, shown_max}
    end

    local applicable_values = {}
    for _, fluid_proto in pairs(TEMPERATURE_MAP[ingredient.name]) do
        local temperature = fluid_proto.temperature
        local above_min = (min_temp == nil) or (temperature > min_temp)
            or (temperature == min_temp and not exclusive_minimum)
        local below_max = (max_temp == nil) or (temperature < max_temp)
            or (temperature == max_temp and not exclusive_maximum)
        if above_min and below_max then
            table.insert(applicable_values, fluid_proto.temperature)
        end
    end

    return {
        annotation = {"", " ", annotation}--[[@as LocalisedString]],
        applicable_values = applicable_values
    }
end


--- An excluded temperature is one that would cancel out the product the recipe is being added
--- for, so it doesn't count as a candidate at all
---@param player LuaPlayer
---@param ingredient Ingredient.fluid
---@param applicable_values float[]
---@param excluded float?
---@return number? default
function _temperature.determine_applicable_default(player, ingredient, applicable_values, excluded)
    local preferences = lib.globals.preferences(player)
    local defaults = preferences.default_temperatures[ingredient.name]

    local candidates = applicable_values
    if excluded ~= nil then
        candidates = {}
        for _, value in pairs(applicable_values) do
            if value ~= excluded then table.insert(candidates, value) end
        end
    end

    -- No preference to apply when there's no choice left to make
    if #candidates == 1 then return candidates[1] end

    for _, default in pairs(defaults) do
        for _, value in pairs(candidates) do
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
