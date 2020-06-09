-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(player, recipe)
    local line = {
        recipe = recipe,
        percentage = 100,
        machine = nil,
        Module = Collection.init(),
        beacon = nil,
        total_effects = nil,
        energy_consumption = 0,
        pollution = 0,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        fuel = nil,
        priority_product_proto = nil,  -- will be set by the user
        comment = nil,
        production_ratio = 0,
        uncapped_production_ratio = 0, -- used to calculate machine choice numbers
        subfloor = nil,
        valid = true,
        class = "Line"
    }

    -- Return false if no fitting machine can be found (needs error handling on the other end)
    if Line.change_machine(line, player, nil, nil) == false then return false end

    -- Initialise total_effects
    Line.summarize_effects(line)

    return line
end


-- Sets the priority_product_proto on this line and optionally it's subfloor / parent line
function Line.set_priority_product(self, proto)
    self.priority_product_proto = proto
    -- Can't use pack/unpack method as it doesn't work for proto being nil
    if self.subfloor ~= nil then
        local sub_line = Floor.get(self.subfloor, "Line", 1)
        sub_line.priority_product_proto = proto
    elseif self.id == 1 and self.parent.origin_line then
        self.parent.origin_line.priority_product_proto = proto
    end
end

-- Sets the machine's limit on this line and optionally it's subfloor / parent line
function Line.set_machine_limit(self, limit, hard_limit)
    self.machine.limit, self.machine.hard_limit = limit, hard_limit
    -- Can't use pack/unpack method as it doesn't work for proto being nil
    if self.subfloor ~= nil then
        local machine = Floor.get(self.subfloor, "Line", 1).machine
        machine.limit, machine.hard_limit = limit, hard_limit
    elseif self.id == 1 and self.parent.origin_line then
        local machine = self.parent.origin_line.machine
        machine.limit, machine.hard_limit = limit, hard_limit
    end
end


-- Changes the amount of the given module on this line and optionally it's subfloor / parent line
function Line.change_module_amount(self, module, new_amount, secondary)
    module.amount = new_amount

    -- (This could theoretically use Line.carry_over_changes, but it's too different to be worth it)
    if self.subfloor ~= nil and not secondary then
        local sub_line = Floor.get(self.subfloor, "Line", 1)
        local sub_module = Line.get_by_name(sub_line, "Module", module.proto.name)
        Line.change_module_amount(self, sub_module, new_amount, true)
    elseif self.id == 1 and self.parent.origin_line and not secondary then
        local parent_module = Line.get_by_name(self.parent.origin_line, "Module", module.proto.name)
        Line.change_module_amount(self.parent.origin_line, parent_module, new_amount, true)
    end

    Line.summarize_effects(self)
end

-- Sets the given beacon on this line and optionally it's subfloor / parent line (Beacon can't be nil)
function Line.set_beacon(self, beacon, secondary)
    beacon.parent = self
    self.beacon = beacon

    Line.carry_over_changes(self, Line.set_beacon, secondary, table.pack(cutil.deepcopy(beacon)))
    Beacon.trim_modules(self.beacon)
    Line.summarize_effects(self)
end

-- Use this if you want to remove the beacon from this line
function Line.remove_beacon(self, secondary)
    self.beacon = nil
    Line.carry_over_changes(self, Line.remove_beacon, secondary, {})
    Line.summarize_effects(self)
end


function Line.add(self, object, secondary)
    object.parent = self
    local dataset = Collection.add(self[object.class], object)

    if dataset.class == "Module" then
        Line.carry_over_changes(self, Line.add, secondary, table.pack(cutil.deepcopy(object)))
        Line.normalize_modules(self)
    end

    return dataset
end

function Line.remove(self, dataset, secondary)
    if dataset.class == "Module" then
        Line.carry_over_changes(self, Line.remove, secondary, table.pack(cutil.deepcopy(dataset)))
    end

    local removed_gui_position = Collection.remove(self[dataset.class], dataset)
    if dataset.class == "Module" then Line.normalize_modules(self) end

    return removed_gui_position
end

function Line.replace(self, dataset, object, secondary)
    local dataset = Collection.replace(self[dataset.class], dataset, object)

    if dataset.class == "Module" then
        Line.carry_over_changes(self, Line.replace, secondary, table.pack(cutil.deepcopy(dataset), object))
        Line.normalize_modules(self)
    end

    return dataset
end


function Line.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Line.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Line.get_by_gui_position(self, class, gui_position)
    return Collection.get_by_gui_position(self[class], gui_position)
end

function Line.get_by_name(self, class, name)
    return Collection.get_by_name(self[class], name)
end

function Line.shift(self, dataset, direction)
    return Collection.shift(self[dataset.class], dataset, direction)
end


-- Carries the changes to this Line over to it's origin_line and subfloor, whichever applies
function Line.carry_over_changes(self, f, secondary, arg)
    if not secondary then
        table.insert(arg, true)  -- add indication that this is a secondary call

        if self.subfloor ~= nil then
            local sub_line = Floor.get(self.subfloor, "Line", 1)
            f(sub_line, unpack(arg))
        elseif self.id == 1 and self.parent.origin_line then
            f(self.parent.origin_line, unpack(arg))
        end
    end
end


-- Returns whether the given machine can be used for this line/recipe
function Line.is_machine_applicable(self, machine_proto)
    local recipe_proto = self.recipe.proto
    local valid_ingredient_count = (machine_proto.ingredient_limit >= recipe_proto.type_counts.ingredients.items)
    local valid_input_channels = (machine_proto.fluid_channels.input >= recipe_proto.type_counts.ingredients.fluids)
    local valid_output_channels = (machine_proto.fluid_channels.output >= recipe_proto.type_counts.products.fluids)

    return (valid_ingredient_count and valid_input_channels and valid_output_channels)
end

-- Changes the machine either to the given machine or moves it in the given direction
-- Returns false if no machine is applied because none can be found, true otherwise
function Line.change_machine(self, player, machine, direction)
    -- Set the machine to the default one
    if machine == nil and direction == nil then
        local machine_category_id = global.all_machines.map[self.recipe.proto.category]
        local default_machine = prototyper.defaults.get(player, "machines", machine_category_id)
        -- If no default machine is found, this category has no machines
        if default_machine == nil then return false end
        return Line.change_machine(self, player, default_machine, nil)

    -- Set machine directly
    elseif machine ~= nil and direction == nil then
        local new_machine = (machine.proto ~= nil) and machine or Machine.init_by_proto(machine)
        -- Try setting a higher tier machine until it sticks or nothing happens
        -- Returns false if no machine fits at all, so an appropriate error can be displayed
        if not Line.is_machine_applicable(self, new_machine.proto) then
            return Line.change_machine(self, player, new_machine, "positive")

        else
            -- Check if the fuel is still compatible, remove it otherwise
            if not (self.machine and self.fuel and new_machine.proto.energy_type == "burner"
              and new_machine.proto.burner.categories[self.fuel.proto.category]) then
                self.fuel = nil
            end

            -- Carry over the machine limit
            if new_machine and self.machine then
                new_machine.limit = self.machine.limit
                new_machine.hard_limit = self.machine.hard_limit
            end
            self.machine = new_machine

            -- Adjust parent line
            if self.parent then  -- if no parent exists, nothing is overwritten anyway
                if self.subfloor then
                    Floor.get(self.subfloor, "Line", 1).machine = self.machine
                elseif self.id == 1 and self.parent.origin_line then
                    self.parent.origin_line.machine = self.machine
                end
            end

            -- Adjust modules (ie. trim them if needed)
            Line.trim_modules(self)
            Line.summarize_effects(self)

            -- Adjust beacon (ie. remove if machine does not allow beacons)
            if self.machine.proto.allowed_effects == nil then Line.remove_beacon(self) end

            return true
        end

    -- Bump machine in the given direction (takes given machine, if available)
    elseif direction ~= nil then
        local category, proto
        if machine ~= nil then
            if machine.proto then
                category = machine.category
                proto = machine.proto
            else
                category = global.all_machines.categories[global.all_machines.map[machine.category]]
                proto = machine
            end
        else
            category = self.machine.category
            proto = self.machine.proto
        end

        if direction == "positive" then
            if proto.id < #category.machines then
                local new_machine = category.machines[proto.id + 1]
                return Line.change_machine(self, player, new_machine, nil)
            else
                local message = {"fp.error_object_cant_be_up_downgraded", {"fp.machine"}, {"fp.upgraded"}}
                ui_util.message.enqueue(player, message, "error", 1, false)
                return false
            end
        else  -- direction == "negative"
            if proto.id > 1 then
                local new_machine = category.machines[proto.id - 1]
                return Line.change_machine(self, player, new_machine, nil)
            else
                local message = {"fp.error_object_cant_be_up_downgraded", {"fp.machine"}, {"fp.downgraded"}}
                ui_util.message.enqueue(player, message, "error", 1, false)
                return false
            end
        end
    end
end


-- Normalizes the modules of this Line after they've been changed
function Line.normalize_modules(self)
    Line.sort_modules(self)
    Line.summarize_effects(self)
end

-- Returns the total amount of modules associated with this line
function Line.count_modules(self)
    local module_count = 0
    for _, module in ipairs(Line.get_in_order(self, "Module")) do
        module_count = module_count + module.amount
    end
    return module_count
end

-- Returns the amount of empty slots this line has
function Line.empty_slots(self)
    return (self.machine.proto.module_limit - Line.count_modules(self))
end


-- Returns a table containing all relevant data for the given module in relation to this Line
function Line.get_module_characteristics(self, module_proto)
    local compatible, existing_amount = true, nil
    local recipe_proto = self.recipe.proto
    local machine_proto = self.machine.proto

    if not self.recipe.valid or not self.machine.valid then compatible = false end

    if compatible then
        if recipe_proto == nil or (table_size(module_proto.limitations) ~= 0 and
          recipe_proto.use_limitations and not module_proto.limitations[recipe_proto.name]) then
            compatible = false
        end
    end

    if compatible then
        local allowed_effects = machine_proto.allowed_effects
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

    if compatible then
        for _, module in pairs(Line.get_in_order(self, "Module")) do
            if module.proto == module_proto then
                existing_amount = module.amount
                break
            end
        end
    end

    return {
        compatible = compatible,
        existing_amount = existing_amount
    }
end

-- Returns a table indicating the compatibility of the given module with this line and the given beacon
function Line.get_beacon_module_characteristics(self, beacon_proto, module_proto)
    local compatible = true
    local recipe_proto = self.recipe.proto
    local machine_proto = self.machine.proto

    if not self.recipe.valid or not self.machine.valid then compatible = false end

    if compatible then
        if recipe_proto == nil or (table_size(module_proto.limitations) ~= 0 and
          recipe_proto.use_limitations and not module_proto.limitations[recipe_proto.name]) then
            compatible = false
          end
    end

    if compatible then
        if machine_proto.allowed_effects == nil or beacon_proto.allowed_effects == nil then
            compatible = false
        else
            for effect_name, _ in pairs(module_proto.effects) do
                if machine_proto.allowed_effects[effect_name] == false or
                  beacon_proto.allowed_effects[effect_name] == false then
                    compatible = false
                end
            end
        end
    end

    return { compatible = compatible }
end


-- Returns the total effects influencing this line, including mining productivity
function Line.get_total_effects(self, player)
    local effects = cutil.shallowcopy(self.total_effects)

    -- Add mining productivity, if applicable
    local mining_productivity = 0
    if self.machine.proto.mining then
        local subfactory = self.parent.parent
        if subfactory.mining_productivity ~= nil then
            mining_productivity = (subfactory.mining_productivity / 100)
        else
            mining_productivity = player.force.mining_drill_productivity_bonus
        end
    end
    effects.productivity = effects.productivity + mining_productivity

    return effects
end


-- Updates the line attribute containing the total module effects of this line (modules+beacons)
function Line.summarize_effects(self)
    local module_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}

    -- Machine base productivity
    if not self.machine or not self.machine.proto then return end
    module_effects.productivity = module_effects.productivity + self.machine.proto.base_productivity

    -- Module effects
    for _, module in pairs(Line.get_in_order(self, "Module")) do
        for name, effect in pairs(module.proto.effects) do
            module_effects[name] = module_effects[name] + (effect.bonus * module.amount)
        end
    end

    -- Beacon effects
    if self.beacon ~= nil then
        for name, effect in pairs(self.beacon.total_effects) do
            module_effects[name] = module_effects[name] + effect
        end
    end

    self.total_effects = module_effects
end

-- Sorts modules in a deterministic fashion so they are in the same order for every line
-- Not a very efficient algorithm, but totally fine for the small (<10) amount of datasets
function Line.sort_modules(self)
    local next_position = 1
    local new_gui_positions = {}

    if global.all_modules == nil then return end
    for _, category in ipairs(global.all_modules.categories) do
        for _, module_proto in ipairs(category.modules) do
            for _, module in ipairs(Line.get_in_order(self, "Module")) do
                if module.category.name == category.name and module.proto.name == module_proto.name then
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
function Line.trim_modules(self)
    local module_count = Line.count_modules(self)
    local module_limit = self.machine.proto.module_limit or 0
    -- Return if the module count is within limits
    if module_count <= module_limit then return end

    local modules_to_remove = {}
    -- Traverse modules in reverse to trim them off the end
    for _, module in ipairs(Line.get_in_order(self, "Module", true)) do
        -- Remove a whole module if it brings the count to >= limit
        if module_count - module.amount >= module_limit then
            table.insert(modules_to_remove, module)
            module_count = module_count - module.amount

        -- Otherwise, diminish the amount on the module appropriately and break
        else
            local new_amount = module.amount - (module_count - module_limit)
            Line.change_module_amount(self, module, new_amount)
            break
        end
    end

    -- Remove superfluous modules (no re-sorting necessary)
    for _, module in pairs(modules_to_remove) do
        Line.remove(self, module)
    end
end


-- Update the validity of values associated tp this line
function Line.update_validity(self)
    self.valid = true

    -- Validate Recipe
    if not Recipe.update_validity(self.recipe) then
        self.valid = false
    end

    -- Validate Items + Modules
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item", Module = "Module"}
    if not run_validation_updates(self, classes) then
        self.valid = false
    end

    -- Validate Machine
    if not Machine.update_validity(self.machine, self) then
        self.valid = false
    end

    -- Validate Fuel
    if self.valid and self.fuel and not Fuel.update_validity(self.fuel, self) then
        self.valid = false
    end

    -- Validate module-amount
    if self.machine.valid and Line.count_modules(self) > (self.machine.proto.module_limit or 0) then
        self.valid = false
    end

    -- Validate beacon
    if self.beacon ~= nil and not Beacon.update_validity(self.beacon) then
        self.valid = false
    end

    -- Update modules to eventual changes in prototypes (only makes sense if valid)
    if self.valid then
        Line.sort_modules(self)
        Line.trim_modules(self)
        Line.summarize_effects(self)
    end

    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
-- (In general, Line Items are not repairable and can only be deleted)
function Line.attempt_repair(self, player)
    self.valid = true

    -- Repair Recipe
    if not self.recipe.valid and not Recipe.attempt_repair(self.recipe) then
        self.valid = false
    end

    -- Repair Items + Modules
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item", Module = "Module"}
    run_invalid_dataset_repair(player, self, classes)

    -- Repair Machine
    if self.valid and not self.machine.valid and not Machine.attempt_repair(self.machine) then
        if self.machine.category == nil then  -- No category means that it could not be repaired
            if self.valid then  -- If the line is still valid here, it has a valid recipe
                -- Try if a new line with the new category would be valid, remove it otherwise
                local new_line = Line.init(player, self.recipe)
                if new_line ~= false then
                    Floor.replace(self.parent, self, new_line)

                    -- Try to repair the machine again with the new category
                    self.machine.category = self.recipe.proto.category
                    if not Machine.attempt_repair(self.machine) then
                        self.valid = false
                    end
                else
                    self.valid = false
                end
            end
        else
            -- Set the machine to the default one; remove of none is compatible anymore
            -- (Recipe needs to be valid at this point, which it is)
            if not Line.change_machine(self, player, nil, nil) then
                self.valid = false
            end
        end
    end

    -- Repair Fuel
    if self.valid and self.fuel and not self.fuel.valid and not Fuel.attempt_repair(self.fuel, player) then
        self.valid = false
    end

    -- Repair Beacon
    if self.valid and self.beacon ~= nil and not Beacon.attempt_repair(self.beacon) then
        self.valid = false
    end

    -- Repair Modules
    if self.valid then
        Line.sort_modules(self)
        Line.trim_modules(self)
        Line.summarize_effects(self)
    end

    -- Repair subfloor (continues through recursively)
    if self.subfloor and not self.subfloor.valid and not Floor.attempt_repair(self.subfloor, player) then
        Subfactory.remove(self.subfloor.parent, self.subfloor)
        self.subfloor = nil
    end

    return self.valid
end