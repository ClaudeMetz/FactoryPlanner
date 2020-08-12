-- This is a 'class' representing a (group of) beacon(s) and the modules attached to it
Beacon = {}

-- TODO potentially remove this and apply changes to beacons bit by bit instead of replacing them
function Beacon.init_by_protos(beacon_proto, beacon_amount, module_proto, module_amount, total_amount)
    local module = Module.init_by_proto(module_proto, module_amount)

    local beacon = {
        proto = beacon_proto,
        amount = beacon_amount,
        module = module,
        total_amount = total_amount,
        total_effects = nil,
        valid = true,
        class = "Beacon"
    }
    beacon.module.parent = beacon

    -- Initialise total_effects
    Beacon.summarize_effects(beacon)

    return beacon
end

-- Init a beacon without modules to compare the compatibility of potential modules to
function Beacon.blank_init(beacon_proto, beacon_amount, parent_line)
    local beacon = {
        proto = beacon_proto,
        amount = beacon_amount or 0,
        total_effects = nil,
        valid = true,
        class = "Beacon"
    }
    beacon.parent = parent_line

    -- Initialize total_effects with all zeroes
    Beacon.summarize_effects(beacon)

    return beacon
end


-- Exceptionally, a setter function to automatically run additional functionality
function Beacon.set_module(self, module)
    if module ~= nil then module.parent = self end
    self.module = module
    Line.summarize_effects(self.parent, false, true)
end


-- Removes modules that don't fit into the beacon anymore
function Beacon.trim_modules(self)
    self.module.amount = math.min(self.module.amount, self.proto.module_limit)
end

-- Summarizes the effects this Beacon has
function Beacon.summarize_effects(self)
    local module_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}

    if self.module ~= nil then
        for name, effect in pairs(self.module.proto.effects) do
            module_effects[name] = effect.bonus * self.module.amount * self.amount * self.proto.effectivity
        end
    end

    self.total_effects = module_effects
end


function Beacon.check_module_compatibility(self, module_proto)
    local compatible = true
    local recipe_proto, machine_proto = self.parent.recipe.proto, self.parent.machine.proto

    if table_size(module_proto.limitations) ~= 0 and recipe_proto.use_limitations
      and not module_proto.limitations[recipe_proto.name] then
        compatible = false
    end

    if compatible then
        local machine_effects, beacon_effects = machine_proto.allowed_effects, self.proto.allowed_effects
        if machine_effects == nil or beacon_effects == nil then
            compatible = false
        else
            for effect_name, _ in pairs(module_proto.effects) do
                if machine_effects[effect_name] == false or beacon_effects[effect_name] == false then
                    compatible = false
                    break
                end
            end
        end
    end

    return compatible
end

function Beacon.compile_module_filter(self)
    local compatible_modules = {}
    for module_name, module_proto in pairs(MODULE_NAME_MAP) do
        if Machine.check_module_compatibility(self, module_proto) then
            table.insert(compatible_modules, module_name)
        end
    end

    return {{filter="name", name=compatible_modules}}
end


function Beacon.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        amount = self.amount,
        module = Module.pack(self.module),
        total_amount = self.total_amount,
        class = self.class
    }
end

function Beacon.unpack(packed_self)
    local self = packed_self

    self.module = Module.unpack(packed_self.module)
    self.module.parent = self
    -- Effects are summarized by the ensuing validation

    return self
end


-- Needs validation: proto, module
function Beacon.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "beacons", nil)

    local machine = self.parent.machine  -- make sure the machine still can still be influenced by beacons
    if machine.valid then self.valid = (machine.proto.allowed_effects ~= nil) and self.valid end

    self.valid = Module.validate(self.module) and self.valid

    if self.valid then
        Beacon.trim_modules(self)
        Beacon.summarize_effects(self)
    end

    return self.valid
end

-- Needs repair:
function Beacon.repair(self, _)
    -- If the beacon is invalid at this point, meaning the prototypes are still simplified,
    -- it couldn't be fixed by validate, so it has to be removed
    self.parent.beacon = nil

    -- no return necessary
end