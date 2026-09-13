---@class FPLib
local _lib = {
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
function _lib.split_string(str, separator)
    local result = {}
    for token in string.gmatch(str, "[^" .. separator .. "]+") do
        table.insert(result, (tonumber(token) or token))
    end
    return result
end


---@param export_table table
---@return ExportString export_string
function _lib.pack_export_string(export_table)
    return helpers.encode_string(helpers.table_to_json(export_table)) ---@as ExportString
end

---@param export_string ExportString
---@return table export_table
function _lib.unpack_export_string(export_string)
    return helpers.json_to_table(helpers.decode_string(export_string)--[[@as string]]) ---@as table
end


-- Fills up the localised table in a smart way to avoid the limit of 20 strings per level
-- To make it stateless, it needs its return values passed back as arguments
-- Uses state to avoid needing to call table_size() because that function is slow
---@param string_to_insert LocalisedString
---@param current_table LocalisedString
---@param next_index integer
---@return LocalisedString, integer
function _lib.build_localised_string(string_to_insert, current_table, next_index)
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
---@return IntegerEffectValue productivity_bonus
function _lib.get_recipe_productivity(force, recipe_name)
    local bonus = nil
    if recipe_name == "custom-mining" then
        bonus = force.mining_drill_productivity_bonus
    elseif recipe_name == "custom-research" then
        bonus = force.laboratory_productivity_bonus
    else
        bonus = force.recipes[recipe_name].productivity_bonus
    end
    return math.floor(bonus * MAGIC_NUMBERS.effect_precision + 1e-4)
end


---@param force LuaForce
---@param recipe FPRecipePrototype
---@return boolean? overwrite
function _lib.recipe_picker_overwrite(force, recipe)
    local overwrite = nil  ---@type boolean?

    local overwrites = storage.integrations.overwrite_recipe_picker[force.index]
    if overwrites then overwrite = overwrites[recipe.name] end

    if overwrite == nil then  -- fall back to the base game's visibility override
        overwrite = force.get_script_visible({type="recipe", name=recipe.name})
    end

    return overwrite
end


---@param force LuaForce
---@param recipe FPRecipePrototype
---@return boolean available
---@return boolean? overwrite
function _lib.is_recipe_available(force, recipe)
    if recipe.custom then return true end  -- custom recipes are always available

    local force_recipe = force.recipes[recipe.name]
    if force_recipe == nil then return false end

    -- A recipe that another one stands in for can't be obtained anymore, no matter its own state
    local substitutions = storage.integrations.recipe_substitutions[force.index]
    if substitutions and substitutions[recipe.name] then return false end

    -- A mod overwriting the picker knows better than the recipe's own state, either way
    local overwrite = _lib.recipe_picker_overwrite(force, recipe)
    if overwrite ~= nil then return overwrite, overwrite end

    if recipe.enabled_from_the_start or force_recipe.enabled then return true end

    -- If the recipe is not enabled, it has to be made sure that there is at
    -- least one enabled technology that could potentially enable it
    if recipe.enabling_technologies ~= nil then
        for _, technology_name in pairs(recipe.enabling_technologies) do
            local force_technology = force.technologies[technology_name]
            if force_technology and (force_technology.enabled or force_technology.visible_when_disabled) then
                return true
            end
        end
    end

    return false
end

---@param force LuaForce
---@param machine FPMachinePrototype
---@return boolean available
function _lib.is_machine_available(force, machine)
    local substitutions = storage.integrations.machine_substitutions[force.index]
    return not (substitutions and substitutions[machine.name])
end


---@param recipe FPRecipePrototype
---@param machine FPMachinePrototype
---@return boolean
function _lib.is_recipe_machine_compatible(recipe, machine)
    local counts = recipe.type_counts
    return machine.ingredient_limit >= counts.ingredients.items
        and machine.product_limit >= counts.products.items
        and machine.fluid_channels.input >= counts.ingredients.fluids
        and machine.fluid_channels.output >= counts.products.fluids
end


---@alias PrototypeUnlockCache table<string, table<string, boolean>>

---@param force LuaForce
---@param id UnlockableID
---@param cache PrototypeUnlockCache
---@return boolean
local function is_prototype_unlocked(force, id, cache)
    local type_cache = cache[id.type]
    if type_cache == nil then
        type_cache = {}
        cache[id.type] = type_cache
    end
    local name = id.name or ""  -- special unlocks, such as fluid mining, have no prototype name
    if type_cache[name] == nil then type_cache[name] = force.is_visible(id) end
    return type_cache[name]
end

-- Custom recipes require an unlocked compatible machine and any explicit source requirements
---@param force LuaForce
---@param recipe FPRecipePrototype
---@param cache PrototypeUnlockCache?
---@return boolean
function _lib.is_recipe_unlocked(force, recipe, cache)
    if not recipe.custom then
        local force_recipe = force.recipes[recipe.name]
        return force_recipe ~= nil and force_recipe.enabled
    end

    cache = cache or {}
    for _, requirement in pairs(recipe.additional_unlock_requirements or {}) do
        if not is_prototype_unlocked(force, requirement, cache) then return false end
    end

    if recipe.unlock_without_machine then return true end

    local machines = prototyper.util.find("machines", nil, recipe.combined_category)  ---@as NamedCategory<FPMachinePrototype>
    for _, machine in pairs(machines.members) do
        if _lib.is_recipe_machine_compatible(recipe, machine) and _lib.is_machine_available(force, machine)
            and is_prototype_unlocked(force, {type="entity", name=machine.name}, cache) then return true end
    end
    return false
end

---@param force LuaForce
---@param item FPItemPrototype
---@param cache PrototypeUnlockCache?
---@return boolean
function _lib.is_item_unlocked(force, item, cache)
    cache = cache or {}
    if item.type ~= "entity" then
        return is_prototype_unlocked(force, {type=item.type, name=item.base_name or item.name}, cache)
    end

    local producers = RECIPE_MAPS.produce[item.category_id][item.id]
    for recipe_id, _ in pairs(producers or {}) do
        local recipe = prototyper.util.find("recipes", recipe_id, nil)  ---@as FPRecipePrototype
        if _lib.is_recipe_unlocked(force, recipe, cache) then return true end
    end
    return false
end


---@alias FactoriopediaIDType "item" | "fluid" | "recipe" | "entity" | "tile" | "space-location" | "ammo-category" | "space-connection" | "asteroid-chunk" | "virtual-signal" | "surface"
---@alias FPFactoriopediaID {type: FactoriopediaIDType, name: string}

-- Custom items and recipes need an explicit mapping; normal entries use their own prototype.
---@param proto FPPrototype | FPPackedPrototype
---@return FactoriopediaID?
function _lib.get_factoriopedia_proto(proto)
    if proto.simplified then return nil end
    ---@cast proto FPPrototype
    local fp_id = proto.factoriopedia_id
    if fp_id then return prototypes[fp_id.type][fp_id.name] end

    if proto.data_type == "items" then
        ---@cast proto FPItemPrototype
        if proto.type == "entity" then return nil end
        return prototypes[proto.type][proto.base_name or proto.name]
    elseif proto.data_type == "recipes" then
        ---@cast proto FPRecipePrototype
        if proto.custom then return nil end
        return prototypes.recipe[proto.name]
    elseif proto.data_type == "fuels" then
        ---@cast proto FPFuelPrototype
        return prototypes[proto.type][proto.name]
    elseif proto.data_type == "modules" then
        return prototypes.item[proto.name]
    elseif proto.data_type == "machines" or proto.data_type == "beacons" then
        return prototypes.entity[proto.name]
    end
    return nil
end


---@param name string
---@return boolean
function _lib.is_special_power_item(name)
    return (name == "custom-electric-power" or name == "custom-heat-power" or name == "custom-heating-power")
end

return _lib
