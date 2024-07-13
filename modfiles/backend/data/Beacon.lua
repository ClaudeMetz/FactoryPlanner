local Object = require("backend.data.Object")
local ModuleSet = require("backend.data.ModuleSet")

---@class Beacon: Object, ObjectMethods
---@field class "Beacon"
---@field parent Line
---@field proto FPBeaconPrototype | FPPackedPrototype
---@field amount number
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


function Beacon:summarize_effects()
    local effect_multiplier = self.proto.effectivity * self.amount
    local effects = self.module_set.total_effects
    for name, effect in pairs(effects) do
        effects[name] = effect * effect_multiplier
    end
    self.total_effects = effects
    self.effects_tooltip = util.gui.format_module_effects(effects, false)

    self.parent:summarize_effects()
end

---@param module_proto FPModulePrototype
---@return boolean compatible
function Beacon:check_module_compatibility(module_proto)
    local machine_proto = self.parent.machine.proto
    local machine_effects, beacon_effects = machine_proto.allowed_effects, self.proto.allowed_effects

    if machine_effects == nil or beacon_effects == nil then
        return false
    else
        for effect_name, _ in pairs(module_proto.effects) do
            if machine_effects[effect_name] == false or beacon_effects[effect_name] == false then
                return false
            end
        end
    end

    return true
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

    if BEACON_OVERLOAD_ACTIVE then self.amount = 1 end

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
        self.valid = self.module_set:repair()

        if self.module_set.module_count == 0 then return false end   -- if the beacon is empty, remove it
    end

    self.valid = true  -- if it gets to here, the beacon was successfully repaired
    return true
end

return {init = init, unpack = unpack}
