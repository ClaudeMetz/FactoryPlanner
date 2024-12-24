local Object = require("backend.data.Object")
local ModuleSet = require("backend.data.ModuleSet")

---@class Beacon: Object, ObjectMethods
---@field class "Beacon"
---@field parent Line
---@field proto FPBeaconPrototype | FPPackedPrototype
---@field quality_proto FPQualityPrototype
---@field amount integer
---@field total_amount number?
---@field module_set ModuleSet
---@field total_effects ModuleEffects
---@field effects_tooltip LocalisedString
local Beacon = Object.methods()
Beacon.__index = Beacon
script.register_metatable("Beacon", Beacon)

---@param proto FPBeaconPrototype
---@param parent Line
---@return Beacon
local function init(proto, parent)
    local object = Object.init({
        proto = proto,
        quality_proto = defaults.get_fallback("qualities").proto,
        amount = 0,
        total_amount = nil,
        module_set = nil,

        total_effects = nil,
        effects_tooltip = "",

        parent = parent
    }, "Beacon", Beacon)  --[[@as Beacon]]
    object.module_set = ModuleSet.init(object)
    return object
end


function Beacon:index()
    OBJECT_INDEX[self.id] = self
    self.module_set:index()
end


---@return {name: string, quality: string}
function Beacon:elem_value()
    return {name=self.proto.name, quality=self.quality_proto.name}
end


---@return double profile_multiplier
function Beacon:profile_multiplier()
    if self.amount == 0 then
        return 0
    else
        local profile_count = #self.proto.profile
        local index = (self.amount > profile_count) and profile_count or self.amount
        return self.proto.profile[index]
    end
end


function Beacon:summarize_effects()
    local profile_mulitplier = self:profile_multiplier()
    local effectivity = self.proto.effectivity + (self.quality_proto.level * self.proto.quality_bonus)
    local effect_multiplier = self.amount * profile_mulitplier * effectivity

    local effects = self.module_set:get_effects()
    for name, effect in pairs(effects) do
        effects[name] = effect * effect_multiplier
    end

    self.total_effects = effects
    self.effects_tooltip = util.effects.format(effects)

    self.parent:summarize_effects()
end

---@return boolean uses_effects
function Beacon:uses_effects()
    -- This method is here for ModuleSet to use generically
    return self.parent:uses_beacon_effects()
end


---@param player LuaPlayer
function Beacon:reset(player)
    local beacon_default = defaults.get(player, "beacons", nil)

    self.proto = beacon_default.proto  --[[@as FPBeaconPrototype]]
    self.quality_proto = beacon_default.quality
    if beacon_default.beacon_amount then self.amount = beacon_default.beacon_amount end

    self.module_set:clear()
    if beacon_default.modules then self.module_set:ingest_default(beacon_default.modules) end
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Beacon:paste(object)
    if object.class == "Beacon" then
        self.parent:set_beacon(object)
        if not object.module_set.first then
            self.parent:set_beacon(nil)
            return false, "incompatible"
        else
            return true, nil
        end
    elseif object.class == "Module" and self.module_set ~= nil then
        -- Only allow modules to be pasted if this is a non-fake beacon
       return self.module_set:paste(object)
    else
        return false, "incompatible_class"
    end
end


---@class PackedBeacon: PackedObject
---@field class "Beacon"
---@field proto FPBeaconPrototype
---@field quality_proto FPQualityPrototype
---@field amount number
---@field total_amount number?
---@field module_set PackedModuleSet

---@return PackedBeacon packed_self
function Beacon:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, nil),
        quality_proto = prototyper.util.simplify_prototype(self.quality_proto, nil),
        amount = self.amount,
        total_amount = self.total_amount,
        module_set = self.module_set:pack()
    }
end

---@param packed_self PackedBeacon
---@param parent Line
---@return Beacon machine
local function unpack(packed_self, parent)
    local unpacked_self = init(packed_self.proto, parent)
    unpacked_self.quality_proto = packed_self.quality_proto
    unpacked_self.amount = packed_self.amount
    unpacked_self.total_amount = packed_self.total_amount
    unpacked_self.module_set = ModuleSet.unpack(packed_self.module_set, unpacked_self)

    return unpacked_self
end

---@return Beacon clone
function Beacon:clone()
    local clone = unpack(self:pack(), self.parent)
    clone:validate()
    return clone
end


---@return boolean valid
function Beacon:validate()
    self.proto = prototyper.util.validate_prototype_object(self.proto, nil)
    self.valid = (not self.proto.simplified)

    self.quality_proto = prototyper.util.validate_prototype_object(self.quality_proto, nil)
    self.valid = (not self.quality_proto.simplified) and self.valid

    self.valid = self.parent:uses_beacon_effects() and self.valid
    self.valid = self.module_set:validate() and self.valid

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Beacon:repair(player)
    self.valid = true

    if self.proto.simplified or not self.parent:uses_beacon_effects() then
        self.valid = false  -- this situation can't be repaired
        -- This could try another beacon, but it's not really worth it
    end

    if self.valid and self.quality_proto.simplified then
        self.quality_proto = defaults.get_fallback("qualities").proto
    end

    if self.valid then
        self.module_set:repair(player)  -- always becomes valid
        if self.module_set.module_count == 0 then self.valid = false end
    end

    return self.valid
end

return {init = init, unpack = unpack}
