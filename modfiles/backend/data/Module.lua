local Object = require("backend.data.Object")

---@class Module: Object, ObjectMethods
---@field class "Module"
---@field parent ModuleSet
---@field proto FPModulePrototype | FPPackedPrototype
---@field quality_proto FPQualityPrototype | FPPackedPrototype
---@field amount integer
---@field total_effects IntegerModuleEffects
---@field effects_tooltip LocalisedString
local Module = Object.methods()
Module.__index = Module
script.register_metatable("Module", Module)

---@param proto FPModulePrototype | FPPackedPrototype
---@param amount integer
---@param quality_proto FPQualityPrototype | FPPackedPrototype
---@return Module
local function init(proto, amount, quality_proto)
    local object = Object.init({
        proto = proto,
        quality_proto = quality_proto,
        amount = amount,

        total_effects = nil,
        effects_tooltip = ""
    }, "Module", Module)  ---@as Module

    if not proto.simplified then object:summarize_effects() end
    return object
end


function Module:index()
    OBJECT_INDEX[self.id] = self
end


---@return {name: string, quality: string}
function Module:elem_value()
    return {name=self.proto.name, quality=self.quality_proto.name}
end


---@param new_amount integer
function Module:set_amount(new_amount)
    self.amount = new_amount
    self.parent:count_modules()
    self:summarize_effects()
end


function Module:summarize_effects()
    ---@cast self.proto FPModulePrototype
    ---@cast self.quality_proto FPQualityPrototype

    local effects = lib.flib.shallow_copy(lib.effects.blank)

    for name, effect in pairs(self.proto.effects) do
        local base_effect = effect  ---@type number
        local module_multiplier = self.proto.quality_multipliers[name]
        if module_multiplier ~= 0 then
            local quality_multiplier = self.quality_proto.module_multipliers[name]
            base_effect = effect * (1 + module_multiplier * (quality_multiplier - 1))
        end

        effect = (base_effect < 0) and math.ceil(base_effect - 1e-4)
            or math.floor(base_effect + 1e-4)  -- truncate towards zero
        effects[name] = effect * self.amount  -- doesn't create decimals
    end

    self.total_effects = effects
    self.effects_tooltip = lib.effects.format(effects)
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Module:paste(object)
    if object.class == "Module" then
        ---@cast object Module
        if self.proto.simplified or self.quality_proto.simplified or object.proto.simplified or
           not self.parent:check_compatibility(object.proto--[[@as FPModulePrototype]]) then
            return false, "incompatible"
        end

        if self.proto == object.proto and self.quality_proto == object.quality_proto then
            local available_slots = self.parent.module_limit - self.parent.module_count + self.amount
            self:set_amount(math.min(object.amount, available_slots))

            self.parent:normalize({effects=true})
            return true, nil
        else
            local existing_module = self.parent:find({
                proto = object.proto--[[@as FPModulePrototype]],
                quality_proto = object.quality_proto--[[@as FPQualityPrototype]]
            }--[[@as ObjectFilter]])
            local parent = self.parent  -- retain here because it can be changed below

            if existing_module then
                local added_amount = math.min(object.amount, self.amount)
                existing_module:set_amount(existing_module.amount + added_amount)
                parent:remove(self)
            else
                object:set_amount(math.min(object.amount, self.amount))
                parent:replace(self, object)
            end

            parent:normalize({sort=true, effects=true})
            return true, nil
        end
    else
        return false, "incompatible_class"
    end
end


---@class PackedModule: PackedObject
---@field class "Module"
---@field proto FPPackedPrototype
---@field quality_proto FPPackedPrototype
---@field amount integer

---@param full boolean
---@return PackedModule packed_self
function Module:pack(full)
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),
        quality_proto = prototyper.util.simplify_prototype(self.quality_proto, nil),
        amount = self.amount
    }
end

---@param packed_self PackedModule
---@param parent ModuleSet
---@return Module module
local function unpack(packed_self, parent)
    -- Prototypes are unpacked at validate
    local unpacked_self = init(packed_self.proto, packed_self.amount, packed_self.quality_proto)

    unpacked_self.parent = parent

    return unpacked_self
end


---@return boolean valid
function Module:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")  ---@as FPModulePrototype | FPPackedPrototype
    self.valid = (not self.proto.simplified)

    self.quality_proto = prototyper.util.validate_prototype_object(self.quality_proto, nil)  ---@as FPQualityPrototype | FPPackedPrototype
    self.valid = (not self.quality_proto.simplified) and self.valid

    -- Can't be valid with an invalid parent
    self.valid = self.parent.parent.valid and self.parent.valid and self.valid

    -- Check whether the module is still compatible with its machine or beacon
    if self.valid then self.valid = self.parent:check_compatibility(self.proto--[[@as FPModulePrototype]]) end

    if self.valid then self:summarize_effects() end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Module:repair(player)
    self.valid = true

    if self.proto.simplified or not self.parent:check_compatibility(self.proto--[[@as FPModulePrototype]]) then
        self.valid = false  -- the module can not be salvaged in this case and will be removed
    end

    if self.valid and self.quality_proto.simplified then
        self.quality_proto = defaults.get_fallback("qualities").proto  ---@as FPQualityPrototype
    end

    if self.valid then self:summarize_effects() end

    return self.valid
end


return {init = init, unpack = unpack}
