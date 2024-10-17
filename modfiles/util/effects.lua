local _effects = {}

---@param effect_tables ModuleEffects[]
---@return ModuleEffects
function _effects.merge(effect_tables)
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

---@param name string
---@param value ModuleEffectValue
---@return boolean is_positive_effect
function _effects.is_positive(name, value)
    -- Effects are considered positive if their effect is actually in the 'desirable'
    -- direction, ie. positive speed, or negative pollution
    return (value > 0) == is_effect_positive[name]
end


local upper_bound = 327.67

---@param effects ModuleEffects
---@param max_prod double
---@return ModuleEffects
---@return { ModuleEffectName: string }
function _effects.limit(effects, max_prod)
    local indications = {}
    local bounds = {
        speed = {lower = -0.8, upper = upper_bound},
        productivity = {lower = 0, upper = max_prod or upper_bound},
        quality = {lower = 0, upper = upper_bound/10},
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


---@class FormatModuleEffectsOptions
---@field indications { ModuleEffectName: string }?
---@field machine_effects ModuleEffects?
---@field recipe_effects ModuleEffects?

local function format_effect(value, color)
    if value == nil then return "" end
    -- Force display of either a '+' or '-', also round the result
    local display_value = ("%+d"):format(math.floor((value * 100) + 0.5))
    return {"fp.effect_value", color, display_value}
end

-- Formats the given effects for use in a tooltip
---@param module_effects ModuleEffects
---@param options FormatModuleEffectsOptions?
---@return LocalisedString
function _effects.format(module_effects, options)
    options = options or {}
    options.indications = options.indications or {}
    options.machine_effects = options.machine_effects or {}
    options.recipe_effects = options.recipe_effects or {}

    local tooltip_lines = {""}
    for effect_name, _ in pairs(BLANK_EFFECTS) do
        local module_effect = module_effects[effect_name]
        local machine_effect = options.machine_effects[effect_name]
        local recipe_effect = options.recipe_effects[effect_name]

        if options.indications[effect_name] ~= nil or module_effect ~= 0
                or (machine_effect ~= nil and machine_effect ~= 0)
                or (recipe_effect ~= nil and recipe_effect ~= 0) then
            local module_percentage = format_effect(module_effect, "#FFE6C0")
            local machine_percentage = format_effect(machine_effect, "#7CFF01")
            local recipe_percentage = format_effect(recipe_effect, "#01FFF4")

            if #tooltip_lines > 1 then table.insert(tooltip_lines, "\n") end
            table.insert(tooltip_lines, {"fp.effect_line", {"fp." .. effect_name}, module_percentage,
                machine_percentage, recipe_percentage, options.indications[effect_name] or ""})
        end
    end

    return tooltip_lines
end

return _effects
