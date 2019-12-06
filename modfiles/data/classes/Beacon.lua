-- This is a 'class' representing a (group of) beacon(s) and the modules attached to it
Beacon = {}

function Beacon.init_by_protos(beacon_proto, beacon_amount, module_proto, module_amount, total_amount)
    local module = Module.init_by_proto(module_proto, module_amount)
    local beacon = {
        proto = beacon_proto,
        amount = beacon_amount,
        module = module,  -- Module-object
        total_amount = total_amount,
        total_effects = nil,
        valid = true,
        class = "Beacon"
    }
    beacon.module.parent = beacon

    -- Initialise the total_effects
    Beacon.summarize_effects(beacon)

    return beacon
end


-- Exceptionally, a setter function to automatically run additional functionality
function Beacon.set_module(self, module, no_recursion)
    if module ~= nil then module.parent = self end
    self.module = module
    
    if self.parent.subfloor ~= nil and not no_recursion then
        local sub_line = Floor.get(self.parent.subfloor, "Line", 1)
        Beacon.set_module(sub_line.beacon, cutil.deepcopy(module), true)
    elseif self.parent.id == 1 and self.parent.parent.origin_line and not no_recursion then
        Beacon.set_module(self.parent.parent.origin_line.beacon, cutil.deepcopy(module), true)
    end

    Beacon.summarize_effects(self)
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

-- Removes modules that don't fit into the beacon anymore
function Beacon.trim_modules(self)
    self.module.amount = math.min(self.module.amount, self.proto.module_limit)
end


-- Update the validity of this beacon
function Beacon.update_validity(self)
    local proto_name = (type(self.proto) == "string") and self.proto or self.proto.name
    local new_beacon_id = new.all_beacons.map[proto_name]
    
    if new_beacon_id ~= nil then
        self.proto = new.all_beacons.beacons[new_beacon_id]
        self.valid = true
    else
        self.proto = self.proto.name
        self.valid = false
    end
    
    if not Module.update_validity(self.module) then
        self.valid = false
    end

    -- Check excessive module amounts
    if self.valid and self.module.amount > self.proto.module_limit then
        self.valid = false
    end

    if self.valid and self.parent.machine.proto.allowed_effects == nil then
        self.valid = false
    end
    
    -- Update effects if this beacon is still valid
    if self.valid then
        Beacon.summarize_effects(self)
    end

    return self.valid
end

-- Tries to repair this beacon, deletes it otherwise (by returning false)
-- If this is called, the beacon is invalid and has a string saved to proto
function Beacon.attempt_repair(self, player)
    local current_beacon_id = global.all_beacons.map[self.proto]
    if current_beacon_id ~= nil then
        self.proto = global.all_beacons.beacons[current_beacon_id]
        self.valid = true
    end

    -- Trim module amount if necessary
    if self.valid then Beacon.trim_modules(self) end

    -- Update effects if this beacon is still valid
    if self.valid then Beacon.summarize_effects(self) end

    return self.valid
end