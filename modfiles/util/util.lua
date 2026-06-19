local _util = {
    flib = require("util.flib"),
    translator = require("util.dictionary"),
    globals = require("util.globals"),
    context = require("util.context"),
    clipboard = require("util.clipboard"),
    messages = require("util.messages"),
    cursor = require("util.cursor"),
    gui = require("util.gui"),
    format = require("util.format"),
    nth_tick = require("util.nth_tick"),
    porter = require("util.porter"),
    actions = require("util.actions"),
    effects = require("util.effects"),
    temperature = require("util.temperature"),
    preferences = require("util.preferences")
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


---@param export_table table
---@return ExportString export_string
function _util.pack_export_string(export_table)
    return helpers.encode_string(helpers.table_to_json(export_table))
end

---@param export_string ExportString
---@return table export_table
function _util.unpack_export_string(export_string)
    return helpers.json_to_table(helpers.decode_string(export_string))
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


---@param force LuaForce
---@param recipe_name string
---@return EffectValue productivity_bonus
function _util.get_recipe_productivity(force, recipe_name)
    local bonus = nil
    if recipe_name == "custom-mining" then
        bonus = force.mining_drill_productivity_bonus
    else
        bonus = force.recipes[recipe_name].productivity_bonus
    end
    return math.floor(bonus * MAGIC_NUMBERS.effect_precision + 1e-4)
end


---@alias FactoriopedaIDType "item" | "fluid" | "recipe" | "entity" | "tile" | "space-location" | "ammo-category" | "space-connection" | "asteroid-chunk" | "virtual-signal" | "surface"

---@param type FactoriopediaIDType
---@param name string
---@param proto FPPrototype?
function _util.get_factoriopedia_proto(type, name, proto)
    local fp_id = proto and proto.factoriopedia_id or nil

    if fp_id then return prototypes[fp_id.type][fp_id.name]
    else return prototypes[type][name] end
end


---@param name string
---@return boolean
function _util.is_special_power_item(name)
    return (name == "custom-electric-power" or name == "custom-heat-power" or name == "custom-heating-power")
end


return _util
