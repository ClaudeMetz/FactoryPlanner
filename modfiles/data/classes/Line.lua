-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(recipe)
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
        priority_product_proto = nil,  -- set by the user
        comment = nil,
        production_ratio = 0,
        uncapped_production_ratio = 0, -- used to calculate machine_choice-numbers
        subfloor = nil,
        valid = true,
        class = "Line"
    }

    -- Initialise total_effects
    Line.summarize_effects(line)

    return line
end


function Line.add(self, object)
    object.parent = self

    local dataset = Collection.add(self[object.class], object)
    if dataset.class == "Module" then Line.normalize_modules(self) end

    return dataset
end

function Line.remove(self, dataset)
    local removed_gui_position = Collection.remove(self[dataset.class], dataset)
    if dataset.class == "Module" then Line.normalize_modules(self) end

    return removed_gui_position
end

function Line.replace(self, dataset, object)
    dataset = Collection.replace(self[dataset.class], dataset, object)
    if dataset.class == "Module" then Line.normalize_modules(self) end

    return dataset
end


function Line.set_percentage(self, percentage)
    self.percentage = percentage

    if self.subfloor then
        Floor.get(self.subfloor, "Line", 1).percentage = percentage
    elseif self.gui_position == 1 and self.parent.origin_line then
        self.parent.origin_line.percentage = percentage
    end
end

function Line.set_beacon(self, beacon)
    self.beacon = beacon  -- beacon can be nil

    if beacon then
        self.beacon.parent = self
        Beacon.trim_modules(self.beacon)
    end

    Line.summarize_effects(self)
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

function Line.get_by_type_and_name(self, class, type, name)
    return Collection.get_by_type_and_name(self[class], type, name)
end

function Line.shift(self, dataset, direction)
    return Collection.shift(self[dataset.class], dataset, direction)
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

            new_machine.parent = self
            self.machine = new_machine

            -- Adjust modules (ie. trim them if needed)
            Line.trim_modules(self)
            Line.summarize_effects(self)

            -- Adjust beacon (ie. remove if machine does not allow beacons)
            if self.machine.proto.allowed_effects == nil then Line.set_beacon(self, nil) end

            return true
        end

    -- Bump machine in the given direction
    elseif direction ~= nil then
        machine = machine or self.machine  -- takes given machine, if available
        local machine_category_id = global.all_machines.map[machine.proto.category]
        local category_machines = global.all_machines.categories[machine_category_id].machines

        if direction == "positive" then
            if machine.proto.id < #category_machines then
                local new_machine = category_machines[machine.proto.id + 1]
                return Line.change_machine(self, player, new_machine, nil)
            else
                local message = {"fp.error_object_cant_be_up_downgraded", {"fp.machine"}, {"fp.upgraded"}}
                ui_util.message.enqueue(player, message, "error", 1, false)
                return false
            end
        else  -- direction == "negative"
            if machine.proto.id > 1 then
                local new_machine = category_machines[machine.proto.id - 1]
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
            Module.change_amount(module, new_amount)
            break
        end
    end

    -- Remove superfluous modules (no re-sorting necessary)
    for _, module in pairs(modules_to_remove) do
        Line.remove(self, module)
    end
end


-- Needs validation: recipe, machine, Module, beacon, fuel?, priority_product_proto, subfloor
function Line.validate(self)
    self.valid = true

    self.valid = Recipe.validate(self.recipe) and self.valid

    self.valid = Machine.validate(self.machine) and self.valid


    if self.subfloor then
        self.valid = Floor.validate(self.subfloor) and self.valid
    end

    return self.valid
end

-- Needs repair: recipe, machine, Module, beacon, fuel?, priority_product_proto, subfloor
function Line.repair(self, player)
    self.valid = true

    if not self.recipe.valid then
        self.valid = Recipe.repair(self.recipe)
    end

    if self.valid and not self.machine.valid then
        self.valid = Machine.repair(self.machine)
    end


    if self.valid and self.subfloor and not self.subfloor.valid then
        -- Repairing a floor always makes it valid, or removes it if left empty
        Floor.repair(self.subfloor, player)
    end

    return self.valid
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
                local new_line = Line.init(self.recipe)
                if Line.change_machine(new_line, player, nil, nil) == false then
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