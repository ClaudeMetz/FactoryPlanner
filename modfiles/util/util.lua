local _util = {
    globals = require("util.globals"),
    context = require("util.context"),
    clipboard = require("util.clipboard"),
    messages = require("util.messages"),
    raise = require("util.raise"),
    cursor = require("util.cursor"),
    gui = require("util.gui"),
    format = require("util.format"),
    nth_tick = require("util.nth_tick"),
    porter = require("util.porter"),
    actions = require("util.actions")
}


-- Still can't believe this is not a thing in Lua
-- This has the added feature of turning any number strings into actual numbers
---@param str string
---@param separator string
---@return string[]
function _util.split_string(str, separator)
    local result = {}
    for token in string.gmatch(str, "[^" .. separator .. "]+") do
        table.insert(result, (tonumber(token) or token))
    end
    return result
end


-- Fills up the localised table in a smart way to avoid the limit of 20 strings per level
-- To make it stateless, it needs its return values passed back as arguments
-- Uses state to avoid needing to call table_size() because that function is slow
---@param string_to_insert LocalisedString
---@param current_table LocalisedString
---@param next_index integer
---@return LocalisedString, integer
function _util.build_localised_string(string_to_insert, current_table, next_index)
    current_table = current_table or {""}
    next_index = next_index or 2

    if next_index == 20 then  -- go a level deeper if this one is almost full
        local new_table = {""}
        current_table[next_index] = new_table
        current_table = new_table
        next_index = 2
    end
    current_table[next_index] = string_to_insert
    next_index = next_index + 1

    return current_table, next_index
end


---@param effect_tables ModuleEffects[]
---@return ModuleEffects
function _util.merge_effects(effect_tables)
    local effects = ftable.shallow_copy(BLANK_EFFECTS)
    for _, effect_table in pairs(effect_tables) do
        for name, effect in pairs(effect_table) do
            effects[name] = effects[name] + effect
        end
    end
    return effects
end

local is_effect_positive = {speed=true, productivity=true, quality=true,
                          consumption=false, pollution=false}
local upper_bound = 327.67

---@param name string
---@param value ModuleEffectValue
---@return boolean is_positive_effect
function _util.is_positive_effect(name, value)
    -- Effects are considered positive if their effect is actually in the 'desirable'
    -- direction, ie. positive speed, or negative pollution
    return (value > 0) == is_effect_positive[name]
end

---@param effects ModuleEffects
---@param max_prod double
---@return ModuleEffects
---@return { ModuleEffectName: string }
function _util.limit_effects(effects, max_prod)
    local indications = {}
    local bounds = {
        speed = {lower = -0.8, upper = upper_bound},
        productivity = {lower = 0, upper = max_prod},
        quality = {lower = 0, upper = upper_bound},
        consumption = {lower = -0.8, upper = upper_bound},
        pollution = {lower = -0.8, upper = upper_bound}
    }

    -- Bound effects and note the indication if relevant
    for name, effect in pairs(effects) do
        if effect < bounds[name].lower then
            effects[name] = bounds[name].lower
            indications[name] = "[img=fp_limited_down]"
        elseif effect > bounds[name].upper then
            effects[name] = bounds[name].upper
            indications[name] = "[img=fp_limited_up]"
        end
    end

    return effects, indications
end


---@param a boolean
---@param b boolean
---@return boolean
function _util.xor(a, b)
    return not a ~= not b
end


---@param force LuaForce
---@param recipe_name string
---@return ModuleEffectValue productivity_bonus
function _util.get_recipe_productivity(force, recipe_name)
    if recipe_name == "custom-mining" then
        return force.mining_drill_productivity_bonus
    else
        return force.recipes[recipe_name].productivity_bonus
    end
end

return _util
