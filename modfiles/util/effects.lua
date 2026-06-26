local _effects = {}

_effects.blank = {speed = 0, productivity = 0, quality = 0, consumption = 0, pollution = 0}

---@alias EffectValue integer
---@alias ModuleEffectName "speed" | "productivity" | "quality" | "consumption" | "pollution"
---@alias IntegerModuleEffects { [ModuleEffectName]: EffectValue }

local is_effect_positive = {speed=true, productivity=true, quality=true,
                            consumption=false, pollution=false}

---@param proto FPMachinePrototype | FPBeaconPrototype | FPRecipePrototype
---@param module FPModulePrototype
---@return boolean
function _effects.is_compatible(proto, module)
    local allowed_categories = proto.allowed_module_categories
    -- No allowed categories means everything is compatible
    if allowed_categories ~= nil and not allowed_categories[module.category] then
        return false
    end

    local allowed_effects = proto.allowed_effects
    -- No allowed effects means nothing is compatible
    if allowed_effects == nil then return false end
    for name, value in pairs(module.effects) do
        -- Effects only need to be in the allowed list if they are considered positive
        -- Effects are considered positive if their effect is actually in the
        -- 'desirable' direction, ie. positive speed, or negative pollution
        if not allowed_effects[name] and (value > 0) == is_effect_positive[name] then
            return false
        end
    end

    return true
end


---@param effect_tables IntegerModuleEffects[]
---@return IntegerModuleEffects
function _effects.merge(effect_tables)
    local effects = util.flib.shallow_copy(util.effects.blank)
    for _, effect_table in pairs(effect_tables) do
        for name, effect in pairs(effect_table) do
            effects[name] = effects[name] + effect  -- doesn't create decimals
        end
    end
    return effects
end


---@param effect EffectValue
---@param bounds EffectValueRange
function _effects.limit_value(effect, bounds)
    local low_bound = bounds.low * MAGIC_NUMBERS.effect_precision
    local high_bound = bounds.high * MAGIC_NUMBERS.effect_precision

    if effect < low_bound then
        return low_bound, "[img=fp_limited_down]"
    elseif effect > high_bound then
        return high_bound, "[img=fp_limited_up]"
    else
        return effect, nil
    end
end

---@param effects IntegerModuleEffects
---@param effect_receiver FormattedEffectReceiver
---@return IntegerModuleEffects
---@return { ModuleEffectName: string }
function _effects.limit(effects, effect_receiver)
    local indications = {}

    -- Bound effects and note the indication if relevant
    for name, effect in pairs(effects) do
        local bounds = effect_receiver.limits[name]
        effects[name], indications[name] = _effects.limit_value(effect, bounds)
    end

    return effects, indications
end


---@param value EffectValue
---@param color string
---@param effect_name ModuleEffectName
---@return LocalisedString
local function format_effect(value, color)
    if value == nil then return "" end
    local epsilon = (value < 0) and -1e-4 or 1e-4
    -- Turn value into percentage, and divide out precision multiplier
    local percentage = value * 100 / MAGIC_NUMBERS.effect_precision + epsilon
    -- Show leading sign, two decimals, and remove trailing zeros
    local effect = ("%+.2f"):format(percentage):gsub("%.?0+$", "")
    return {"fp.effect_value", color, effect}
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
    for effect_name, _ in pairs(util.effects.blank) do
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

    if #tooltip_lines > 1 then return tooltip_lines
    else return {"fp.none"} end
end

return _effects
