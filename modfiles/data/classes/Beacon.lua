-- This is a 'class' representing a (group of) beacon(s) and the modules attached to it
Beacon = {}

-- Init a beacon without a module, which will have to be added afterwards
function Beacon.init(beacon_proto, beacon_amount, total_amount, parent_line)
    local beacon = {
        proto = beacon_proto,
        amount = beacon_amount or 0,
        total_amount = total_amount,
        Module = Collection.init("Module"),
        module_count = 0,  -- updated automatically
        total_effects = nil,
        effects_tooltip = "",
        valid = true,
        class = "Beacon"
    }
    -- Exceptionally set in the object init itself, because it'll be used before being added to a line
    beacon.parent = parent_line

    -- Initialize total_effects with all zeroes
    Beacon.summarize_effects(beacon)

    return beacon
end

-- lookup exists for internal purposes
function Beacon.clone(self, lookup)
    lookup = lookup or {}
    local new = {}
    lookup[self] = new
    for k, v in pairs(self) do
        new[k] = lookup[v] or v
    end
    new.Module = Collection.clone(new.Module, lookup)
    return new
end


function Beacon.add(self, object)
    object.parent = self
    local dataset = Collection.add(self[object.class], object)

    self.module_count = self.module_count + dataset.amount
    Beacon.normalize_modules(self, true, false)

    return dataset
end

function Beacon.remove(self, dataset)
    local removed_gui_position = Collection.remove(self[dataset.class], dataset)

    self.module_count = self.module_count - dataset.amount
    Beacon.normalize_modules(self, true, false)

    return removed_gui_position
end

function Beacon.replace(self, dataset, object)
    object.parent = self
    local module_count_difference = object.amount - dataset.amount
    local new_dataset = Collection.replace(self[dataset.class], dataset, object)

    self.module_count = self.module_count + module_count_difference
    Beacon.normalize_modules(self, true, false)

    return new_dataset
end

function Beacon.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Beacon.get_all(self, class)
    return Collection.get_all(self[class])
end

function Beacon.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end


-- Normalizes the modules of this beacon after they've been changed
function Beacon.normalize_modules(self, sort, trim)
    if sort then Beacon.sort_modules(self) end
    if trim then Beacon.trim_modules(self) end
    Line.summarize_effects(self.parent, false, true)
end

-- Sorts modules in a deterministic fashion so they are in the same order for every line
function Beacon.sort_modules(self)
    if global.all_modules == nil then return end

    local modules_by_name = {}
    for _, module in pairs(Beacon.get_all(self, "Module")) do
        modules_by_name[module.proto.name] = module
    end

    local next_position = 1
    for _, category in ipairs(global.all_modules.categories) do
        for _, module_proto in ipairs(category.modules) do
            local module = modules_by_name[module_proto.name]
            if module then
                module.gui_position = next_position
                next_position = next_position + 1
            end
        end
    end
end

-- Removes modules that may no longer fit
function Beacon.trim_modules(self)
    local module_count = self.module_count
    local module_limit = self.proto.module_limit or 0
    -- Return if the module count is within limits
    if module_count <= module_limit then return end

    -- Traverse modules in reverse to trim them off the end
    for _, module in ipairs(Beacon.get_in_order(self, "Module", true)) do
        local module_amount = module.amount
        -- Remove a whole module if it brings the count to >= limit
        if (module_count - module_amount) >= module_limit then
            -- Not using Beacon.remove to avoid triggering full sorting and line recalculation every time
            Collection.remove(self.Module, module)
            module_count = module_count - module_amount
        -- Otherwise, diminish the amount on the module appropriately and break
        else
            if module_count > module_limit then
                local new_amount = module_amount - (module_count - module_limit)
                -- Not using Module.change_amount to avoid triggering extra line recalculation
                module.amount = new_amount
                module_count = module_limit
            end
            break
        end
    end
    self.module_count = module_count

    -- Now recalculate
    Beacon.normalize_modules(self, true, false)
end


-- Summarizes the effects this Beacon has
function Beacon.summarize_effects(self)
    local module_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}
    local effect_multiplier = self.proto.effectivity * self.amount

    for _, module in pairs(Beacon.get_all(self, "Module")) do
        for name, effect in pairs(module.proto.effects) do
            module_effects[name] = module_effects[name] + (effect.bonus * module.amount * effect_multiplier)
        end

        module.effects_tooltip = data_util.format_module_effects(module.proto.effects, module.amount * effect_multiplier, false)
    end

    self.total_effects = module_effects
    self.effects_tooltip = data_util.format_module_effects(module_effects, 1, false)
end


function Beacon.empty_slot_count(self)
    return (self.proto.module_limit - self.module_count)
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

function Beacon.compile_module_filter(self)
    local compatible_modules = {}
    for module_name, module_proto in pairs(MODULE_NAME_MAP) do
        if Beacon.check_module_compatibility(self, module_proto) then
            table.insert(compatible_modules, module_name)
        end
    end

    return {{filter="name", name=compatible_modules}}
end


function Beacon.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        amount = self.amount,
        Module = Collection.pack(self.Module),
        module_count = self.module_count,
        total_amount = self.total_amount,
        class = self.class
    }
end

function Beacon.unpack(packed_self)
    local self = packed_self

    self.Module = Collection.unpack(packed_self.Module, self)
    -- Effects are summarized by the ensuing validation

    return self
end


-- Needs validation: proto, Module
function Beacon.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "beacons", nil)

    local machine = self.parent.machine  -- make sure the machine can still be influenced by beacons
    if machine.valid then self.valid = (machine.proto.allowed_effects ~= nil) and self.valid end

    self.valid = Collection.validate_datasets(self.Module) and self.valid
    if self.valid then Beacon.normalize_modules(self, true, true) end

    return self.valid
end

-- Needs repair: Module
function Beacon.repair(self, _)
    if self.proto.simplified then -- if still simplified, the beacon can't be repaired and needs to be removed
        self.parent.beacon = nil
    else  -- otherwise, the modules need to be checked and removed if necessary
        -- Remove invalid modules and normalize the remaining ones
        Collection.repair_datasets(self.Module, nil)
        Beacon.normalize_modules(self, true, true)

        if self.module_count == 0 then   -- if the beacon would be empty, it needs to be removed
            self.parent.beacon = nil
        end
    end

    -- no return necessary as the beacon will either be valid or have removed itself after repair
end
