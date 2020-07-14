-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(recipe)
    return {
        recipe = recipe,
        percentage = 100,
        machine = nil,
        beacon = nil,
        total_effects = nil,  -- initialized after a machine is set
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
end


function Line.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Line.remove(self, dataset)
    return Collection.remove(self[dataset.class], dataset)
end

function Line.replace(self, dataset, object)
    return Collection.replace(self[dataset.class], dataset, object)
end


function Line.set_percentage(self, percentage)
    self.percentage = percentage

    if self.subfloor then
        Floor.get(self.subfloor, "Line", 1).percentage = percentage
    elseif self.gui_position == 1 and self.parent.origin_line then
        self.parent.origin_line.percentage = percentage
    end
end

function Line.set_priority_product(self, priority_product_proto)
    self.priority_product_proto = priority_product_proto  -- can be nil

    if self.subfloor then
        Floor.get(self.subfloor, "Line", 1).priority_product_proto = priority_product_proto
    elseif self.gui_position == 1 and self.parent.origin_line then
        self.parent.origin_line.priority_product_proto = priority_product_proto
    end
end

function Line.set_beacon(self, beacon)
    self.beacon = beacon  -- can be nil

    if beacon then
        self.beacon.parent = self
        Beacon.trim_modules(self.beacon)
    end

    Line.summarize_effects(self, false, true)
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
function Line.change_machine(self, player, machine_proto, direction)
    -- Set the machine to the default one
    if machine_proto == nil and direction == nil then
        local machine_category_id = global.all_machines.map[self.recipe.proto.category]
        local default_machine_proto = prototyper.defaults.get(player, "machines", machine_category_id)

        -- If no default machine is found, this category has no machines
        if default_machine_proto == nil then return false end
        return Line.change_machine(self, player, default_machine_proto, nil)

    -- Set machine directly
    elseif machine_proto ~= nil and direction == nil then
        -- Try setting a higher tier machine until it sticks or nothing happens
        -- Returns false if no machine fits at all, so an appropriate error can be displayed
        if not Line.is_machine_applicable(self, machine_proto) then
            return Line.change_machine(self, player, machine_proto, "positive")

        else
            if not self.machine then
                self.machine = Machine.init_by_proto(machine_proto)
                self.machine.parent = self

                -- Initialize total_effects, now that the line has a machine
                Line.summarize_effects(self, false, false)

            else
                self.machine.proto = machine_proto

                -- Check if the fuel is still compatible, remove it otherwise
                if self.fuel and not (machine_proto.energy_type == "burner"
                  and machine_proto.burner.categories[self.fuel.proto.category]) then
                    self.fuel = nil
                end

                -- Adjust modules (ie. trim them if needed)
                Machine.normalize_modules(self.machine, false, true)

                -- Adjust beacon (ie. remove if machine does not allow beacons)
                if self.machine.proto.allowed_effects == nil then Line.set_beacon(self, nil) end
            end

            return true
        end

    -- Bump machine in the given direction
    elseif direction ~= nil then
        -- Uses the given machine proto, if given, otherwise bumps the line's existing machine
        machine_proto = machine_proto or self.machine.proto

        local machine_category_id = global.all_machines.map[machine_proto.category]
        local category_machines = global.all_machines.categories[machine_category_id].machines

        if direction == "positive" then
            if machine_proto.id < #category_machines then
                local new_machine = category_machines[machine_proto.id + 1]
                return Line.change_machine(self, player, new_machine, nil)
            else
                local message = {"fp.error_object_cant_be_up_downgraded", {"fp.machine"}, {"fp.upgraded"}}
                ui_util.message.enqueue(player, message, "error", 1, false)
                return false
            end
        else  -- direction == "negative"
            if machine_proto.id > 1 then
                local new_machine = category_machines[machine_proto.id - 1]
                return Line.change_machine(self, player, new_machine, nil)
            else
                local message = {"fp.error_object_cant_be_up_downgraded", {"fp.machine"}, {"fp.downgraded"}}
                ui_util.message.enqueue(player, message, "error", 1, false)
                return false
            end
        end
    end
end


-- Updates the line attribute containing the total module effects of this line (modules+beacons)
function Line.summarize_effects(self, summarize_machine, summarize_beacon)
    if self.subfloor ~= nil or self.machine == nil then return nil end

    if summarize_machine then Machine.summarize_effects(self.machine) end
    if summarize_beacon and self.beacon then Beacon.summarize_effects(self.beacon) end

    local module_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}

    local effects_table = {self.machine.total_effects}
    if self.beacon then table.insert(effects_table, self.beacon.total_effects) end

    for _, effect_table in pairs(effects_table) do
        for name, effect in pairs(effect_table) do
            module_effects[name] = module_effects[name] + effect
        end
    end

    self.total_effects = module_effects
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


-- Returns a table containing all relevant data for the given module in relation to this Line
function Line.get_machine_module_characteristics(self, module_proto)
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
        for _, module in pairs(Machine.get_in_order(self.machine, "Module")) do
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


-- Needs validation: recipe, machine, beacon, fuel?, priority_product_proto?, subfloor
function Line.validate(self)
    self.valid = true

    self.valid = Recipe.validate(self.recipe) and self.valid

    -- When this line has a subfloor, only the recipe and the subfloor need to be checked
    if self.subfloor then
        self.valid = Floor.validate(self.subfloor) and self.valid

    else
        self.valid = Machine.validate(self.machine) and self.valid


    end

    return self.valid
end

-- Needs repair: recipe, machine, beacon, fuel?, priority_product_proto?, subfloor
function Line.repair(self, player)
    self.valid = true

    if not self.recipe.valid then self.valid = Recipe.repair(self.recipe, nil) end

    if self.subfloor then
        if self.valid and not self.subfloor.valid then
            -- Repairing a floor always makes it valid, or removes it if left empty
            Floor.repair(self.subfloor, player)
        end

    else
        if self.valid and not self.machine.valid then
            self.valid = Machine.repair(self.machine, player)
        end


    end

    return self.valid
end