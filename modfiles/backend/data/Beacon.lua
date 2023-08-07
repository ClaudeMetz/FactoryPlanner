local Object = require("backend.data.Object")

---@class Beacon: Object, ObjectMethods
---@field class "Beacon"
---@field parent Line
---@field proto FPBeaconPrototype | FPPackedPrototype
---@field amount number
---@field total_amount number?
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

        total_effects = nil,
        effects_tooltip = "",

        parent = parent
    }, "Beacon", Beacon)  --[[@as Beacon]]
    return object
end


function Beacon:index()
    OBJECT_INDEX[self.id] = self
end

function Beacon:cleanup()
    OBJECT_INDEX[self.id] = nil
end



---@param object CopyableObject
---@return boolean success
---@return string? error
function Beacon:paste(object)
    if object.class == "Beacon" then
        self.parent:set_beacon(object)
        --self.parent:summarize_effects()
        return true, nil
    --elseif object.class == "Module" and self.module_set ~= nil then
        -- Only allow modules to be pasted if this is a non-fake beacon
       --return ModuleSet.paste(self.module_set, object)
    else
        return false, "incompatible_class"
    end
end


---@class PackedBeacon: PackedObject
---@field class "Beacon"
---@field proto FPBeaconPrototype
---@field amount number
---@field total_amount number?

---@return PackedBeacon packed_self
function Beacon:pack()
    return {
        class = self.class,
        proto = prototyper.util.simplify_prototype(self.proto, nil),
        amount = self.amount,
        total_amount = self.total_amount
    }
end

---@param packed_self PackedBeacon
---@return Beacon machine
local function unpack(packed_self, parent)
    local unpacked_self = init(packed_self.proto, parent)
    unpacked_self.amount = packed_self.amount
    unpacked_self.total_amount = packed_self.total_amount


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

    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Beacon:repair(player)
    if self.proto.simplified then -- if still simplified, the beacon can't be repaired and needs to be removed
        return false
    else  -- otherwise, the modules need to be checked and removed if necessary
        -- Remove invalid modules and normalize the remaining ones
        --self.valid = ModuleSet.repair(self.module_set)

        --if self.module_set.module_count == 0 then return false end   -- if the beacon is empty, remove it
    end

    self.valid = true  -- if it gets to here, the beacon was successfully repaired
    return true
end

return {init = init, unpack = unpack}
