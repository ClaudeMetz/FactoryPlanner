local Object = require("backend.data.Object")

---@class Module: Object, ObjectMethods
---@field class "Module"
---@field parent ModuleSet
---@field proto FPModulePrototype | FPPackedPrototype
---@field quality_proto FPQualityPrototype
---@field amount integer
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
local Module = Object.methods()
Module.__index = Module
script.register_metatable("Module", Module)

---@param proto FPModulePrototype | FPPackedPrototype
---@param amount integer
---@param quality_proto FPQualityPrototype
---@return Module
local function init(proto, amount, quality_proto)
    local object = Object.init({
        proto = proto,
        quality_proto = quality_proto,
        amount = amount,

        total_effects = nil,
        effects_tooltip = ""
    }, "Module", Module)  --[[@as Module]]
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
    local effects = ftable.shallow_copy(BLANK_EFFECTS)
    for name, effect in pairs(self.proto.effects) do
        local is_positive = util.effects.is_positive(name, effect)
        local multiplier = (is_positive) and self.quality_proto.multiplier or 1
        effects[name] = effect * self.amount * multiplier
    end

    self.total_effects = effects
    self.effects_tooltip = util.effects.format(effects)
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Module:paste(object)
    if object.class == "Module" then
        ---@cast object Module
        if self.parent:check_compatibility(object.proto) then
            if self.parent:find({proto=object.proto, quality_proto=self.quality_proto}) then
                return false, "already_exists"
            else
                object.amount = math.min(object.amount, self.amount + self.parent.empty_slots)
                object:summarize_effects()

                self.parent:replace(self, object)
                self.parent:normalize{effects=true}
                return true, nil
            end
        else
            return false, "incompatible"
        end
    else
        return false, "incompatible_class"
    end
end


---@class PackedModule: PackedObject
---@field class "Module"
---@field proto FPModulePrototype
---@field quality_proto FPQualityPrototype
---@field amount integer

---@return PackedModule packed_self
function Module:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, "category"),
        quality_proto = prototyper.util.simplify_prototype(self.quality_proto, nil),
        amount = self.amount
    }
end

---@param packed_self PackedModule
---@return Module module
local function unpack(packed_self)
    local unpacked_self = init(packed_self.proto, packed_self.amount)
    unpacked_self.quality_proto = packed_self.quality_proto

    return unpacked_self
end


---@return boolean valid
function Module:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, "category")
    self.valid = (not self.proto.simplified)

    self.quality_proto = prototyper.util.validate_prototype_object(self.quality_proto, nil)
    self.valid = (not self.quality_proto.simplified) and self.valid

    -- Check whether the module is still compatible with its machine or beacon
    if self.valid and self.parent and self.parent.valid then
        self.valid = self.parent:check_compatibility(self.proto)
    end

    if self.valid then self:summarize_effects() end

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Module:repair(player)
    if self.proto.simplified or not self.parent:check_compatibility(self.proto) then
        return false  -- the module can not be salvaged in this case and will be removed
    else  -- otherwise, the quality just needs to be reset
        self.quality_proto = defaults.get_fallback("qualities").proto
    end

    self.valid = true  -- if it gets to here, the module was successfully repaired
    self:summarize_effects()
    return true
end


return {init = init, unpack = unpack}
