local _availability = {}


---@param force LuaForce
---@param recipe FPRecipePrototype
---@return boolean? overwrite
local function recipe_picker_overwrite(force, recipe)
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
function _availability.is_recipe_available(force, recipe)
    if recipe.custom then return true end  -- custom recipes are always available

    local force_recipe = force.recipes[recipe.name]
    if force_recipe == nil then return false end

    -- A recipe that another one stands in for can't be obtained anymore, no matter its own state
    local substitutions = storage.integrations.recipe_substitutions[force.index]
    if substitutions and substitutions[recipe.name] then return false end

    -- A mod overwriting the picker knows better than the recipe's own state, either way
    local overwrite = recipe_picker_overwrite(force, recipe)
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
function _availability.is_machine_available(force, machine)
    local substitutions = storage.integrations.machine_substitutions[force.index]
    return not (substitutions and substitutions[machine.name])
end


---@param recipe FPRecipePrototype
---@param machine FPMachinePrototype
---@return boolean
function _availability.is_recipe_machine_compatible(recipe, machine)
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
function _availability.is_recipe_unlocked(force, recipe, cache)
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
        if _availability.is_recipe_machine_compatible(recipe, machine) and _availability.is_machine_available(force, machine)
            and is_prototype_unlocked(force, {type="entity", name=machine.name}, cache) then return true end
    end
    return false
end

---@param force LuaForce
---@param item FPItemPrototype
---@param cache PrototypeUnlockCache?
---@return boolean
function _availability.is_item_unlocked(force, item, cache)
    cache = cache or {}
    if item.type ~= "entity" then
        return is_prototype_unlocked(force, {type=item.type, name=item.base_name or item.name}, cache)
    end

    local producers = RECIPE_MAPS.produce[item.category_id][item.id]
    for recipe_id, _ in pairs(producers or {}) do
        local recipe = prototyper.util.find("recipes", recipe_id, nil)  ---@as FPRecipePrototype
        if _availability.is_recipe_unlocked(force, recipe, cache) then return true end
    end
    return false
end

return _availability
