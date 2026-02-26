local _effects = {}

---@alias EffectValue integer
---@alias ModuleEffectName "speed" | "productivity" | "quality" | "consumption" | "pollution"
---@alias IntegerModuleEffects { [ModuleEffectName]: EffectValue }

---@param effect_tables IntegerModuleEffects[]
---@return IntegerModuleEffects
function _effects.merge(effect_tables)
    local effects = ftable.shallow_copy(BLANK_EFFECTS)
    for _, effect_table in pairs(effect_tables) do
        for name, effect in pairs(effect_table) do
            effects[name] = effects[name] + effect  -- doesn't create decimals
        end
    end
    return effects
end


local is_effect_positive = {speed=true, productivity=true, quality=true,
                            consumption=false, pollution=false}

---@param name string
---@param value EffectValue
---@return boolean is_positive_effect
function _effects.is_positive(name, value)
    -- Effects are considered positive if their effect is actually in the 'desirable'
    -- direction, ie. positive speed, or negative pollution
    return (value > 0) == is_effect_positive[name]
end


local upper_bound = 32767

---@param effects IntegerModuleEffects
---@param maximum_productivity EffectValue
---@return IntegerModuleEffects
---@return { ModuleEffectName: string }
function _effects.limit(effects, maximum_productivity)
    local bounds = {
        speed = {lower = -80, upper = upper_bound},
        productivity = {lower = 0, upper = maximum_productivity or upper_bound},
        quality = {lower = 0, upper = upper_bound},
        consumption = {lower = -80, upper = upper_bound},
        pollution = {lower = -80, upper = upper_bound}
    }

    local indications = {}
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

-- It's weird that this is the value used to determine the factor that the quality effect is
--   multiplied by, but this is how the game does it, so here we are
local quality_effect_factor = prototypes.quality["normal"].next_probability

---@param value EffectValue
---@param color string
---@param effect_name ModuleEffectName
---@return LocalisedString
local function format_effect(value, color, effect_name)
    if value == nil then return "" end
    value = (effect_name == "quality") and value * quality_effect_factor or value
    local format_string = (effect_name == "quality") and "%+.1f" or "%+d"
    local epsilon = (value < 0) and -1e-4 or 1e-4
    -- Force display of either a '+' or '-', also round the result
    return {"fp.effect_value", color, format_string:format(value + epsilon)}
end

---@class FormatModuleEffectsOptions
---@field indications { ModuleEffectName: string }?
---@field machine_effects IntegerModuleEffects?
---@field recipe_effects IntegerModuleEffects?

-- Formats the given effects for use in a tooltip
---@param module_effects IntegerModuleEffects
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
            local module_percentage = format_effect(module_effect, "#FFE6C0", effect_name)
            local machine_percentage = format_effect(machine_effect, "#7CFF01", effect_name)
            local recipe_percentage = format_effect(recipe_effect, "#01FFF4", effect_name)

            if #tooltip_lines > 1 then table.insert(tooltip_lines, "\n") end
            table.insert(tooltip_lines, {"fp.effect_line", {"fp." .. effect_name}, module_percentage,
                machine_percentage, recipe_percentage, options.indications[effect_name] or ""})
        end
    end

    if #tooltip_lines > 1 then return tooltip_lines
    else return {"fp.none"} end
end

return _effects
