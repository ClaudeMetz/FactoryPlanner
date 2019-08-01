-- 'Class' representing an assembly line producing a single recipe
Line = {}

function Line.init(player, recipe, machine)
    local line = {
        recipe = recipe,
        percentage = 100,
        machine = nil,
        Module = Collection.init(),
        beacon = nil,
        total_effects = nil,
        energy_consumption = 0,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        fuel = nil,  -- gets set on first use, then stays set
        comment = nil,
        production_ratio = 0,
        subfloor = nil,
        valid = true,
        class = "Line"
    }
    
    -- If machine is specified, it gets used, otherwise it'll fall back to the default
    if machine == nil then
        -- Hack together a pseudo-category for machine.change to use to find the default
        line.machine = {category = { id = global.all_machines.map[recipe.proto.category] } }
    end
    -- Return false if no fitting machine can be found (needs error handling on the other end)
    if data_util.machine.change(player, line, machine, nil) == false then
        return false
    end

    for _, product in pairs(recipe.proto.products) do
        Line.add(line, Item.init_by_item(product, "Product", 0))
    end

    for _, ingredient in pairs(recipe.proto.ingredients) do
        Line.add(line, Item.init_by_item(ingredient, "Ingredient", 0))
    end

    -- Initialise the total_effects
    Line.summarize_effects(line)

    return line
end


-- Changes the amount of the given module on this line and optionally it's subfloor / parent line
function Line.change_module_amount(self, module, new_amount, no_recursion)
    module.amount = new_amount
    
    if self.subfloor ~= nil and not no_recursion then
        local sub_line = Floor.get(self.subfloor, "Line", 1)
        local sub_module = Line.get_by_name(sub_line, "Module", module.proto.name)
        Line.change_module_amount(self, sub_module, new_amount, true)
    elseif self.id == 1 and self.parent.origin_line and not no_recursion then
        local parent_module = Line.get_by_name(self.parent.origin_line, "Module", module.proto.name)
        Line.change_module_amount(self.parent.origin_line, parent_module, new_amount, true)
    end

    Line.summarize_effects(self)
end

-- Sets the given beacon on this line and optionally it's subfloor / parent line
function Line.set_beacon(self, beacon, no_recursion)
    if beacon ~= nil then beacon.parent = self end
    self.beacon = beacon
    
    if self.subfloor ~= nil and not no_recursion then
        local sub_line = Floor.get(self.subfloor, "Line", 1)
        Line.set_beacon(sub_line, util.table.deepcopy(beacon), true)
    elseif self.id == 1 and self.parent.origin_line and not no_recursion then
        Line.set_beacon(self.parent.origin_line, util.table.deepcopy(beacon), true)
    end

    if self.beacon ~= nil then Beacon.trim_modules(self.beacon) end
    Line.summarize_effects(self)
end


function Line.add(self, object, sort, no_recursion)
    object.parent = self
    local dataset = Collection.add(self[object.class], object)

    if dataset.class == "Module" then
        if self.subfloor ~= nil and not no_recursion then
            local sub_line = Floor.get(self.subfloor, "Line", 1)
            Line.add(sub_line, util.table.deepcopy(object), sort, true)
        elseif self.id == 1 and self.parent.origin_line and not no_recursion then
            Line.add(self.parent.origin_line, util.table.deepcopy(object), sort, true)
        end
        if sort then Line.sort_modules(self) end
        Line.summarize_effects(self)
    end

    return dataset
end

function Line.remove(self, dataset, sort, no_recursion)
    if dataset.class == "Module" then
        if self.subfloor ~= nil and not no_recursion then
            local sub_line = Floor.get(self.subfloor, "Line", 1)
            Line.remove(sub_line, util.table.deepcopy(dataset), sort, true)
        elseif self.id == 1 and self.parent.origin_line and not no_recursion then
            Line.remove(self.parent.origin_line, util.table.deepcopy(dataset), sort, true)
        end
    end
    
    Collection.remove(self[dataset.class], dataset)
    
    if dataset.class == "Module" then
        if sort then Line.sort_modules(self) end
        Line.summarize_effects(self)
    end
end

function Line.replace(self, dataset, object, sort, no_recursion)
    local dataset = Collection.replace(self[dataset.class], dataset, object)

    if dataset.class == "Module" then
        if self.subfloor ~= nil and not no_recursion then
            local sub_line = Floor.get(self.subfloor, "Line", 1)
            Line.replace(sub_line, util.table.deepcopy(dataset), object, sort, true)
        elseif self.id == 1 and self.parent.origin_line and not no_recursion then
            Line.replace(self.parent.origin_line, util.table.deepcopy(dataset), object, sort, true)
        end
        if sort then Line.sort_modules(self) end
        Line.summarize_effects(self)
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
    Collection.shift(self[dataset.class], dataset, direction)
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

    -- First, check for compatibility
    if table_size(module_proto.limitations) ~= 0 and not module_proto.limitations[self.recipe.proto.name] then
        compatible = false
    end

    if compatible then  -- if it's not compatible anyway, no point in continuing
        local allowed_effects = self.machine.proto.allowed_effects
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

    if compatible then  -- if it's not compatible anyway, no point in continuing
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

-- Updates the line attribute containing the total module effects of this line (modules+beacons)
function Line.summarize_effects(self)
    local module_effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0}

    -- Machine base productivity
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
        Line.remove(self, module, false)
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
    if not data_util.run_validation_updates(self, classes) then
        self.valid = false
    end

    -- Validate Machine
    if not Machine.update_validity(self.machine, self.recipe) then
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

    -- Validate Fuel
    if self.fuel ~= nil then
        local fuel_name = (type(self.fuel) == "string") and self.fuel or self.fuel.name
        local new_fuel_id = new.all_fuels.map[fuel_name]

        if new_fuel_id ~= nil then
            self.fuel = new.all_fuels.fuels[new_fuel_id]
        else
            self.fuel = self.fuel.name
            self.valid = false
        end
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
    data_util.run_invalid_dataset_repair(player, self, classes)

    -- Repair Machine
    if self.valid and not self.machine.valid and not Machine.attempt_repair(self.machine) then
        if self.machine.category == nil then  -- No category means that it could not be repaired
            if self.valid then  -- If the line is still valid here, it has a valid recipe
                -- Try if a new line with the new category would be valid, remove it otherwise
                local new_line = Line.init(player, self.recipe, nil)
                if new_line ~= false then
                    Floor.replace(self.parent, self, new_line)
                else
                    self.valid = false
                end
            end
        else
            -- Set the machine to the default one; remove of none is compatible anymore
            if not data_util.machine.change(player, self, nil, nil) then
                self.valid = false
            end
        end
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
    
    -- Repair Fuel
    if self.valid and self.fuel ~= nil and type(self.fuel) == "string" then
        local current_fuel_id = global.all_fuels.map[self.fuel]
        if current_fuel_id ~= nil then
            self.fuel = global.all_fuels.fuels[current_fuel_id]
        else
            -- If it is not found, set it to the default
            self.fuel = data_util.base_data.preferred_fuel(global)
        end
    end

    -- Repair subfloor (continues through recursively)
    if self.subfloor and not self.subfloor.valid and not Floor.attempt_repair(self.subfloor, player) then
        Subfactory.remove(self.subfloor.parent, self.subfloor)
    end

    return self.valid
end