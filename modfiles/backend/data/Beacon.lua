local Object = require("backend.data.Object")
local ModuleSet = require("backend.data.ModuleSet")

---@class Beacon: Object, ObjectMethods
---@field class "Beacon"
---@field parent Line
---@field proto FPBeaconPrototype | FPPackedPrototype
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
    local effects = self.module_set:get_effects()
    local profile_mulitplier = self:profile_multiplier()
    local effect_multiplier = self.amount * profile_mulitplier * self.proto.effectivity

    for name, effect in pairs(effects) do
        effects[name] = effect * effect_multiplier
    end

    self.total_effects = effects
    self.effects_tooltip = util.gui.format_module_effects(effects)

    self.parent:summarize_effects()
end

---@return boolean uses_effects
function Beacon:uses_effects()
    local effect_receiver = self.parent.machine.proto.effect_receiver  --[[@as EffectReceiver]]
    return effect_receiver.uses_module_effects and effect_receiver.uses_beacon_effects
end


---@param object CopyableObject
---@return boolean success
---@return string? error
function Beacon:paste(object)
    if object.class == "Beacon" then
        self.parent:set_beacon(object)  -- weeds out incompatibilities
        if object.module_set.first == nil then
            object.parent:set_beacon(nil)
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
---@field amount number
---@field total_amount number?
---@field module_set PackedModuleSet

---@return PackedBeacon packed_self
function Beacon:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, nil),
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

    local machine = self.parent.machine  -- make sure the machine can still be influenced by beacons
    if machine.valid then self.valid = (machine.proto.allowed_effects ~= nil) and self.valid end

    self.valid = self.module_set:validate() and self.valid

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Beacon:repair(player)
    if self.proto.simplified then -- if still simplified, the beacon can't be repaired and needs to be removed
        return false
    else  -- otherwise, the modules need to be checked and removed if necessary
        -- Remove invalid modules and normalize the remaining ones
        self.valid = self.module_set:repair(player)

        if self.module_set.module_count == 0 then return false end   -- if the beacon became empty, remove it
    end

    self.valid = true  -- if it gets to here, the beacon was successfully repaired
    return true
end

return {init = init, unpack = unpack}
