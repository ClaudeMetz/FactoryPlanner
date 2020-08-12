-- Class representing a machine with its attached modules and fuel
Machine = {}

-- Initialised by passing a prototype from the all_machines global table
function Machine.init_by_proto(proto)
    local machine = {
        proto = proto,
        count = 0,
        limit = nil,  -- will be set by the user
        hard_limit = false,
        fuel = nil,  -- updated by Line.change_machine()
        Module = Collection.init("Module"),
        module_count = 0,  -- updated automatically
        total_effects = nil,
        valid = true,
        class = "Machine"
    }

    -- Initialise total_effects
    Machine.summarize_effects(machine)

    return machine
end


function Machine.add(self, object)
    object.parent = self
    local dataset = Collection.add(self[object.class], object)

    self.module_count = self.module_count + dataset.amount
    Machine.normalize_modules(self, true, false)

    return dataset
end

function Machine.remove(self, dataset)
    local removed_gui_position = Collection.remove(self[dataset.class], dataset)

    self.module_count = self.module_count - dataset.amount
    Machine.normalize_modules(self, true, false)

    return removed_gui_position
end

function Machine.replace(self, dataset, object)
    object.parent = self
    local module_count_difference = object.amount - dataset.amount
    local new_dataset = Collection.replace(self[dataset.class], dataset, object)

    self.module_count = self.module_count + module_count_difference
    Machine.normalize_modules(self, true, false)

    return new_dataset
end

function Machine.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Machine.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end


function Machine.find_fuel(self, player)
    if self.fuel == nil and self.proto.energy_type == "burner" then
        local burner = self.proto.burner

        -- Use the first category of this machine's burner as the default one
        local fuel_category_name, _ = next(burner.categories, nil)
        local fuel_category_id = global.all_fuels.map[fuel_category_name]

        local default_fuel_proto = prototyper.defaults.get(player, "fuels", fuel_category_id)
        self.fuel = Fuel.init_by_proto(default_fuel_proto)
        self.fuel.parent = self
    end
end


function Machine.summarize_effects(self)
    local module_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}

    -- Machine base productivity
    module_effects.productivity = module_effects.productivity + self.proto.base_productivity

    -- Module productivity
    for _, module in pairs(Machine.get_in_order(self, "Module")) do
        for name, effect in pairs(module.proto.effects) do
            module_effects[name] = module_effects[name] + (effect.bonus * module.amount)
        end
    end

    self.total_effects = module_effects
end


function Machine.empty_slot_count(self)
    return (self.proto.module_limit - self.module_count)
end

function Machine.check_module_compatibility(self, module_proto)
    local compatible = true
    local recipe = self.parent.recipe

    if table_size(module_proto.limitations) ~= 0 and recipe.proto.use_limitations
      and not module_proto.limitations[recipe.proto.name] then
        compatible = false
    end

    if compatible then
        local allowed_effects = self.proto.allowed_effects
        if allowed_effects == nil then
            compatible = false
        else
            for effect_name, _ in pairs(module_proto.effects) do
                if allowed_effects[effect_name] == false then
                    compatible = false
                end
            end
        end
    end

    return compatible
end

function Machine.compile_module_filter(self)
    local existing_names = {}
    for _, module in ipairs(Machine.get_in_order(self, "Module")) do
        existing_names[module.proto.name] = true
    end

    local compatible_modules = {}
    for module_name, module_proto in pairs(MODULE_NAME_MAP) do
        if Machine.check_module_compatibility(self, module_proto) and not existing_names[module_name] then
            table.insert(compatible_modules, module_name)
        end
    end

    return {{filter="name", name=compatible_modules}}
end


-- Normalizes the modules of this machine after they've been changed
function Machine.normalize_modules(self, sort, trim)
    if sort then Machine.sort_modules(self) end
    if trim then Machine.trim_modules(self) end
    Line.summarize_effects(self.parent, true, false)
end

-- Sorts modules in a deterministic fashion so they are in the same order for every line
-- Not a very efficient algorithm, but totally fine for the small (<10) amount of datasets
function Machine.sort_modules(self)
    local next_position = 1
    local new_gui_positions = {}

    if global.all_modules == nil then return end
    for _, category in ipairs(global.all_modules.categories) do
        for _, module_proto in ipairs(category.modules) do
            for _, module in ipairs(Machine.get_in_order(self, "Module")) do
                if module.proto.category == category.name and module.proto.name == module_proto.name then
                    table.insert(new_gui_positions, {module = module, new_pos = next_position})
                    next_position = next_position + 1
                end
            end
        end
    end

    -- Actually set the new gui positions
    for _, new_position in pairs(new_gui_positions) do
        new_position.module.gui_position = new_position.new_pos
    end
end

-- Trims superflous modules off the end (might be needed when the machine is downgraded)
function Machine.trim_modules(self)
    local module_count = self.module_count
    local module_limit = self.proto.module_limit or 0
    -- Return if the module count is within limits
    if module_count <= module_limit then return end

    local modules_to_remove = {}
    -- Traverse modules in reverse to trim them off the end
    for _, module in ipairs(Machine.get_in_order(self, "Module", true)) do
        -- Remove a whole module if it brings the count to >= limit
        if (module_count - module.amount) >= module_limit then
            table.insert(modules_to_remove, module)
            module_count = module_count - module.amount

        -- Otherwise, diminish the amount on the module appropriately and break
        else
            local new_amount = module.amount - (module_count - module_limit)
            Module.change_amount(module, new_amount)
            break
        end
    end

    -- Remove superfluous modules (no re-sorting necessary)
    for _, module in pairs(modules_to_remove) do
        Machine.remove(self, module)
    end
end


function Machine.pack(self)
    return {
        proto = prototyper.util.simplify_prototype(self.proto),
        limit = self.limit,
        hard_limit = self.hard_limit,
        fuel = (self.fuel) and Fuel.pack(self.fuel) or nil,
        Module = Collection.pack(self.Module),
        module_count = self.module_count,
        class = self.class
    }
end

function Machine.unpack(packed_self)
    local self = packed_self
    self.fuel = (packed_self.fuel) and Fuel.unpack(packed_self.fuel) or nil
    if self.fuel then self.fuel.parent = self end

    self.Module = Collection.unpack(packed_self.Module, self)
    -- Effects are summarized by the ensuing validation

    return self
end


-- Needs validation: proto, fuel, Module
function Machine.validate(self)
    self.valid = prototyper.util.validate_prototype_object(self, "proto", "machines", "category")

    local parent_line = self.parent
    if self.valid and parent_line.valid and parent_line.recipe.valid then
        self.valid = Line.is_machine_applicable(parent_line, self.proto)
    end

    if self.fuel then self.valid = Fuel.validate(self.fuel) and self.valid end

    self.valid = Collection.validate_datasets(self.Module) and self.valid
    if self.valid then Machine.normalize_modules(self, true, true) end

    return self.valid
end

-- Needs repair: proto, fuel, Module
function Machine.repair(self, player)
    -- If the prototype is still simplified, it couldn't be fixed by validate
    -- A final possible fix is to replace this machine with the default for its category
    if self.proto.simplified and not Line.change_machine(self.parent, player, nil, nil) then
        return false
    end
    self.valid = true  -- the machine is valid from this point on

    if self.fuel and not self.fuel.valid then Fuel.repair(self.fuel, player) end

    -- Remove invalid modules and normalize the remaining ones
    Collection.repair_datasets(self.Module, nil)
    Machine.normalize_modules(self, true, true)

    return self.valid
end