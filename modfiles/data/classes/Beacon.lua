-- This is a 'class' representing a (group of) beacon(s) and the modules attached to it
Beacon = {}

function Beacon.init(beacon_proto, beacon_amount, total_amount, parent)
    local beacon = {
        proto = beacon_proto,
        amount = beacon_amount or 0,
        total_amount = total_amount,  -- can be nil
        module_set = nil,  -- set right below
        total_effects = nil,
        effects_tooltip = "",
        valid = true,
        class = "Beacon",
        parent = parent
    }
    beacon.module_set = ModuleSet.init(beacon)

    return beacon
end


function Beacon.summarize_effects(self)
    local effect_multiplier = self.proto.effectivity * self.amount
    local effects = self.module_set.total_effects
    for name, effect in pairs(effects) do
        effects[name] = effect * effect_multiplier
    end
    self.total_effects = effects
    self.effects_tooltip = data_util.format_module_effects(effects, false)

    Line.summarize_effects(self.parent)
end

function Beacon.check_module_compatibility(self, module_proto)
    local recipe_proto, machine_proto = self.parent.recipe.proto, self.parent.machine.proto

    if table_size(module_proto.limitations) ~= 0 and recipe_proto.use_limitations
      and not module_proto.limitations[recipe_proto.name] then
        return false
    end

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


function Beacon.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        amount = self.amount,
        total_amount = self.total_amount,
        module_set = ModuleSet.pack(self.module_set),
        class = self.class
    }
end

function Beacon.unpack(packed_self)
    local self = packed_self

    self.module_set = ModuleSet.unpack(packed_self.module_set)
    self.module_set.parent = self

    return self
end


-- Needs validation: proto, module_set
function Beacon.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "beacons", nil)

    local machine = self.parent.machine  -- make sure the machine can still be influenced by beacons
    if machine.valid then self.valid = (machine.proto.allowed_effects ~= nil) and self.valid end

    self.valid = ModuleSet.validate(self.module_set)

    return self.valid
end

-- Needs repair: module_set
function Beacon.repair(self, _)
    if self.proto.simplified then -- if still simplified, the beacon can't be repaired and needs to be removed
        return false
    else  -- otherwise, the modules need to be checked and removed if necessary
        -- Remove invalid modules and normalize the remaining ones
        self.valid = ModuleSet.repair(self.module_set)

        if self.module_set.module_count == 0 then return false end   -- if the beacon is empty, remove it
    end

    self.valid = true  -- if it gets to here, the beacon was successfully repaired
    return true
end
